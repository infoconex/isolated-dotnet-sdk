#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-transaction-regressions.XXXXXX")"
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

make_system_dotnet() {
  local fake_bin="$1"
  cat > "$fake_bin/dotnet" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$fake_bin/dotnet"
}

@test "valid existing exact SDK keeps already-installed behavior and skips download" {
  fake_bin="$test_root/already-installed-bin"
  mkdir -p "$fake_bin" "$install_dir"
  make_system_dotnet "$fake_bin"

  cat > "$install_dir/dotnet" <<EOF
#!/usr/bin/env bash
printf '%s\n' '$version [/fake]'
exit 0
EOF
  chmod +x "$install_dir/dotnet"
  printf '%s\n' 'preserve-existing' > "$install_dir/sentinel.txt"

  cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'download-ran' > "$HOME/download-ran.txt"
exit 88
EOF
  chmod +x "$fake_bin/curl"

  run env HOME="$test_home" PATH="$fake_bin:$PATH" "$tool_path" install "$version" --yes

  [ "$status" -eq 0 ]
  [[ "$output" == *"Isolated SDK $version is already installed."* ]]
  [[ "$output" != *"Downloading Microsoft's dotnet-install.sh script"* ]]
  [ "$(cat "$install_dir/sentinel.txt")" = 'preserve-existing' ]
  [ ! -e "$test_home/download-ran.txt" ]
}

@test "cleanup failure remains observable without masking installer failure" {
  fake_bin="$test_root/cleanup-failure-bin"
  mkdir -p "$fake_bin"
  make_system_dotnet "$fake_bin"

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
while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-dir) install_dir="$2"; shift 2 ;;
    *) shift ;;
  esac
done
mkdir -p "$install_dir"
printf '%s\n' partial > "$install_dir/partial.txt"
exit 73
INSTALLER
EOF

  cat > "$fake_bin/rm" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'cleanup-remove-failed' >&2
exit 91
EOF
  chmod +x "$fake_bin/curl" "$fake_bin/rm"

  run env HOME="$test_home" PATH="$fake_bin:$PATH" "$tool_path" install "$version" --yes

  [ "$status" -ne 0 ]
  [[ "$output" == *"dotnet-install failed for SDK $version with exit code 73."* ]]
  [[ "$output" == *"Unable to clean install helper:"* ]]
  [[ "$output" == *"Unable to clean install staging directory:"* ]]
  [[ "$output" == *"cleanup-remove-failed"* ]]
  [[ "$output" != *"installation completed successfully"* ]]
}
