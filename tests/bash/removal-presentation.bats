#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-removal-presentation.XXXXXX")"
  test_home="$test_root/home"
  tool_root="$test_home/dotnet-sdks"
  tool_path="$tool_root/isolated-dotnet-sdk.sh"
  mkdir -p "$tool_root"
  cp "$repo_root/isolated-dotnet-sdk.sh" "$tool_path"
  chmod +x "$tool_path"
}

teardown() {
  rm -rf "$test_root"
}

@test "removal shutdown suppresses successful child chatter and scopes first-run controls" {
  version='99.0.100'
  install_dir="$tool_root/$version"
  mkdir -p "$install_dir"
  cat > "$install_dir/dotnet" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${DOTNET_NOLOGO:-}" == "true" ]] || exit 81
[[ "${DOTNET_GENERATE_ASPNET_CERTIFICATE:-}" == "false" ]] || exit 82
[[ "${DOTNET_ADD_GLOBAL_TOOLS_TO_PATH:-}" == "false" ]] || exit 83
printf '%s\n' 'child shutdown chatter'
EOF
  chmod +x "$install_dir/dotnet"

  run env HOME="$test_home" "$tool_path" remove "$version" --yes

  [ "$status" -eq 0 ]
  [[ "$output" != *"child shutdown chatter"* ]]
  [[ "$output" == *"Shutting down build servers for SDK $version..."* ]]
  [[ "$output" == *"Isolated SDK $version was removed."* ]]
}

@test "legacy SDK shutdown uses the isolated host and a temporary neutral environment" {
  ambient_dir="$test_root/ambient"
  mkdir -p "$ambient_dir"
  printf '%s\n' '{"sdk":{"version":"0.0.0"}}' > "$ambient_dir/global.json"

  for version in 2.1.818 2.2.207; do
    install_dir="$tool_root/$version"
    marker="$test_root/shutdown-$version.workdir"
    mkdir -p "$install_dir"
    cat > "$install_dir/dotnet" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == "build-server" && "$2" == "shutdown" ]] || exit 81
[[ "$(cd "$DOTNET_ROOT" && pwd -P)" == "$(cd "$(dirname "$0")" && pwd -P)" ]] || exit 82
[[ "${DOTNET_MULTILEVEL_LOOKUP:-}" == "0" ]] || exit 83
[[ "${DOTNET_SKIP_FIRST_TIME_EXPERIENCE:-}" == "1" ]] || exit 84
[[ "${DOTNET_CLI_TELEMETRY_OPTOUT:-}" == "1" ]] || exit 85
[[ "${DOTNET_NOLOGO:-}" == "true" ]] || exit 86
[[ "${DOTNET_GENERATE_ASPNET_CERTIFICATE:-}" == "false" ]] || exit 87
[[ "${DOTNET_ADD_GLOBAL_TOOLS_TO_PATH:-}" == "false" ]] || exit 88
[[ "$(cd "$DOTNET_CLI_HOME" && pwd -P)" == "$(pwd -P)" ]] || exit 89
[[ ! -e "$PWD/global.json" ]] || exit 90
printf '%s\n' "$PWD" > "$SDK_TEST_SHUTDOWN_WORK_DIR_MARKER"
printf '%s\n' 'child shutdown chatter'
EOF
    chmod +x "$install_dir/dotnet"

    cd "$ambient_dir"
    run env HOME="$test_home" DOTNET_ROOT="$test_root/wrong-root" DOTNET_MULTILEVEL_LOOKUP=1 DOTNET_CLI_HOME="$test_root/wrong-home" DOTNET_SKIP_FIRST_TIME_EXPERIENCE=0 DOTNET_CLI_TELEMETRY_OPTOUT=0 SDK_TEST_SHUTDOWN_WORK_DIR_MARKER="$marker" "$tool_path" remove "$version" --yes
    cd "$repo_root"

    if [[ "$status" -ne 0 ]]; then
      printf 'SDK %s shutdown test failed (exit %s): %s\n' "$version" "$status" "$output" >&3
    fi
    [ "$status" -eq 0 ]
    [[ "$output" == *"Isolated SDK $version was removed."* ]]
    [[ "$output" != *"child shutdown chatter"* ]]
    [ -f "$marker" ]
    [ ! -d "$(cat "$marker")" ]
    [ ! -d "$install_dir" ]
  done
}

