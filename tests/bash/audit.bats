#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-audit-tests.XXXXXX")"
  test_home="$test_root/home"
  tool_root="$test_home/dotnet-sdks"
  tool_path="$tool_root/isolated-dotnet-sdk.sh"
  fake_bin="$test_root/fake-bin"
  metadata_root="$test_root/metadata"
  network_log="$test_root/network.log"

  mkdir -p "$tool_root" "$fake_bin" "$metadata_root"
  cp "$repo_root/isolated-dotnet-sdk.sh" "$tool_path"
  chmod +x "$tool_path"
  : > "$network_log"

  cat > "$fake_bin/dotnet" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == '--list-sdks' ]]; then
  printf '%b' "${AUDIT_SYSTEM_SDKS:-}"
  exit "${AUDIT_SYSTEM_EXIT_CODE:-0}"
fi
exit 0
EOF
  chmod +x "$fake_bin/dotnet"

  cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url=""
out_file=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out_file="$2"; shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
printf '%s\n' "$url" >> "$AUDIT_NETWORK_LOG"
if [[ "$url" == *releases-index.json ]]; then
  [[ "${AUDIT_FAIL_INDEX:-false}" != true ]] || exit 71
  source_file="$AUDIT_METADATA_ROOT/releases-index.json"
else
  channel="${url##*/}"
  channel="${channel%.json}"
  [[ "${AUDIT_FAIL_CHANNEL:-}" != "$channel" ]] || exit 72
  source_file="$AUDIT_METADATA_ROOT/$channel.json"
fi
[[ -f "$source_file" ]] || exit 73
if [[ -n "$out_file" ]]; then
  cat "$source_file" > "$out_file"
else
  cat "$source_file"
fi
EOF
  chmod +x "$fake_bin/curl"

  write_standard_metadata
}

teardown() {
  rm -rf "$test_root"
}

write_standard_metadata() {
  cat > "$metadata_root/releases-index.json" <<'JSON'
{
  "releases-index": [
    { "channel-version": "11.0", "latest-sdk": "11.0.100-rc.2.999", "support-phase": "preview", "release-type": "sts", "releases.json": "https://example.invalid/11.0.json" },
    { "channel-version": "10.0", "latest-sdk": "10.0.401", "support-phase": "active", "release-type": "lts", "releases.json": "https://example.invalid/10.0.json" },
    { "channel-version": "9.0", "latest-sdk": "9.0.318", "support-phase": "maintenance", "release-type": "sts", "releases.json": "https://example.invalid/9.0.json" },
    { "channel-version": "8.0", "latest-sdk": "8.0.425", "support-phase": "maintenance", "release-type": "lts", "releases.json": "https://example.invalid/8.0.json" },
    { "channel-version": "7.0", "latest-sdk": "7.0.410", "support-phase": "eol", "release-type": "sts", "releases.json": "https://example.invalid/7.0.json" }
  ]
}
JSON

  cat > "$metadata_root/10.0.json" <<'JSON'
{"releases":[
  {"release-date":"2026-09-01","security":false,"sdk":{"version":"10.0.401","files":[{"url":"https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.401/archive.tgz"}]}}
]}
JSON
  cat > "$metadata_root/9.0.json" <<'JSON'
{"releases":[
  {"release-date":"2026-07-01","security":false,"sdk":{"version":"9.0.306","files":[{"url":"https://builds.dotnet.microsoft.com/dotnet/Sdk/9.0.306/archive.tgz"}]}},
  {"release-date":"2026-09-01","security":true,"sdk":{"version":"9.0.318","files":[{"url":"https://builds.dotnet.microsoft.com/dotnet/Sdk/9.0.318/archive.tgz"}]}}
]}
JSON
  cat > "$metadata_root/8.0.json" <<'JSON'
{"releases":[
  {"release-date":"2026-06-01","security":false,"sdk":{"version":"8.0.303","files":[{"url":"https://builds.dotnet.microsoft.com/dotnet/Sdk/8.0.303/archive.tgz"}]}},
  {"release-date":"2026-09-01","security":false,"sdk":{"version":"8.0.425","files":[{"url":"https://builds.dotnet.microsoft.com/dotnet/Sdk/8.0.425/archive.tgz"}]}}
]}
JSON
  cat > "$metadata_root/7.0.json" <<'JSON'
{"releases":[
  {"release-date":"2024-05-01","security":true,"sdk":{"version":"7.0.410","files":[{"url":"https://builds.dotnet.microsoft.com/dotnet/Sdk/7.0.410/archive.tgz"}]}}
]}
JSON
  cat > "$metadata_root/11.0.json" <<'JSON'
{"releases":[
  {"release-date":"2026-09-01","security":false,"sdk":{"version":"11.0.100-rc.1.111","files":[{"url":"https://builds.dotnet.microsoft.com/dotnet/Sdk/11.0.100-rc.1.111/archive.tgz"}]}},
  {"release-date":"2026-10-01","security":true,"sdk":{"version":"11.0.100-rc.2.999","files":[{"url":"https://builds.dotnet.microsoft.com/dotnet/Sdk/11.0.100-rc.2.999/archive.tgz"}]}}
]}
JSON
}

add_isolated_sdk() {
  local version="$1"
  mkdir -p "$tool_root/$version"
  cat > "$tool_root/$version/dotnet" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == '--list-sdks' ]]; then
  printf '%s [/fake/isolated]\n' '$version'
