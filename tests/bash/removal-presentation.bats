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
[[ "${DOTNET_ROOT:-}" == "$(cd "$(dirname "$0")" && pwd)" ]] || exit 82
[[ "${DOTNET_MULTILEVEL_LOOKUP:-}" == "0" ]] || exit 83
[[ "${DOTNET_SKIP_FIRST_TIME_EXPERIENCE:-}" == "1" ]] || exit 84
[[ "${DOTNET_CLI_TELEMETRY_OPTOUT:-}" == "1" ]] || exit 85
[[ "${DOTNET_NOLOGO:-}" == "true" ]] || exit 86
[[ "${DOTNET_GENERATE_ASPNET_CERTIFICATE:-}" == "false" ]] || exit 87
[[ "${DOTNET_ADD_GLOBAL_TOOLS_TO_PATH:-}" == "false" ]] || exit 88
[[ "${DOTNET_CLI_HOME:-}" == "$PWD" ]] || exit 89
[[ ! -e "$PWD/global.json" ]] || exit 90
printf '%s\n' "$PWD" > "$SDK_TEST_SHUTDOWN_WORK_DIR_MARKER"
printf '%s\n' 'child shutdown chatter'
EOF
    chmod +x "$install_dir/dotnet"

    cd "$ambient_dir"
    run env HOME="$test_home" DOTNET_ROOT="$test_root/wrong-root" DOTNET_MULTILEVEL_LOOKUP=1 DOTNET_CLI_HOME="$test_root/wrong-home" DOTNET_SKIP_FIRST_TIME_EXPERIENCE=0 DOTNET_CLI_TELEMETRY_OPTOUT=0 SDK_TEST_SHUTDOWN_WORK_DIR_MARKER="$marker" "$tool_path" remove "$version" --yes
    cd "$repo_root"

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

@test "verified early SDKs require distinct explicit unsupported-shutdown approval" {
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
    [ "$status" -ne 0 ]
    [ -d "$install_dir" ]

    run env HOME="$test_home" "$tool_path" remove "$version" --yes --allow-unsupported-shutdown
    [ "$status" -eq 0 ]
    [[ "$output" == *"Other build processes may remain"* ]]
    [ ! -d "$install_dir" ]
  done
}

@test "2.1.105 requires successful SDK-local Roslyn shutdown before removal" {
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
    SDK_TEST_ROSLYN_FAILURE=true "$tool_path" remove "$version" --yes --allow-unsupported-shutdown
  [ "$status" -ne 0 ]
  [ -d "$install_dir" ]
  [ ! -e "$marker" ]

  run env HOME="$test_home" SDK_TEST_ROSLYN_MARKER="$marker" \
    "$tool_path" remove "$version" --yes --allow-unsupported-shutdown
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
  run env HOME="$test_home" "$tool_path" remove "$version" --yes --allow-unsupported-shutdown
  [ "$status" -ne 0 ]
  [ -d "$install_dir" ]

  cat > "$install_dir/dotnet" <<'EOF'
#!/usr/bin/env bash
if [[ "$1 $2" == "build-server --help" ]]; then exit 0; fi
if [[ "$1 $2" == "build-server shutdown" ]]; then exit 74; fi
exit 1
EOF
  chmod +x "$install_dir/dotnet"
  run env HOME="$test_home" "$tool_path" remove "$version" --yes --allow-unsupported-shutdown
  [ "$status" -ne 0 ]
  [ -d "$install_dir" ]

  unknown="$tool_root/1.1.99"
  mkdir -p "$unknown/sdk/1.1.99"
  cp "$install_dir/dotnet" "$unknown/dotnet"
  run env HOME="$test_home" "$tool_path" remove 1.1.99 --yes --allow-unsupported-shutdown
  [ "$status" -ne 0 ]
  [ -d "$unknown" ]
}

@test "legacy bypass is Remove-only" {
  run env HOME="$test_home" "$tool_path" list --allow-unsupported-shutdown
  [ "$status" -ne 0 ]
  [[ "$output" == *"supported only with Remove"* ]]
}

@test "destructive warning has explicit blank boundaries in source" {
  warning_line="$(grep -n 'tool_warn "Isolated SDK \$VERSION will be removed from \$install_dir"' "$repo_root/isolated-dotnet-sdk.sh" | cut -d: -f1)"
  [ -n "$warning_line" ]

  previous_line="$(sed -n "$((warning_line - 1))p" "$repo_root/isolated-dotnet-sdk.sh")"
  next_line="$(sed -n "$((warning_line + 1))p" "$repo_root/isolated-dotnet-sdk.sh")"

  [[ "$previous_line" =~ ^[[:space:]]*echo[[:space:]]*$ ]]
  [[ "$next_line" =~ ^[[:space:]]*echo[[:space:]]*$ ]]
}
