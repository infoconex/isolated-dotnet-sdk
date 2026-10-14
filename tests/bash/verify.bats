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
  mkdir -p "$install_dir/sdk" "$install_dir/shared/Microsoft.NETCore.App"
  cat > "$install_dir/dotnet" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == '--list-sdks' ]]; then
  if [[ -n "\${VERIFY_TEST_EXIT_CODE:-}" ]]; then
    exit "\$VERIFY_TEST_EXIT_CODE"
  fi
  printf '%s [%s]\\n' "\${VERIFY_TEST_REPORTED_VERSION:-$reported_version}" "\${VERIFY_TEST_ORIGIN:-$install_dir/sdk}"
fi
if [[ "\${1:-}" == '--info' ]]; then
  if [[ "\${VERIFY_TEST_LEGACY_INFO:-}" == 'true' ]]; then
    printf '%s\n' 'Runtime Environment:' ' RID:         linux-x64' '' 'Host (useful for support):' '  Version:      99.0.9'
  else
    printf '%s\n' 'Runtime Environment:' ' RID:         linux-x64' '' 'Host:' '  Version:      99.0.9' '  Architecture: x64'
  fi
fi
if [[ "\${1:-}" == '--list-runtimes' ]]; then
  printf 'Microsoft.NETCore.App 99.0.9 [%s]\n' "$install_dir/shared/Microsoft.NETCore.App"
  if [[ -n "\${VERIFY_TEST_EXTRA_RUNTIME_ROOT:-}" ]]; then
    printf 'Microsoft.AspNetCore.App 99.0.9 [%s]\n' "\$VERIFY_TEST_EXTRA_RUNTIME_ROOT"
  fi
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
  [[ "$output" == *"SDK information:"* ]]
  [[ "$output" == *"SDK version"*"$version"* ]]
  [[ "$output" == *"Installed components:"* ]]
  [[ "$output" == *"Host version"*'99.0.9'* ]]
  [[ "$output" == *"Architecture"*'x64'* ]]
  [[ "$output" == *"Runtime identifier"*'linux-x64'* ]]
  [[ "$output" == *"Microsoft.NETCore.App"*'99.0.9'* ]]
  [[ "$output" != *"Location:"* ]]
  [[ "$output" == *"Exact SDK found in isolated installation"* ]]
  [[ "$output" == *"Correct SDK selected"* ]]
  [[ "$output" == *"SDK inventory"* ]]
  [[ "$output" == *"SDK resolution"* ]]
  [[ "$output" == *"Release/lifecycle   Unavailable"* ]]
  [ "$(cat "$install_dir/verify-sentinel.txt")" = 'preserve-me' ]
  [ "$(find "$install_dir" -type f | wc -l | tr -d ' ')" = "$file_count_before" ]
}

@test "Verify recognizes legacy Host heading and derives architecture from RID" {
  version='2.2.207'
  install_fake_host "$version"
  run env HOME="$test_home" VERIFY_TEST_LEGACY_INFO=true "$tool_path" verify "$version"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Host version"*'99.0.9'* ]]
  [[ "$output" == *"Architecture"*'x64'* ]]
  [[ "$output" == *"Runtime identifier"*'linux-x64'* ]]
  [[ "$output" == *"Isolated SDK $version verified successfully."* ]]
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
  [[ "$output" == *"Support type"*'LTS'* ]]
  [[ "$output" == *"Status"*'Maintenance'* ]]
  [[ "$output" == *"SDK release date"*'2026-01-01'* ]]
  [[ "$output" == *"Channel EOS date"*'2030-01-01'* ]]
  [[ "$output" == *"Update available"*'99.0.200'* ]]
}

@test "Verify omits unrelated system runtimes" {
  version='99.0.100'
  install_fake_host "$version"
  mkdir -p "$test_root/system/shared/Microsoft.AspNetCore.App"
  run env HOME="$test_home" VERIFY_TEST_EXTRA_RUNTIME_ROOT="$test_root/system/shared/Microsoft.AspNetCore.App" "$tool_path" verify "$version"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Microsoft.NETCore.App"*'99.0.9'* ]]
  [[ "$output" != *"Microsoft.AspNetCore.App"* ]]
}


