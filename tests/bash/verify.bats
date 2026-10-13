#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-verify-tests.XXXXXX")"
  test_home="$test_root/home"
  tool_root="$test_home/dotnet-sdks"
  tool_path="$tool_root/isolated-dotnet-sdk.sh"
  source_copy="$test_root/isolated-dotnet-sdk-source.sh"

  fake_bin="$test_root/fake-bin"
  metadata_dir="$test_root/metadata"
  mkdir -p "$test_home" "$fake_bin" "$metadata_dir"
  cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
url="${@: -1}"
if [[ "$url" == *releases-index.json ]]; then
  [[ -f "$VERIFY_METADATA_DIR/index.json" ]] || exit 71
  cat "$VERIFY_METADATA_DIR/index.json"
else
  [[ -f "$VERIFY_METADATA_DIR/channel.json" ]] || exit 72
  cat "$VERIFY_METADATA_DIR/channel.json"
fi
EOF
  chmod +x "$fake_bin/curl"
  export VERIFY_METADATA_DIR="$metadata_dir"
  export PATH="$fake_bin:$PATH"
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
  mkdir -p "$install_dir/sdk"
  cat > "$install_dir/dotnet" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == '--list-sdks' ]]; then
  if [[ -n "\${VERIFY_TEST_EXIT_CODE:-}" ]]; then
    exit "\$VERIFY_TEST_EXIT_CODE"
  fi
  printf '%s [%s]\\n' "\${VERIFY_TEST_REPORTED_VERSION:-$reported_version}" "\${VERIFY_TEST_ORIGIN:-$install_dir/sdk}"
fi
if [[ "\${1:-}" == '--version' ]]; then
  if [[ -n "\${VERIFY_TEST_VERSION_EXIT_CODE:-}" ]]; then
    exit "\$VERIFY_TEST_VERSION_EXIT_CODE"
  fi
  if [[ "\${VERIFY_TEST_REQUIRE_ISOLATION:-}" == 'true' ]]; then
    [[ "\${DOTNET_MULTILEVEL_LOOKUP:-}" == '0' && "$PWD" != "\$PWD" ]] || exit 74
  fi
  printf '%s\\n' "\${VERIFY_TEST_RESOLVED_VERSION:-$reported_version}"
fi
exit 0
EOF
  chmod +x "$install_dir/dotnet"
}

@test "verify reports an exact isolated SDK verification without mutating it" {
  version='99.0.100'
  install_dir="$tool_root/$version"
  install_fake_host "$version"
  printf '%s' 'preserve-me' > "$install_dir/verify-sentinel.txt"
  file_count_before="$(find "$install_dir" -type f | wc -l | tr -d ' ')"

  run env HOME="$test_home" "$tool_path" verify "$version"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Isolated SDK $version verified successfully."* ]]
  [[ "$output" == *"Location: $install_dir"* ]]
  [[ "$output" == *"SDK inventory"* ]]
  [[ "$output" == *"SDK resolution"* ]]
  [[ "$output" == *"Release/lifecycle information: Unavailable"* ]]
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

@test "verify rejects same-version inventory from a different SDK root" {
  version='99.0.100'
  install_fake_host "$version"
  mkdir -p "$test_root/system/sdk"
  run env HOME="$test_home" VERIFY_TEST_ORIGIN="$test_root/system/sdk" "$tool_path" verify "$version"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SDK inventory"*FAIL* ]]
  [[ "$output" == *"was not reported from $tool_root/$version/sdk"* ]]
}

@test "verify rejects missing isolated SDK origin even when a host reports that path" {
  version='99.0.100'
  install_fake_host "$version"
  rm -rf -- "$tool_root/$version/sdk"
  run env HOME="$test_home" "$tool_path" verify "$version"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SDK inventory"*FAIL* ]]
  [[ "$output" == *"was not reported from"* ]]
}

@test "verify rejects --version mismatch and native --version failure" {
  version='99.0.100'
  install_fake_host "$version"
  run env HOME="$test_home" VERIFY_TEST_RESOLVED_VERSION='98.0.100' "$tool_path" verify "$version"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--version resolved 98.0.100 instead of $version"* ]]
  run env HOME="$test_home" VERIFY_TEST_VERSION_EXIT_CODE=75 "$tool_path" verify "$version"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--version exited with code 75"* ]]
}

@test "verify isolates lookup and current directory from ambient global.json" {
  version='99.0.100'
  install_fake_host "$version"
  printf '%s\\n' '{ "sdk": {"version": "1.0.100"} }' > "$tool_root/global.json"
  run env HOME="$test_home" DOTNET_MULTILEVEL_LOOKUP=1 VERIFY_TEST_REQUIRE_ISOLATION=true "$tool_path" verify "$version"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verified successfully."* ]]
  [ -f "$tool_root/global.json" ]
}

@test "Verify reuses Audit metadata classification when available" {
  version='99.0.100'
  install_fake_host "$version"
  cat > "$metadata_dir/index.json" <<'JSON'
{"releases-index":[
{"channel-version":"99.0","latest-sdk":"99.0.200","support-phase":"maintenance","release-type":"lts","eol-date":"2030-01-01","releases.json":"https://example.invalid/99.0.json"}
]}
JSON
  cat > "$metadata_dir/channel.json" <<'JSON'
{"releases":[
{"release-date":"2026-01-01","sdk":{"version":"99.0.100","files":[{"url":"https://builds.dotnet.microsoft.com/dotnet/Sdk/99.0.100/archive.tgz"}]}},
{"release-date":"2026-04-01","sdk":{"version":"99.0.200","files":[{"url":"https://builds.dotnet.microsoft.com/dotnet/Sdk/99.0.200/archive.tgz"}]}}
]}
JSON
  run env HOME="$test_home" "$tool_path" verify "$version"
  [ "$status" -eq 0 ]
  [[ "$output" == *"99.0.100  LTS  Maintenance"* ]]
  [[ "$output" == *"Release: 2026-01-01"* ]]
  [[ "$output" == *"EOS: 2030-01-01"* ]]
  [[ "$output" == *"Update -> 99.0.200"* ]]
}
