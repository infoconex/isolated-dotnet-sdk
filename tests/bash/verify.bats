#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-verify-tests.XXXXXX")"
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

install_fake_host() {
  local version="$1"
  local reported_version="${2:-$1}"
  local install_dir="$tool_root/$version"
  mkdir -p "$install_dir"
  cat > "$install_dir/dotnet" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == '--list-sdks' ]]; then
  if [[ -n "\${VERIFY_TEST_EXIT_CODE:-}" ]]; then
    exit "\$VERIFY_TEST_EXIT_CODE"
  fi
  printf '%s [/fake/sdk]\n' "\${VERIFY_TEST_REPORTED_VERSION:-$reported_version}"
fi
exit 0
EOF
  chmod +x "$install_dir/dotnet"
}

@test "verify reports a healthy exact isolated SDK without mutating it" {
  version='99.0.100'
  install_dir="$tool_root/$version"
  install_fake_host "$version"
  printf '%s' 'preserve-me' > "$install_dir/verify-sentinel.txt"
  file_count_before="$(find "$install_dir" -type f | wc -l | tr -d ' ')"

  run env HOME="$test_home" "$tool_path" verify "$version"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Isolated SDK $version is healthy."* ]]
  [[ "$output" == *"Location: $install_dir"* ]]
  [ "$(cat "$install_dir/verify-sentinel.txt")" = 'preserve-me' ]
  [ "$(find "$install_dir" -type f | wc -l | tr -d ' ')" = "$file_count_before" ]
}

@test "verify fails clearly when the selected version is not installed" {
  version='99.0.100'

  run env HOME="$test_home" "$tool_path" verify "$version"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Isolated SDK $version is not installed under $tool_root."* ]]
}

@test "verify fails clearly when the installation directory has no host" {
  version='99.0.100'
  install_dir="$tool_root/$version"
  mkdir -p "$install_dir"

  run env HOME="$test_home" "$tool_path" verify "$version"

  [ "$status" -ne 0 ]
  [[ "$output" == *"expected dotnet host was not found"* ]]
  [ -d "$install_dir" ]
}

@test "verify fails clearly when the isolated host is not executable" {
  version='99.0.100'
  install_dir="$tool_root/$version"
  mkdir -p "$install_dir"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$install_dir/dotnet"
  chmod -x "$install_dir/dotnet"

  run env HOME="$test_home" "$tool_path" verify "$version"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Isolated SDK $version host is not executable: $install_dir/dotnet"* ]]
  [ -f "$install_dir/dotnet" ]
}

@test "verify fails with the native exit code when host execution fails" {
  version='99.0.100'
  install_fake_host "$version"

  run env HOME="$test_home" VERIFY_TEST_EXIT_CODE=73 "$tool_path" verify "$version"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Unable to verify isolated SDK $version with exit code 73."* ]]
}

@test "verify fails when the isolated host does not report the requested SDK version" {
  version='99.0.100'
  install_fake_host "$version" '98.0.100'

  run env HOME="$test_home" "$tool_path" verify "$version"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Isolated SDK $version failed verification: the host did not report SDK $version."* ]]
}

@test "verify requires an exact version" {
  run env HOME="$test_home" "$tool_path" verify

  [ "$status" -ne 0 ]
  [[ "$output" == *"An exact SDK version is required with verify."* ]]
}

@test "verify rejects invalid exact-version syntax" {
  run env HOME="$test_home" "$tool_path" verify 'invalid/version'

  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid SDK version: invalid/version"* ]]
}
