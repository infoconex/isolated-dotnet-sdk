#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-interactive-verify.XXXXXX")"
  test_home="$test_root/home"
  tool_root="$test_home/dotnet-sdks"
  tool_path="$tool_root/isolated-dotnet-sdk.sh"
  source_copy="$test_root/isolated-dotnet-sdk-source.sh"

  mkdir -p "$test_home"
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

install_fake_host() {
  local version="$1"
  local reported_version="${2:-$1}"
  local install_dir="$tool_root/$version"
  mkdir -p "$install_dir"
  cat > "$install_dir/dotnet" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == '--list-sdks' ]]; then
  printf '%s [/fake/sdk]\n' '$reported_version'
fi
exit 0
EOF
  chmod +x "$install_dir/dotnet"
}

@test "Main exposes Verify and a healthy interactive Verify returns to Main" {
  version='99.0.100'
  install_fake_host "$version"

  run bash -c 'printf "v\n1\ne\n" | env HOME="$1" "$2"' _ "$test_home" "$tool_path"

  [ "$status" -eq 0 ]
  [ "$(count_main_prompts "$output")" -eq 2 ]
  [[ "$output" == *"V. Verify an isolated SDK"* ]]
  [[ "$output" == *"Select an isolated SDK to verify:"* ]]
  [[ "$output" == *"Isolated SDK $version is healthy."* ]]
  [[ "$output" == *"Exiting."* ]]
}

@test "interactive Verify with no isolated SDK is a normal no-change result" {
  run bash -c 'printf "v\ne\n" | env HOME="$1" "$2"' _ "$test_home" "$tool_path"

  [ "$status" -eq 0 ]
  [ "$(count_main_prompts "$output")" -eq 2 ]
  [[ "$output" == *"No isolated SDKs are installed under $tool_root."* ]]
  [[ "$output" != *"Select an isolated SDK to verify:"* ]]
}

@test "Verify Back returns to Main and Verify Exit leaves the session" {
  version='99.0.100'
  install_fake_host "$version"

  run bash -c 'printf "v\nb\nv\ne\n" | env HOME="$1" "$2"' _ "$test_home" "$tool_path"

  [ "$status" -eq 0 ]
  [ "$(count_main_prompts "$output")" -eq 2 ]
  [[ "$output" == *"B. Back to Main"* ]]
  [[ "$output" == *"E. Exit"* ]]
  [[ "$output" == *"Exiting."* ]]
  [[ "$output" != *"Isolated SDK $version is healthy."* ]]
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