@test "recognized legacy SDK startup errors still block deletion" {
  version='2.2.207'
  install_dir="$tool_root/$version"
  sibling_dir="$tool_root/2.1.818"
  mkdir -p "$install_dir" "$sibling_dir"
  printf '%s\n' 'preserve sibling' > "$sibling_dir/sentinel.txt"
  cat > "$install_dir/dotnet" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'System.EntryPointNotFoundException: hostfxr_set_error_writer' >&2
exit 72
EOF
  chmod +x "$install_dir/dotnet"

  run env HOME="$test_home" "$tool_path" remove "$version" --yes

  [ "$status" -ne 0 ]
  [[ "$output" == *"Build-server shutdown failed for SDK $version with exit code 72."* ]]
  [[ "$output" != *"Isolated SDK $version was removed."* ]]
  [ -d "$install_dir" ]
  [ -f "$sibling_dir/sentinel.txt" ]
}

@test "verified early SDKs remove without a second opt-in" {
  for version in 1.0.4 1.1.5 1.1.14 2.0.3; do
    install_dir="$tool_root/$version"
    mkdir -p "$install_dir/sdk/$version"
    cat > "$install_dir/dotnet" <<'EOF'
#!/usr/bin/env bash
if [[ "$1 $2" == "build-server --help" ]]; then
  echo 'No executable found matching command "dotnet-build-server"'
  exit 1
fi
if [[ "$1 $2" == "buildserver --help" ]]; then
  echo 'No executable found matching command "dotnet-buildserver"'
  exit 1
fi
exit 99
EOF
    chmod +x "$install_dir/dotnet"

    run env HOME="$test_home" "$tool_path" remove "$version" --yes
    [ "$status" -eq 0 ]
    [[ "$output" == *"Other build processes may remain"* ]]
    [ ! -d "$install_dir" ]
  done
}

@test "2.1.105 requires SDK-local Roslyn shutdown automatically" {
  version='2.1.105'
  install_dir="$tool_root/$version"
  compiler="$install_dir/sdk/$version/Roslyn/bincore/VBCSCompiler.dll"
  mkdir -p "$(dirname "$compiler")"
  printf 'fixture' > "$compiler"
  cat > "$install_dir/dotnet" <<'EOF'
#!/usr/bin/env bash
if [[ "$1 $2" == "build-server --help" ]]; then
  echo 'No executable found matching command "dotnet-build-server"'
  exit 1
fi
if [[ "$1 $2" == "buildserver --help" ]]; then
  echo 'No executable found matching command "dotnet-buildserver"'
  exit 1
fi
if [[ "$1" == exec && "$3" == -shutdown && -f "$2" ]]; then
  [[ "${SDK_TEST_ROSLYN_FAILURE:-}" == true ]] && exit 77
  printf '%s' "$2" > "$SDK_TEST_ROSLYN_MARKER"
  exit 0
fi
exit 98
EOF
  chmod +x "$install_dir/dotnet"
  marker="$test_root/roslyn.txt"
  run env HOME="$test_home" SDK_TEST_ROSLYN_MARKER="$marker" \
    SDK_TEST_ROSLYN_FAILURE=true "$tool_path" remove "$version" --yes
  [ "$status" -ne 0 ]
  [ -d "$install_dir" ]
  [ ! -e "$marker" ]

  run env HOME="$test_home" SDK_TEST_ROSLYN_MARKER="$marker" \
    "$tool_path" remove "$version" --yes
  [ "$status" -eq 0 ]
  [ "$(cat "$marker")" = "$compiler" ]
  [ ! -d "$install_dir" ]
}