# This host models the original 1.x CLI: --version and --info only.
install_legacy_verify_host() {
  local version="$1"
  local install_dir="$tool_root/$version"
  mkdir -p "$install_dir/sdk/$version" "$install_dir/shared/Microsoft.NETCore.App"
  cat > "$install_dir/dotnet" <<'HOST'
#!/usr/bin/env bash
version="$(basename "$(dirname "$0")")"
install_dir="$(cd "$(dirname "$0")" && pwd -P)"
if [[ -n "${VERIFY_LEGACY_CALL_LOG:-}" ]]; then
  printf '%s\n' "${1:-}" >> "$VERIFY_LEGACY_CALL_LOG"
fi
case "${1:-}" in
  --list-sdks|--list-runtimes)
    printf 'Unknown option: %s\n' "$1" >&2
    exit 72 ;;
  --version|--info)
    if [[ "${VERIFY_LEGACY_REQUIRE_PIN:-}" == true ]]; then
      [[ "${DOTNET_MULTILEVEL_LOOKUP:-}" == 0 && -d "${DOTNET_ROOT:-}" ]] || exit 76
      [[ "$(cd "$DOTNET_ROOT" && pwd -P)" == "$install_dir" ]] || exit 76
      [[ -f ./global.json ]] && grep -Fq "\"version\":\"$version\"" ./global.json || exit 76
    fi
    if [[ "$1" == '--version' ]]; then
      [[ -z "${VERIFY_LEGACY_VERSION_EXIT:-}" ]] || exit "$VERIFY_LEGACY_VERSION_EXIT"
      printf '%s\n' "${VERIFY_LEGACY_VERSION_OUTPUT-$version}"
      if [[ "${VERIFY_LEGACY_EXTRA_VERSION+x}" ]]; then printf '%s\n' "$VERIFY_LEGACY_EXTRA_VERSION"; fi
    else
      [[ -z "${VERIFY_LEGACY_INFO_EXIT:-}" ]] || exit "$VERIFY_LEGACY_INFO_EXIT"
      printf '.NET Command Line Tools (%s)\nProduct Information:\n Version: %s\nRuntime Environment:\n' "$version" "$version"
      if [[ "${VERIFY_LEGACY_NO_BASE:-}" != true ]]; then
        printf ' Base Path: %s\n' "${VERIFY_LEGACY_BASE_PATH-$install_dir/sdk/$version}"
      fi
      if [[ "${VERIFY_LEGACY_EXTRA_BASE+x}" ]]; then printf ' Base Path: %s\n' "$VERIFY_LEGACY_EXTRA_BASE"; fi
      if [[ -n "${VERIFY_LEGACY_RID:-}" ]]; then printf ' RID: %s\n' "$VERIFY_LEGACY_RID"; fi
    fi ;;
  *) exit 73 ;;
esac
HOST
  chmod +x "$install_dir/dotnet"
}

@test "legacy 1.x Verify succeeds without unsupported inventory diagnostics" {
  export VERIFY_LEGACY_CALL_LOG="$test_root/legacy-calls"
  for version in 1.0.4 1.1.5 1.1.14; do
    install_legacy_verify_host "$version"
    : > "$VERIFY_LEGACY_CALL_LOG"
    run env HOME="$test_home" DOTNET_MULTILEVEL_LOOKUP=1 VERIFY_LEGACY_REQUIRE_PIN=true "$tool_path" verify "$version"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Isolated SDK $version verified successfully."* ]]
    [[ "$output" == *"SDK resolution"*"OK"*"Correct SDK selected"* ]]
    [[ "$output" == *"SDK origin"*"OK"*"Exact SDK Base Path in isolated installation"* ]]
    [[ "$output" != *"SDK inventory"* ]]
    [[ "$output" == *"Host version"*"Unavailable"* ]]
    [[ "$output" == *"Runtime identifier"*"Unavailable"* ]]
    [[ "$output" == *"Release/lifecycle   Unavailable"* ]]
    grep -Fxq -- '--version' "$VERIFY_LEGACY_CALL_LOG"
    grep -Fxq -- '--info' "$VERIFY_LEGACY_CALL_LOG"
    ! grep -Eq '^--list-(sdks|runtimes)$' "$VERIFY_LEGACY_CALL_LOG"
  done
}

