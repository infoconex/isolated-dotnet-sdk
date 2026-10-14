#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-interactive-verify.XXXXXX")"
  test_home="$test_root/home"
  tool_root="$test_home/dotnet-sdks"
  tool_path="$tool_root/isolated-dotnet-sdk.sh"
  source_copy="$test_root/isolated-dotnet-sdk-source.sh"

  fake_bin="$test_root/fake-bin"
  mkdir -p "$test_home" "$fake_bin"
  printf '#!/usr/bin/env bash\\nexit 76\\n' > "$fake_bin/curl"
  chmod +x "$fake_bin/curl"
  export PATH="$fake_bin:$PATH"
  cp "$repo_root/isolated-dotnet-sdk.sh" "$source_copy"
  chmod +x "$source_copy"
  run env HOME="$test_home" "$source_copy" list
  [ "$status" -eq 0 ]
}

teardown() {
  rm -rf "$test_root"
}

count_main_prompts() {
  printf '%s\n' "$1" | grep -c 'What would you like to do?' || true
}

count_acknowledgement_prompts() {
  printf '%s\n' "$1" | grep -Ec 'Press Enter to return to .+\.\.\.' || true
}

install_fake_host() {
  local version="$1"
  local reported_version="${2:-$1}"
  local install_dir="$tool_root/$version"
  mkdir -p "$install_dir/sdk"
  cat > "$install_dir/dotnet" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == '--list-sdks' ]]; then
  printf '%s [%s]\\n' '$reported_version' '$install_dir/sdk'
fi
if [[ "\${1:-}" == '--version' ]]; then
  printf '%s\\n' '$reported_version'
fi
exit 0
EOF
  chmod +x "$install_dir/dotnet"
}

@test "successful interactive Verify returns to the Verify SDK list" {
  version='99.0.100'
  install_fake_host "$version"

  run bash -c 'printf "v\n1\nb\ne\n" | env HOME="$1" "$2"' _ "$test_home" "$tool_path"

  [ "$status" -eq 0 ]
  [ "$(count_main_prompts "$output")" -eq 2 ]
  [ "$(count_acknowledgement_prompts "$output")" -eq 0 ]
  [[ "$output" == *"V. Verify an isolated SDK"* ]]
  [ "$(printf '%s\n' "$output" | grep -c 'Select an isolated SDK to verify:' || true)" -eq 2 ]
  [[ "$output" == *"Isolated SDK $version verified successfully."* ]]
  [[ "$output" == *"Exiting."* ]]
}

@test "interactive Verify with no isolated SDK is a normal no-change result" {
  run bash -c 'printf "v\ne\n" | env HOME="$1" "$2"' _ "$test_home" "$tool_path"

  [ "$status" -eq 0 ]
  [ "$(count_main_prompts "$output")" -eq 2 ]
  [ "$(count_acknowledgement_prompts "$output")" -eq 0 ]
  [[ "$output" == *"No isolated SDKs are installed under $tool_root."* ]]
  [[ "$output" != *"Select an isolated SDK to verify:"* ]]
}

@test "Verify Back returns to Main and Verify Exit leaves the session" {
  version='99.0.100'
  install_fake_host "$version"

  run bash -c 'printf "v\nb\nv\ne\n" | env HOME="$1" "$2"' _ "$test_home" "$tool_path"

  [ "$status" -eq 0 ]
  [ "$(count_main_prompts "$output")" -eq 2 ]
  [ "$(count_acknowledgement_prompts "$output")" -eq 0 ]
  [[ "$output" == *"B. Back to Main"* ]]
  [[ "$output" == *"E. Exit"* ]]
  [[ "$output" == *"Exiting."* ]]
  [[ "$output" != *"Isolated SDK $version verified successfully."* ]]
}

@test "Verify choices are sorted newest to oldest" {
  install_fake_host '8.0.425'
  install_fake_host '11.0.100-rc.1.26425.128'
  install_fake_host '10.0.401'

  run bash -c 'printf "v\nb\ne\n" | env HOME="$1" "$2"' _ "$test_home" "$tool_path"

  [ "$status" -eq 0 ]
  verify_section="$(printf '%s\n' "$output" | sed -n '/Select an isolated SDK to verify:/,/B. Back to Main/p')"
  [[ "$verify_section" == *"1. 11.0.100-rc.1.26425.128"* ]]
  [[ "$verify_section" == *"2. 10.0.401"* ]]
  [[ "$verify_section" == *"3. 8.0.425"* ]]
}

@test "Verify selection never offers System SDKs" {
  isolated_version='99.0.100'
  system_version='88.0.100'
  install_fake_host "$isolated_version"
  fake_bin="$test_root/fake-bin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/dotnet" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == '--list-sdks' ]]; then
  printf '%s\n' '$system_version [/system/sdk]'
fi
exit 0
EOF
  chmod +x "$fake_bin/dotnet"

  run bash -c 'printf "v\nb\ne\n" | env HOME="$1" PATH="$2:$PATH" "$3"' _ \
    "$test_home" "$fake_bin" "$tool_path"

  [ "$status" -eq 0 ]
  [[ "$output" == *"1. $isolated_version"* ]]
  [[ "$output" != *"$system_version"* ]]
}

@test "interactive Verify failure terminates nonzero without consuming later Exit" {
  version='99.0.100'
  install_fake_host "$version" '98.0.100'

  run bash -c 'printf "v\n1\ne\n" | env HOME="$1" "$2" 2>&1' _ "$test_home" "$tool_path"

  [ "$status" -ne 0 ]
  [ "$(count_main_prompts "$output")" -eq 1 ]
  [ "$(count_acknowledgement_prompts "$output")" -eq 0 ]
  [[ "$output" == *"Isolated SDK $version failed verification: the host did not report SDK $version."* ]]
  [[ "$output" != *"Exiting."* ]]
}

@test "Verify retry feedback reports the active choices" {
  version='99.0.100'
  install_fake_host "$version"

  run bash -c 'printf "v\n\n6\nb\ne\n" | env HOME="$1" "$2" 2>&1' _ "$test_home" "$tool_path"

  [ "$status" -eq 0 ]
  [[ "$output" == *"A selection is required. Choose 1, B, or E."* ]]
  [[ "$output" == *"Invalid selection: 6. Choose 1, B, or E."* ]]
  [[ "$output" == *$'Invalid selection: 6. Choose 1, B, or E.\n\nSelect an isolated SDK to verify:'* ]]
}


@test "interactive Verify uses the same legacy SDK origin proof" {
  version='1.1.14'
  install_fake_host "$version"
  mkdir -p "$tool_root/$version/sdk/$version"
  cat > "$tool_root/$version/dotnet" <<EOF
#!/usr/bin/env bash
case "${1:-}" in
  --version) printf '%s\n' '$version' ;;
  --info) printf 'Runtime Environment:\n Base Path: %s\n' '$tool_root/$version/sdk/$version' ;;
  --list-sdks|--list-runtimes) printf 'Unknown option: %s\n' "$1" >&2; exit 77 ;;
esac
EOF
  chmod +x "$tool_root/$version/dotnet"
  run bash -c 'printf "v\n1\nb\ne\n" | env HOME="$1" "$2"' _ "$test_home" "$tool_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SDK origin"*"OK"*"Exact SDK Base Path in isolated installation"* ]]
  [[ "$output" == *"Isolated SDK $version verified successfully."* ]]
  [[ "$output" != *"Unknown option: --list-sdks"* ]]
}
