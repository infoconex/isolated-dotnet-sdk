#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-metadata-tests.XXXXXX")"
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

@test "release index tolerates missing display-only latest SDK and release type fields" {
  cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

url=""
out_file=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      out_file="$2"
      shift 2
      ;;
    -*)
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done

case "$url" in
  *releases-index.json)
    cat <<'JSON'
{
  "releases-index": [
    {
      "channel-version": "99.0",
      "support-phase": "active",
      "releases.json": "https://example.invalid/releases.json"
    }
  ]
}
JSON
    ;;
  https://example.invalid/releases.json)
    cat > "$out_file" <<'JSON'
{
  "releases": [
    {
      "sdk": {
        "files": [
          { "url": "https://example.invalid/dotnet/Sdk/99.0.100/archive.tgz" }
        ]
      }
    }
  ]
}
JSON
    ;;
  *)
    exit 88
    ;;
esac
EOF
  chmod +x "$fake_bin/curl"

  run bash -c 'printf "1\nq\n" | env HOME="$1" PATH="$2:$PATH" "$3" install' _ \
    "$test_home" "$fake_bin" "$tool_path"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Available .NET 99.0 SDKs:"* ]]
  [[ "$output" == *"99.0.100"* ]]
}