@test "unsupported opt-in never bypasses unexpected errors or supported shutdown failures" {
  version='1.0.4'
  install_dir="$tool_root/$version"
  mkdir -p "$install_dir/sdk/$version"
  cat > "$install_dir/dotnet" <<'EOF'
#!/usr/bin/env bash
if [[ "$2" == --help ]]; then
  echo 'unrecognized capability error'
  exit 1
fi
exit 73
EOF
  chmod +x "$install_dir/dotnet"
  run env HOME="$test_home" "$tool_path" remove "$version" --yes
  [ "$status" -ne 0 ]
  [ -d "$install_dir" ]

  cat > "$install_dir/dotnet" <<'EOF'
#!/usr/bin/env bash
if [[ "$1 $2" == "build-server --help" ]]; then exit 0; fi
if [[ "$1 $2" == "build-server shutdown" ]]; then exit 74; fi
exit 1
EOF
  chmod +x "$install_dir/dotnet"
  run env HOME="$test_home" "$tool_path" remove "$version" --yes
  [ "$status" -ne 0 ]
  [ -d "$install_dir" ]

  unknown="$tool_root/1.1.99"
  mkdir -p "$unknown/sdk/1.1.99"
  cp "$install_dir/dotnet" "$unknown/dotnet"
  run env HOME="$test_home" "$tool_path" remove 1.1.99 --yes --allow-unsupported-shutdown
  [ "$status" -ne 0 ]
  [ -d "$unknown" ]
}

@test "early SDK with compiler-server payload cannot bypass shutdown" {
  version='2.0.3'
  install_dir="$tool_root/$version"
  mkdir -p "$install_dir/sdk/$version/Roslyn"
  touch "$install_dir/sdk/$version/Roslyn/VBCSCompiler.dll"
  cat > "$install_dir/dotnet" <<'EOF'
#!/usr/bin/env bash
if [[ "$1 $2" == "build-server --help" ]]; then
  echo 'No executable found matching command "dotnet-build-server"'
  exit 1
fi
if [[ "$1 $2" == "buildserver --help" ]]; then
  echo 'No executable found matching command "dotnet-buildserver"'
  exit 1
fi
exit 97
EOF
  chmod +x "$install_dir/dotnet"
  run env HOME="$test_home" "$tool_path" remove "$version" --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unrecognized compiler-server payload"* ]]
  [ -d "$install_dir" ]
}

@test "2.1.105 missing compiler payload fails closed even with opt-in" {
  version='2.1.105'
  install_dir="$tool_root/$version"
  mkdir -p "$install_dir/sdk/$version"
  cat > "$install_dir/dotnet" <<'EOF'
#!/usr/bin/env bash
if [[ "$1 $2" == "build-server --help" ]]; then
  echo 'No executable found matching command "dotnet-build-server"'
  exit 1
fi
if [[ "$1 $2" == "buildserver --help" ]]; then
  echo 'No executable found matching command "dotnet-buildserver"'
  exit 1
fi
exit 97
EOF
  chmod +x "$install_dir/dotnet"
  run env HOME="$test_home" "$tool_path" remove "$version" --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"Legacy compiler shutdown unavailable"* ]]
  [ -d "$install_dir" ]
}

@test "a recognized alternate historical shutdown command must return zero" {
  version='1.0.4'
  install_dir="$tool_root/$version"
  mkdir -p "$install_dir/sdk/$version"
  cat > "$install_dir/dotnet" <<'EOF'
#!/usr/bin/env bash
if [[ "$1 $2" == "build-server --help" ]]; then
  echo 'No executable found matching command "dotnet-build-server"'
  exit 1
fi
if [[ "$1 $2" == "buildserver --help" ]]; then exit 0; fi
if [[ "$1 $2" == "buildserver shutdown" ]]; then exit 79; fi
exit 97
EOF
  chmod +x "$install_dir/dotnet"
  run env HOME="$test_home" "$tool_path" remove "$version" --yes
  [ "$status" -ne 0 ]
  [ -d "$install_dir" ]
}