fi
exit 0
EOF
  chmod +x "$tool_root/$version/dotnet"
}

run_audit() {
  run env \
    HOME="$test_home" \
    PATH="$fake_bin:$PATH" \
    AUDIT_METADATA_ROOT="$metadata_root" \
    AUDIT_NETWORK_LOG="$network_log" \
    AUDIT_SYSTEM_SDKS="${AUDIT_SYSTEM_SDKS:-}" \
    AUDIT_FAIL_INDEX="${AUDIT_FAIL_INDEX:-false}" \
    AUDIT_FAIL_CHANNEL="${AUDIT_FAIL_CHANNEL:-}" \
    "$tool_path" audit
}

@test "audit reports servicing and lifecycle states for isolated and system SDKs" {
  add_isolated_sdk '10.0.401'
  add_isolated_sdk '9.0.306'
  add_isolated_sdk '8.0.303'
  add_isolated_sdk '7.0.410'
  add_isolated_sdk '11.0.100-rc.1.111'
  export AUDIT_SYSTEM_SDKS=$'10.0.401 [/system/sdk]\n8.0.425 [/system/sdk]\n'

  run_audit

  [ "$status" -eq 0 ]
  [[ "$output" == *".NET SDK audit"* ]]
  [[ "$output" == *$'Isolated SDKs:\n  10.0.401  Current'* ]]
  [[ "$output" == *"9.0.306  Security update available -> 9.0.318  Maintenance"* ]]
  [[ "$output" == *"8.0.303  Update available -> 8.0.425  Maintenance"* ]]
  [[ "$output" == *"7.0.410  End of life"* ]]
  [[ "$output" == *"11.0.100-rc.1.111  Update available -> 11.0.100-rc.2.999  Preview"* ]]
  [[ "$output" == *$'System SDKs:\n  10.0.401  Current'* ]]
  [[ "$output" == *"8.0.425  Maintenance"* ]]
  [[ "$output" != *"Vulnerable"* ]]
}

@test "audit preserves duplicate versions across ownership groups" {
  add_isolated_sdk '10.0.401'
  export AUDIT_SYSTEM_SDKS=$'10.0.401 [/system/sdk]\n'

  run_audit

  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '  10.0.401  Current')" -eq 2 ]
}

@test "audit does not mark an SDK newer than known metadata as outdated" {
  add_isolated_sdk '10.0.999'

  run_audit

  [ "$status" -eq 0 ]
  [[ "$output" == *"10.0.999  Newer than known metadata"* ]]
  [[ "$output" != *"10.0.999  Update available"* ]]
}

@test "audit reports an unrecognized installed channel without fabricating lifecycle data" {
  add_isolated_sdk '12.0.100'

  run_audit

  [ "$status" -eq 0 ]
  [[ "$output" == *"12.0.100  Unknown channel"* ]]
}

@test "audit fails clearly when the release index cannot be obtained" {
  add_isolated_sdk '10.0.401'
  export AUDIT_FAIL_INDEX=true

  run_audit

  [ "$status" -ne 0 ]
  [[ "$output" == *"Unable to load .NET release metadata from Microsoft."* ]]
  [[ "$output" != *"Current"* ]]
}

@test "audit fails clearly when required channel metadata is malformed" {
  add_isolated_sdk '10.0.401'
  printf '%s\n' 'not-json' > "$metadata_root/10.0.json"

  run_audit

  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid release metadata for .NET 10.0."* ]]
  [[ "$output" != *"10.0.401  Current"* ]]
}

@test "audit rejects an SDK version argument" {
  run env HOME="$test_home" PATH="$fake_bin:$PATH" "$tool_path" audit 10.0.401

  [ "$status" -ne 0 ]
  [[ "$output" == *"An SDK version cannot be combined with audit."* ]]
}

@test "interactive Audit returns to Main after completion" {
  add_isolated_sdk '10.0.401'

  run bash -c 'printf "a\ne\n" | env HOME="$1" PATH="$2:$PATH" AUDIT_METADATA_ROOT="$3" AUDIT_NETWORK_LOG="$4" "$5"' _ \
    "$test_home" "$fake_bin" "$metadata_root" "$network_log" "$tool_path"

  [ "$status" -eq 0 ]
  [[ "$output" == *"A. Audit installed SDKs"* ]]
  [[ "$output" == *"10.0.401  Current"* ]]
  [ "$(printf '%s\n' "$output" | grep -c 'What would you like to do?')" -eq 2 ]
  [[ "$output" == *"Exiting."* ]]
}

@test "List and Verify remain independent of release metadata" {
  add_isolated_sdk '10.0.401'
  cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'network-should-not-be-used' >&2
exit 91
EOF
  chmod +x "$fake_bin/curl"

  run env HOME="$test_home" PATH="$fake_bin:$PATH" "$tool_path" list
  [ "$status" -eq 0 ]
  [[ "$output" != *"network-should-not-be-used"* ]]

  run env HOME="$test_home" PATH="$fake_bin:$PATH" "$tool_path" verify 10.0.401
  [ "$status" -eq 0 ]
  [[ "$output" == *"Isolated SDK 10.0.401 is healthy."* ]]
  [[ "$output" != *"network-should-not-be-used"* ]]
}
