#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-metadata-boundaries.XXXXXX")"
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

@test "release index entries missing required selection fields are not selectable" {
  cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
{
  "releases-index": [
    {
      "support-phase": "active",
      "releases.json": "https://example.invalid/missing-channel.json"
    },
    {
      "channel-version": "98.0",
      "releases.json": "https://example.invalid/missing-phase.json"
    },
    {
      "channel-version": "97.0",
      "support-phase": "active"
    }
  ]
}
JSON
EOF
  chmod +x "$fake_bin/curl"

  run env HOME="$test_home" PATH="$fake_bin:$PATH" "$tool_path" install

  [ "$status" -ne 0 ]
  [[ "$output" == *"No selectable .NET channels were found in Microsoft release metadata."* ]]
  [[ "$output" != *"Select a supported or development .NET channel:"* ]]
}

@test "selected channel with no SDK versions fails before the SDK picker" {
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
    printf '%s\n' '{"releases":[]}' > "$out_file"
    ;;
  *) exit 88 ;;
esac
EOF
  chmod +x "$fake_bin/curl"

  run bash -c 'printf "1\n" | env HOME="$1" PATH="$2:$PATH" "$3" install' _ \
    "$test_home" "$fake_bin" "$tool_path"

  [ "$status" -ne 0 ]
  [[ "$output" == *"No SDK versions were found for .NET 99.0."* ]]
  [[ "$output" != *"Available .NET 99.0 SDKs:"* ]]
}

@test "duplicate SDK versions remain unique after deterministic ordering" {
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
{
  "releases-index": [
    {
      "channel-version": "99.0",
      "latest-sdk": "99.0.101",
      "support-phase": "active",
      "releases.json": "https://example.invalid/releases.json"
    }
  ]
}
JSON
    ;;
  https://example.invalid/releases.json)
    cat > "$out_file" <<'JSON'
{"releases":[{"files":[{"url":"https://example.invalid/dotnet/Sdk/99.0.101/a"},{"url":"https://example.invalid/dotnet/Sdk/99.0.100/b"},{"url":"https://example.invalid/dotnet/Sdk/99.0.101/c"}]}]}
JSON
    ;;
  *) exit 88 ;;
esac
EOF
  chmod +x "$fake_bin/curl"

  run bash -c 'printf "1\ns\nq\n" | env HOME="$1" PATH="$2:$PATH" "$3" install' _ \
    "$test_home" "$fake_bin" "$tool_path"

  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -Ec '^[[:space:]]+1\. 99\.0\.101')" -eq 2 ]
  [ "$(printf '%s\n' "$output" | grep -Ec '^[[:space:]]+2\. 99\.0\.100')" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -Ec '^[[:space:]]+[0-9]+\. 99\.0\.101')" -eq 2 ]
}