@test "legacy bypass is Remove-only" {
  run env HOME="$test_home" "$tool_path" list --allow-unsupported-shutdown
  [ "$status" -ne 0 ]
  [[ "$output" == *"supported only with Remove"* ]]
}

@test "destructive warning has explicit blank boundaries in source" {
  warning_line="$(grep -n 'tool_warn "Isolated SDK \$VERSION will be removed from \$install_dir"' "$repo_root/isolated-dotnet-sdk.sh" | cut -d: -f1)"
  [ -n "$warning_line" ]

  preceding_block="$(sed -n "$((warning_line - 6)),$((warning_line - 1))p" "$repo_root/isolated-dotnet-sdk.sh")"
  following_block="$(sed -n "$((warning_line + 1)),$((warning_line + 5))p" "$repo_root/isolated-dotnet-sdk.sh")"

  # The outer selection boundary retains the separator when no clear occurred;
  # both initial and incomplete-removal warning paths share its trailing blank.
  [[ "$preceding_block" == *'if [[ "$selected_interactively" != "true" ]]; then'* ]]
  [[ "$preceding_block" == *$'\n        echo\n'* ]]
  [[ "$preceding_block" == *'if [[ "$recovery" == "true" ]]; then'* ]]
  [[ "$following_block" == *'if [[ "$recovery" != "true" && "$host_available" != "true" ]]; then'* ]]
  [[ "$following_block" == *$'\n    echo'* ]]
}

@test "partial removal remains retryable after SDK host loss" {
  version='99.0.100'
  install_dir="$tool_root/$version"
  fake_bin="$test_root/fake-rm-bin"
  mkdir -p "$install_dir" "$fake_bin"
  printf '%s\n' "locked content" > "$install_dir/locked.txt"
  cat > "$install_dir/dotnet" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$install_dir/dotnet"
  cat > "$fake_bin/rm" <<'EOF'
#!/usr/bin/env bash
if [[ "${SDK_TEST_LOCK_REMOVAL:-}" == "true" && "$*" == *"/locked.txt"* ]]; then
  exit 77
fi
exec /bin/rm "$@"
EOF
  chmod +x "$fake_bin/rm"

  run env HOME="$test_home" PATH="$fake_bin:$PATH" SDK_TEST_LOCK_REMOVAL=true \
    "$tool_path" remove "$version" --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"incomplete"* ]]
  [ ! -e "$install_dir/dotnet" ]
  [[ "$output" != *"was removed."* ]]

  run env HOME="$test_home" PATH="$fake_bin:$PATH" SDK_TEST_LOCK_REMOVAL=true \
    "$tool_path" remove "$version" --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"incomplete"* ]]
  [ -f "$tool_root/.pending-removals/$version" ]

  run env HOME="$test_home" "$tool_path" remove "$version" --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"was removed."* ]]
  [ ! -e "$install_dir" ]
  [ ! -e "$tool_root/.pending-removals/$version" ]
}

@test "partial removal is visible in Remove picker but not as installed SDK" {
  version='99.0.101'
  install_dir="$tool_root/$version"
  fake_bin="$test_root/fake-rm-bin"
  mkdir -p "$install_dir" "$fake_bin"
  printf 'locked' > "$install_dir/locked.txt"
  cat > "$install_dir/dotnet" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$install_dir/dotnet"
  cat > "$fake_bin/rm" <<'EOF'
#!/usr/bin/env bash
if [[ "${SDK_TEST_LOCK_REMOVAL:-}" == "true" && "$*" == *"/locked.txt"* ]]; then
  exit 77
fi
exec /bin/rm "$@"
EOF
  chmod +x "$fake_bin/rm"

  run env HOME="$test_home" PATH="$fake_bin:$PATH" SDK_TEST_LOCK_REMOVAL=true \
    "$tool_path" remove "$version" --yes
  [ "$status" -ne 0 ]

  run bash -c 'printf "q\n" | env HOME="$1" "$2" remove' _ "$test_home" "$tool_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$version (incomplete removal)"* ]]

  run env HOME="$test_home" "$tool_path" list
  [ "$status" -eq 0 ]
  [[ "$output" != *"$version  $install_dir"* ]]

  run env HOME="$test_home" "$tool_path" remove "$version" --yes
  [ "$status" -eq 0 ]
}