@test "legacy Verify rejects wrong empty and ambiguous --version results" {
  local version=1.0.4
  install_legacy_verify_host "$version"
  run env HOME="$test_home" VERIFY_LEGACY_VERSION_OUTPUT=1.1.14 "$tool_path" verify "$version"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SDK resolution"*"FAIL"* ]]
  run env HOME="$test_home" VERIFY_LEGACY_VERSION_OUTPUT='' "$tool_path" verify "$version"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SDK resolution"*"FAIL"* ]]
  run env HOME="$test_home" VERIFY_LEGACY_EXTRA_VERSION="$version" "$tool_path" verify "$version"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SDK resolution"*"FAIL"* ]]
}

@test "legacy Verify rejects nonzero host command exits" {
  local version=1.1.5
  install_legacy_verify_host "$version"
  run env HOME="$test_home" VERIFY_LEGACY_VERSION_EXIT=74 "$tool_path" verify "$version"
  [ "$status" -ne 0 ]
  [[ "$output" == *".NET host"*"FAIL"* ]]
  run env HOME="$test_home" VERIFY_LEGACY_INFO_EXIT=75 "$tool_path" verify "$version"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SDK origin"*"FAIL"* ]]
  [[ "$output" == *"--info exited with code 75"* ]]
}

@test "legacy Verify rejects missing empty ambiguous and system-only Base Path" {
  local version=1.1.14
  install_legacy_verify_host "$version"
  run env HOME="$test_home" VERIFY_LEGACY_NO_BASE=true "$tool_path" verify "$version"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SDK origin"*"FAIL"* ]]
  run env HOME="$test_home" VERIFY_LEGACY_BASE_PATH='' "$tool_path" verify "$version"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SDK origin"*"FAIL"* ]]
  run env HOME="$test_home" VERIFY_LEGACY_EXTRA_BASE="$tool_root/$version/sdk/$version" "$tool_path" verify "$version"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SDK origin"*"FAIL"* ]]
  mkdir -p "$test_root/system/sdk/$version"
  run env HOME="$test_home" VERIFY_LEGACY_BASE_PATH="$test_root/system/sdk/$version" "$tool_path" verify "$version"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SDK origin"*"FAIL"* ]]
  [[ "$output" == *"does not match the isolated directory"* ]]
}

@test "legacy Verify rejects missing installed SDK Base Path" {
  local version=1.0.4
  install_legacy_verify_host "$version"
  rm -rf -- "$tool_root/$version/sdk/$version"
  run env HOME="$test_home" "$tool_path" verify "$version"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SDK origin"*"FAIL"* ]]
}

@test "legacy Verify reports RID and architecture without inventing runtimes" {
  local version=1.1.5
  install_legacy_verify_host "$version"
  run env HOME="$test_home" VERIFY_LEGACY_RID=linux-x64 "$tool_path" verify "$version"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Architecture"*"x64"* ]]
  [[ "$output" == *"Runtime identifier"*"linux-x64"* ]]
  [[ "$output" == *"Host version"*"Unavailable"* ]]
  [[ "$output" == *".NET runtimes:"*"Unavailable"* ]]
}


@test "legacy Verify cleans pinned work state on failed proof without changing installed files" {
  local version=1.0.4
  install_legacy_verify_host "$version"
  local private_temp="$test_root/private-temp"
  mkdir -p "$private_temp"
  printf '%s' keep > "$tool_root/$version/sentinel"
  run env HOME="$test_home" TMPDIR="$private_temp" VERIFY_LEGACY_INFO_EXIT=79 "$tool_path" verify "$version"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SDK origin"*"FAIL"* ]]
  [ "$(cat "$tool_root/$version/sentinel")" = keep ]
  [ -z "$(find "$private_temp" -mindepth 1 -maxdepth 1 -print -quit)" ]
  [ ! -e "$tool_root/$version/global.json" ]
}

@test "legacy Verify cannot validate an SDK symlink redirected outside isolated root" {
  local version=1.1.14
  install_legacy_verify_host "$version"
  mkdir -p "$test_root/system/sdk/$version"
  rm -rf -- "$tool_root/$version/sdk/$version"
  ln -s "$test_root/system/sdk/$version" "$tool_root/$version/sdk/$version"
  run env HOME="$test_home" VERIFY_LEGACY_BASE_PATH="$test_root/system/sdk/$version" "$tool_path" verify "$version"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SDK origin"*"FAIL"* ]]
}
