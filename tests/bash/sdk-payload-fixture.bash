# Shared deterministic fixture for Bash SDK-payload transaction tests.

payload_test_setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-payload-test.XXXXXX")"
  test_home="$test_root/home"
  tool_root="$test_home/dotnet-sdks"
  tool_path="$tool_root/isolated-dotnet-sdk.sh"
  fake_bin="$test_root/fake-bin"
  fixture_root="$test_root/fixture"
  version='99.0.100'
  rid='linux-x64'
  install_dir="$tool_root/$version"
  metadata="$test_root/releases.json"
  payload="$test_root/sdk.tar.gz"
  artifact_url="https://builds.dotnet.microsoft.com/dotnet/Sdk/$version/dotnet-sdk-$version-$rid.tar.gz"
  metadata_url="https://builds.dotnet.microsoft.com/dotnet/release-metadata/99.0/releases.json"

  mkdir -p "$tool_root" "$fake_bin" "$fixture_root"
  cp "$repo_root/isolated-dotnet-sdk.sh" "$tool_path"
  chmod +x "$tool_path"

  cat > "$fake_bin/uname" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  -s) printf '%s\n' Linux ;;
  -m) printf '%s\n' x86_64 ;;
  *) printf '%s\n' Linux ;;
esac
EOF

  cat > "$fake_bin/dotnet" <<'EOF'
#!/usr/bin/env bash
exit "${SDK_TEST_SYSTEM_DOTNET_EXIT:-0}"
EOF

  cat > "$fixture_root/dotnet" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == '--list-sdks' ]]; then
  if [[ -n "${SDK_TEST_CREATE_DEST_ON_VERIFY:-}" ]]; then
    mkdir -p "$HOME/dotnet-sdks/99.0.100"
    printf '%s\n' external > "$HOME/dotnet-sdks/99.0.100/external.txt"
  fi
  if [[ -n "${SDK_TEST_DOTNET_EXIT:-}" ]]; then
    exit "$SDK_TEST_DOTNET_EXIT"
  fi
  printf '%s [/fixture/sdk]\n' "${SDK_TEST_DOTNET_VERSION:-99.0.100}"
  exit 0
fi
exit 0
EOF
  chmod +x "$fake_bin/uname" "$fake_bin/dotnet" "$fixture_root/dotnet"

  /usr/bin/tar -czf "$payload" -C "$fixture_root" dotnet
  if command -v sha512sum >/dev/null 2>&1; then
    payload_hash="$(sha512sum "$payload" | awk '{print $1}')"
  else
    payload_hash="$(/usr/bin/shasum -a 512 "$payload" | awk '{print $1}')"
  fi
  write_payload_metadata "$payload_hash"

  cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url=''
out=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
printf '%s\n' "$url" >> "$HOME/curl.log"
case "$url" in
  *release-metadata*)
    if [[ -n "${SDK_TEST_METADATA_CURL_EXIT:-}" ]]; then exit "$SDK_TEST_METADATA_CURL_EXIT"; fi
    cp "$SDK_TEST_METADATA" "$out"
    ;;
  */dotnet/Sdk/*)
    if [[ -n "${SDK_TEST_PAYLOAD_CURL_EXIT:-}" ]]; then exit "$SDK_TEST_PAYLOAD_CURL_EXIT"; fi
    cp "$SDK_TEST_PAYLOAD" "$out"
    ;;
  *) exit 22 ;;
esac
EOF

  cat > "$fake_bin/tar" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${SDK_TEST_TAR_EXIT:-}" ]]; then
  exit "$SDK_TEST_TAR_EXIT"
fi
exec /usr/bin/tar "$@"
EOF

  cat > "$fake_bin/mv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${SDK_TEST_MV_EXIT:-}" && "${1:-}" == *'/.install-'* ]]; then
  exit "$SDK_TEST_MV_EXIT"
fi
exec /bin/mv "$@"
EOF

  cat > "$fake_bin/rm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
for arg in "$@"; do
  if [[ -n "${SDK_TEST_RM_FAIL_PATTERN:-}" && "$arg" == *"$SDK_TEST_RM_FAIL_PATTERN"* ]]; then
    printf '%s\n' cleanup-remove-failed >&2
    exit "${SDK_TEST_RM_EXIT:-91}"
  fi
done
exec /bin/rm "$@"
EOF

  chmod +x "$fake_bin/curl" "$fake_bin/tar" "$fake_bin/mv" "$fake_bin/rm"
  export SDK_TEST_METADATA="$metadata"
  export SDK_TEST_PAYLOAD="$payload"
}

write_payload_metadata() {
  local hash="$1"
  cat > "$metadata" <<EOF
{
  "releases": [
    {
      "sdk": {
        "version": "$version",
        "files": [
          { "rid": "$rid", "url": "$artifact_url", "hash": "$hash" }
        ]
      }
    }
  ]
}
EOF
}

build_payload_without_dotnet() {
  local empty="$test_root/empty"
  mkdir -p "$empty"
  printf '%s\n' placeholder > "$empty/README.txt"
  /usr/bin/tar -czf "$payload" -C "$empty" README.txt
  if command -v sha512sum >/dev/null 2>&1; then
    payload_hash="$(sha512sum "$payload" | awk '{print $1}')"
  else
    payload_hash="$(/usr/bin/shasum -a 512 "$payload" | awk '{print $1}')"
  fi
  write_payload_metadata "$payload_hash"
}

payload_test_teardown() {
  /bin/rm -rf "$test_root"
}

run_payload_install() {
  run env HOME="$test_home" PATH="$fake_bin:$PATH" \
    SDK_TEST_METADATA="$metadata" SDK_TEST_PAYLOAD="$payload" \
    SDK_TEST_METADATA_CURL_EXIT="${SDK_TEST_METADATA_CURL_EXIT:-}" \
    SDK_TEST_PAYLOAD_CURL_EXIT="${SDK_TEST_PAYLOAD_CURL_EXIT:-}" \
    SDK_TEST_TAR_EXIT="${SDK_TEST_TAR_EXIT:-}" \
    SDK_TEST_DOTNET_EXIT="${SDK_TEST_DOTNET_EXIT:-}" \
    SDK_TEST_DOTNET_VERSION="${SDK_TEST_DOTNET_VERSION:-}" \
    SDK_TEST_CREATE_DEST_ON_VERIFY="${SDK_TEST_CREATE_DEST_ON_VERIFY:-}" \
    SDK_TEST_MV_EXIT="${SDK_TEST_MV_EXIT:-}" \
    SDK_TEST_RM_FAIL_PATTERN="${SDK_TEST_RM_FAIL_PATTERN:-}" \
    SDK_TEST_RM_EXIT="${SDK_TEST_RM_EXIT:-}" \
    "$tool_path" install "$version" --yes
}