@test "an incomplete removal retry needs normal confirmation" {
  version='99.0.102'
  install_dir="$tool_root/$version"
  fake_bin="$test_root/fake-rm-bin"
  mkdir -p "$install_dir" "$fake_bin"
  printf 'locked' > "$install_dir/locked.txt"
  cat > "$install_dir/dotnet" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$install_dir/dotnet"
  cat > "$fake_bin/rm" <<'EOF'
#!/usr/bin/env bash
if [[ "${SDK_TEST_LOCK_REMOVAL:-}" == true && "$*" == *"/locked.txt"* ]]; then
  exit 77
fi
exec /bin/rm "$@"
EOF
  chmod +x "$fake_bin/rm"
  run env HOME="$test_home" PATH="$fake_bin:$PATH" SDK_TEST_LOCK_REMOVAL=true \
    "$tool_path" remove "$version" --yes
  [ "$status" -ne 0 ]
  [ -e "$tool_root/.pending-removals/$version" ]

  run bash -c 'printf "n\n" | env HOME="$1" "$2" remove "$3"' \
    _ "$test_home" "$tool_path" "$version"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removal cancelled."* ]]
  [ -e "$tool_root/.pending-removals/$version" ]

  run env HOME="$test_home" "$tool_path" remove "$version" --yes
  [ "$status" -eq 0 ]
  [ ! -e "$tool_root/.pending-removals/$version" ]
}

@test "tampered partial-removal proof cannot delete another directory" {
  version='99.0.103'
  install_dir="$tool_root/$version"
  fake_bin="$test_root/fake-rm-bin"
  mkdir -p "$install_dir" "$fake_bin"
  printf 'locked' > "$install_dir/locked.txt"
  cat > "$install_dir/dotnet" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$install_dir/dotnet"
  cat > "$fake_bin/rm" <<'EOF'
#!/usr/bin/env bash
if [[ "${SDK_TEST_LOCK_REMOVAL:-}" == true && "$*" == *"/locked.txt"* ]]; then
  exit 77
fi
exec /bin/rm "$@"
EOF
  chmod +x "$fake_bin/rm"

  run env HOME="$test_home" PATH="$fake_bin:$PATH" SDK_TEST_LOCK_REMOVAL=true \
    "$tool_path" remove "$version" --yes
  [ "$status" -ne 0 ]
  [ -f "$tool_root/.pending-removals/$version" ]

  sibling="$tool_root/99.0.104"
  mkdir -p "$sibling"
  printf 'do not delete' > "$sibling/data.txt"
  printf 'bad-token' > "$tool_root/.pending-removals/$version"
  run env HOME="$test_home" "$tool_path" remove "$version" --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid incomplete-removal recovery token"* ]]
  [ "$(cat "$sibling/data.txt")" = 'do not delete' ]
}

@test "replacing a quarantined recovery target with a symlink is rejected" {
  version='99.0.105'
  install_dir="$tool_root/$version"
  fake_bin="$test_root/fake-rm-bin"
  mkdir -p "$install_dir" "$fake_bin"
  printf 'locked' > "$install_dir/locked.txt"
  cat > "$install_dir/dotnet" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$install_dir/dotnet"
  cat > "$fake_bin/rm" <<'EOF'
#!/usr/bin/env bash
if [[ "${SDK_TEST_LOCK_REMOVAL:-}" == true && "$*" == *"/locked.txt"* ]]; then
  exit 77
fi
exec /bin/rm "$@"
EOF
  chmod +x "$fake_bin/rm"
  run env HOME="$test_home" PATH="$fake_bin:$PATH" SDK_TEST_LOCK_REMOVAL=true \
    "$tool_path" remove "$version" --yes
  [ "$status" -ne 0 ]
  token="$(cat "$tool_root/.pending-removals/$version")"
  stage="$tool_root/.removing-$version-$token"
  [ -d "$stage" ]
  preserved="$test_root/preserved"
  mv "$stage" "$preserved"
  mkdir -p "$test_root/unrelated"
  printf 'protect' > "$test_root/unrelated/keep.txt"
  ln -s "$test_root/unrelated" "$stage"

  run env HOME="$test_home" "$tool_path" remove "$version" --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unsafe incomplete-removal target"* ]]
  [ "$(cat "$test_root/unrelated/keep.txt")" = "protect" ]
}


