#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-ordering-tests.XXXXXX")"
  test_home="$test_root/home"
  tool_root="$test_home/dotnet-sdks"
  tool_path="$tool_root/isolated-dotnet-sdk.sh"
  fake_bin="$test_root/fake-bin"

  mkdir -p "$tool_root" "$fake_bin"
  cp "$repo_root/isolated-dotnet-sdk.sh" "$tool_path"
  chmod +x "$tool_path"
}

teardown() {
  rm -rf "$test_root"
}

@test "expanded SDK picker preserves the shared newest-first ordering vector" {
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

case "$url" in
  *releases-index.json)
    cat <<'JSON'
{"releases-index":[{"channel-version":"8.0","latest-sdk":"8.0.300","support-phase":"active","release-type":"lts","releases.json":"https://example.invalid/releases.json"}]}
JSON
    ;;
  https://example.invalid/releases.json)
    cat > "$out_file" <<'JSON'
{"releases":[{"files":[
{"url":"https://example.invalid/dotnet/Sdk/8.0.100-preview.7.23376.3/archive"},
{"url":"https://example.invalid/dotnet/Sdk/8.0.300/archive"},
{"url":"https://example.invalid/dotnet/Sdk/8.0.100-rc.1.23455.8/archive"},
{"url":"https://example.invalid/dotnet/Sdk/8.0.101/archive"},
{"url":"https://example.invalid/dotnet/Sdk/8.0.100/archive"},
{"url":"https://example.invalid/dotnet/Sdk/8.0.200/archive"},
{"url":"https://example.invalid/dotnet/Sdk/8.0.100-rc.2.23479.6/archive"},
{"url":"https://example.invalid/dotnet/Sdk/8.0.100-preview.6.23330.14/archive"},
{"url":"https://example.invalid/dotnet/Sdk/8.0.201/archive"},
{"url":"https://example.invalid/dotnet/Sdk/8.0.300-servicing.1.2.3/archive"},
{"url":"https://example.invalid/dotnet/Sdk/8.0.100-preview.7.23376.4/archive"},
{"url":"https://example.invalid/dotnet/Sdk/8.0.100-rc.2.23479.7/archive"}
]}]}
JSON
    ;;
  *) exit 88 ;;
esac
EOF
  chmod +x "$fake_bin/curl"

  run bash -c 'printf "1\ns\nq\n" | env HOME="$1" PATH="$2:$PATH" "$3" install' _ \
    "$test_home" "$fake_bin" "$tool_path"

  [ "$status" -eq 0 ]

  expected=$'8.0.300\n8.0.300-servicing.1.2.3\n8.0.201\n8.0.200\n8.0.101\n8.0.100\n8.0.100-rc.2.23479.7\n8.0.100-rc.2.23479.6\n8.0.100-rc.1.23455.8\n8.0.100-preview.7.23376.4\n8.0.100-preview.7.23376.3\n8.0.100-preview.6.23330.14'
  actual="$(printf '%s\n' "$output" | awk '/^[[:space:]]+[0-9]+\. 8\.0\./ { sub(/^[[:space:]]+[0-9]+\. /, ""); sub(/ \([^)]*\)$/, ""); print }' | tail -n 12)"

  [ "$actual" = "$expected" ]
}
