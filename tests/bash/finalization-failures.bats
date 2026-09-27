#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-finalization.XXXXXX")"
  test_home="$test_root/home"
  tool_root="$test_home/dotnet-sdks"
  tool_path="$tool_root/isolated-dotnet-sdk.sh"
  version='99.0.100'
  install_dir="$tool_root/$version"

  mkdir -p "$tool_root"
  cp "$repo_root/isolated-dotnet-sdk.sh" "$tool_path"
  chmod +x "$tool_path"
}

teardown() {
  rm -rf "$test_root"
}

write_successful_install_seams() {
  local fake_bin="$1"

  cat > "$fake_bin/dotnet" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

  cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
out_file=''
while [[ $# -gt 0 ]]; do
  if [[ "$1" == '-o' ]]; then
    out_file="$2"
    shift 2
  else
    shift
  fi
done
cat > "$out_file" <<'INSTALLER'
#!/usr/bin/env bash
set -euo pipefail
install_dir=''
version=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-dir) install_dir="$2"; shift 2 ;;
    --version) version="$2"; shift 2 ;;
    *) shift ;;
  esac
done
mkdir -p "$install_dir"
cat > "$install_dir/dotnet" <<DOTNET
#!/usr/bin/env bash
printf '%s\\n' "$version [/fake]"
exit 0
DOTNET
chmod +x "$install_dir/dotnet"
exit 0
INSTALLER
EOF

  chmod +x "$fake_bin/dotnet" "$fake_bin/curl"
}

@test "promotion command failure cleans transaction state and reports no success" {
  fake_bin="$test_root/promotion-bin"
  mkdir -p "$fake_bin"
  write_successful_install_seams "$fake_bin"

  cat > "$fake_bin/mv" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'promotion-move-failed' >&2
exit 82
EOF
  chmod +x "$fake_bin/mv"

  run env HOME="$test_home" PATH="$fake_bin:$PATH" "$tool_path" install "$version" --yes

  [ "$status" -ne 0 ]
  [[ "$output" == *"Unable to promote isolated SDK $version into $install_dir with exit code 82."* ]]
  [[ "$output" != *"installation completed successfully"* ]]
  [ ! -e "$install_dir" ]
  ! compgen -G "$tool_root/.install-$version.*" >/dev/null
  ! compgen -G "$tool_root/dotnet-install.sh.*" >/dev/null
}

@test "bootstrap final replacement failure preserves the saved tool and cleans its candidate" {
  source_copy="$test_root/isolated-dotnet-sdk-source.sh"
  fake_bin="$test_root/bootstrap-bin"
  mkdir -p "$fake_bin"
  cp "$repo_root/isolated-dotnet-sdk.sh" "$source_copy"
  chmod +x "$source_copy"
  printf '%s\n' 'preserve-saved-tool' > "$tool_path"

  cat > "$fake_bin/mv" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'bootstrap-move-failed' >&2
exit 83
EOF
  chmod +x "$fake_bin/mv"

  run env HOME="$test_home" PATH="$fake_bin:$PATH" "$source_copy" list

  [ "$status" -ne 0 ]
  [ "$(cat "$tool_path")" = 'preserve-saved-tool' ]
  [ -z "$(find "$tool_root" -maxdepth 1 -type f -name '.isolated-dotnet-sdk.sh.*.tmp' -print -quit)" ]
  [[ "$output" != *"Tool installed."* ]]
}

@test "cleanup failure after promotion fails the operation without false install success" {
  fake_bin="$test_root/cleanup-bin"
  mkdir -p "$fake_bin"
  write_successful_install_seams "$fake_bin"

  cat > "$fake_bin/rm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
for arg in "$@"; do
  if [[ "$arg" == *'/dotnet-install.sh.'* ]]; then
    printf '%s\n' 'cleanup-remove-failed' >&2
    exit 91
  fi
done
exec /bin/rm "$@"
EOF
  chmod +x "$fake_bin/rm"

  run env HOME="$test_home" PATH="$fake_bin:$PATH" "$tool_path" install "$version" --yes

  [ "$status" -ne 0 ]
  [[ "$output" == *"Unable to clean install helper:"* ]]
  [[ "$output" == *"Isolated SDK $version was installed, but transaction cleanup failed."* ]]
  [[ "$output" != *"installation completed successfully"* ]]
  [ -x "$install_dir/dotnet" ]
  compgen -G "$tool_root/dotnet-install.sh.*" >/dev/null
}
