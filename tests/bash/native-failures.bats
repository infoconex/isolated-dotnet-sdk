#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-native-tests.XXXXXX")"
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

make_successful_system_dotnet() {
  local fake_bin="$1"
  cat > "$fake_bin/dotnet" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$fake_bin/dotnet"
}

@test "existing isolated host failure stops installation with context" {
  fake_bin="$test_root/existing-probe-fake-bin"
  mkdir -p "$fake_bin" "$install_dir"
  make_successful_system_dotnet "$fake_bin"

  cat > "$install_dir/dotnet" <<'EOF'
#!/usr/bin/env bash
exit 72
EOF
  cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'continued-to-download' >&2
exit 88
EOF
  chmod +x "$install_dir/dotnet" "$fake_bin/curl"

  run env HOME="$test_home" PATH="$fake_bin:$PATH" "$tool_path" install "$version" --yes

  [ "$status" -ne 0 ]
  [[ "$output" == *"Unable to inspect existing isolated SDK $version with exit code 72."* ]]
  [[ "$output" != *"continued-to-download"* ]]
  [[ "$output" != *"installation completed successfully"* ]]
}

@test "installer failure stops before verification and success" {
  fake_bin="$test_root/installer-fake-bin"
  mkdir -p "$fake_bin"
  make_successful_system_dotnet "$fake_bin"

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
cat > "$out_file" <<'SCRIPT'
#!/usr/bin/env bash
exit 73
SCRIPT
EOF
  chmod +x "$fake_bin/curl"

  run env HOME="$test_home" PATH="$fake_bin:$PATH" "$tool_path" install "$version" --yes

  [ "$status" -ne 0 ]
  [[ "$output" == *"dotnet-install failed for SDK $version with exit code 73."* ]]
  [[ "$output" != *"Verifying the isolated SDK"* ]]
  [[ "$output" != *"installation completed successfully"* ]]
}

@test "post-install host failure is reported as verification failure" {
  fake_bin="$test_root/verification-fake-bin"
  mkdir -p "$fake_bin"
  make_successful_system_dotnet "$fake_bin"

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
cat > "$out_file" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
install_dir=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-dir)
      install_dir="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
mkdir -p "$install_dir"
cat > "$install_dir/dotnet" <<'DOTNET'
#!/usr/bin/env bash
exit 74
DOTNET
chmod +x "$install_dir/dotnet"
SCRIPT
EOF
  chmod +x "$fake_bin/curl"

  run env HOME="$test_home" PATH="$fake_bin:$PATH" "$tool_path" install "$version" --yes

  [ "$status" -ne 0 ]
  [[ "$output" == *"Unable to verify isolated SDK $version with exit code 74."* ]]
  [[ "$output" != *"SDK $version was not found after installation."* ]]
  [[ "$output" != *"installation completed successfully"* ]]
}
