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

@test "empty release index fails before channel selection" {
  cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"releases-index":[]}'
EOF
  chmod +x "$fake_bin/curl"

  run env HOME="$test_home" PATH="$fake_bin:$PATH" "$tool_path" install

  [ "$status" -ne 0 ]
  [[ "$output" == *"No selectable .NET channels were found in Microsoft release metadata."* ]]
  [[ "$output" != *"Select a supported or development .NET channel:"* ]]
}

@test "selected channel network failure identifies the channel" {
  cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) shift 2 ;;
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
      "latest-sdk": "99.0.100",
      "support-phase": "active",
      "release-type": "sts",
      "releases.json": "https://example.invalid/releases.json"
    }
  ]
}
JSON
    ;;
  https://example.invalid/releases.json)
    exit 7
    ;;
  *) exit 88 ;;
esac
EOF
  chmod +x "$fake_bin/curl"

  run bash -c 'printf "1\n" | env HOME="$1" PATH="$2:$PATH" "$3" install' _ \
    "$test_home" "$fake_bin" "$tool_path"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Unable to load release metadata for .NET 99.0."* ]]
  [[ "$output" != *"successfully"* ]]
}

@test "malformed selected channel metadata fails deterministically and cleans its temporary file" {
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
      "latest-sdk": "99.0.100",
      "support-phase": "active",
      "release-type": "sts",
      "releases.json": "https://example.invalid/releases.json"
    }
  ]
}
JSON
    ;;
  https://example.invalid/releases.json)
    printf '%s\n' 'not-json' > "$out_file"
    ;;
  *) exit 88 ;;
esac
EOF
  chmod +x "$fake_bin/curl"

  run bash -c 'printf "1\n" | env HOME="$1" PATH="$2:$PATH" "$3" install' _ \
    "$test_home" "$fake_bin" "$tool_path"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid release metadata for .NET 99.0."* ]]
  [ -z "$(find "$tool_root" -maxdepth 1 -type f -name '.release-metadata.*' -print -quit)" ]
}

@test "duplicate SDK metadata remains unique when all versions are expanded" {
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
      "latest-sdk": "99.0.100",
      "support-phase": "active",
      "release-type": "sts",
      "releases.json": "https://example.invalid/releases.json"
    }
  ]
}
JSON
    ;;
  https://example.invalid/releases.json)
    cat > "$out_file" <<'JSON'
{"releases":[{"files":[{"url":"https://example.invalid/dotnet/Sdk/99.0.100/a"},{"url":"https://example.invalid/dotnet/Sdk/99.0.100/b"},{"url":"https://example.invalid/dotnet/Sdk/99.0.101/c"}]}]}
JSON
    ;;
  *) exit 88 ;;
esac
EOF
  chmod +x "$fake_bin/curl"

  run bash -c 'printf "1\ns\nq\n" | env HOME="$1" PATH="$2:$PATH" "$3" install' _ \
    "$test_home" "$fake_bin" "$tool_path"

  [ "$status" -eq 0 ]
  [[ "$output" == *"S. Show all versions"* ]]
  [ "$(printf '%s\n' "$output" | grep -Ec '^[[:space:]]+[0-9]+\. 99\.0\.100')" -eq 2 ]
  [ "$(printf '%s\n' "$output" | grep -Ec '^[[:space:]]+[0-9]+\. 99\.0\.101')" -eq 1 ]
}

@test "explicit SDK version bypasses Microsoft release metadata discovery" {
  curl_log="$test_root/curl.log"
  cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
printf '%s\n' "$url" >> "$CURL_LOG"
exit 77
EOF
  chmod +x "$fake_bin/curl"

  run env HOME="$test_home" PATH="$fake_bin:$PATH" CURL_LOG="$curl_log" \
    "$tool_path" install 99.9.999 --yes

  [ "$status" -ne 0 ]
  grep -Fq 'https://builds.dotnet.microsoft.com/dotnet/release-metadata/99.9/releases.json' "$curl_log"
  ! grep -Fq 'releases-index.json' "$curl_log"
  [[ "$output" != *"Loading available .NET SDK releases from Microsoft"* ]]
}