@test "Remove discovers version folders without hosts and excludes unrelated or linked folders" {
  version='9.0.115'
  install_dir="$tool_root/$version"
  mkdir -p "$install_dir" "$tool_root/notes" "$test_root/outside"
  printf 'preserve' > "$tool_root/notes/readme.txt"
  printf 'outside' > "$test_root/outside/keep.txt"
  ln -s "$test_root/outside" "$tool_root/7.0.400"
  run bash -c 'printf "q\n" | env HOME="$1" "$2" remove' _ "$test_home" "$tool_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$version (incomplete)"* ]]
  [[ "$output" != *"7.0.400"* ]]
  [[ "$output" != *"notes"* ]]

  run env HOME="$test_home" "$tool_path" remove "$version" --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"cannot be shut down"* ]]
  [[ "$output" == *"Isolated SDK $version was removed."* ]]
  [ ! -e "$install_dir" ]
  [ "$(cat "$tool_root/notes/readme.txt")" = preserve ]
  [ "$(cat "$test_root/outside/keep.txt")" = outside ]
}

@test "No-host Remove requires ordinary confirmation and supports an unexecutable host" {
  version='9.0.116'
  install_dir="$tool_root/$version"
  mkdir -p "$install_dir"
  printf 'not executable' > "$install_dir/dotnet"

  run bash -c 'printf "n\n" | env HOME="$1" "$2" remove "$3"' _ "$test_home" "$tool_path" "$version"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removal cancelled."* ]]
  [ -e "$install_dir/dotnet" ]

  run env HOME="$test_home" "$tool_path" remove "$version" --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"cannot be shut down"* ]]
  [ ! -e "$install_dir" ]
}

@test "Remove rejects invalid version names and linked SDK directories without touching their targets" {
  mkdir -p "$tool_root/notes" "$test_root/foreign"
  printf 'unrelated' > "$tool_root/notes/keep.txt"
  printf 'external' > "$test_root/foreign/keep.txt"
  ln -s "$test_root/foreign" "$tool_root/9.0.117"
  run env HOME="$test_home" "$tool_path" remove notes --yes
  [ "$status" -ne 0 ]
  [ -e "$tool_root/notes/keep.txt" ]
  run env HOME="$test_home" "$tool_path" remove 9.0.117 --yes
  [ "$status" -ne 0 ]
  [ "$(cat "$test_root/foreign/keep.txt")" = external ]
}

@test "Failed directory rename leaves the original SDK and no incomplete removal success" {
  version='9.0.118'
  install_dir="$tool_root/$version"
  fake_bin="$test_root/rename-tools"
  mkdir -p "$install_dir" "$fake_bin"
  printf 'retain' > "$install_dir/keep.txt"
  cat > "$fake_bin/mv" <<'EOF'
#!/usr/bin/env bash
exit 71
EOF
  chmod +x "$fake_bin/mv"

  run env HOME="$test_home" PATH="$fake_bin:$PATH" "$tool_path" remove "$version" --yes
  [ "$status" -ne 0 ]
  [[ "$output" != *"was removed."* ]]
  [ "$(cat "$install_dir/keep.txt")" = retain ]
  [ ! -e "$tool_root/.pending-removals/$version" ]

  run env HOME="$test_home" "$tool_path" remove "$version" --yes
  [ "$status" -eq 0 ]
  [ ! -d "$install_dir" ]
}
