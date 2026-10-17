#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  test_root="$(mktemp -d /tmp/isolated-dotnet-channel-sort.XXXXXX)"
  tool_root="$test_root/home/dotnet-sdks"
  tool_path="$tool_root/isolated-dotnet-sdk.sh"
  fake_bin="$test_root/bin"
  mkdir -p "$tool_root" "$fake_bin"
  cp "$repo_root/isolated-dotnet-sdk.sh" "$tool_path"
  chmod +x "$tool_path"

  cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url=""
out_file=""
while [[ "$#" -gt 0 ]]; do
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
      "channel-version": "9.0",
      "latest-sdk": "9.0.318",
      "support-phase": "active",
      "release-type": "sts",
      "releases.json": "https://example.invalid/9.0/releases.json"
    },
    {
      "channel-version": "2.1",
      "latest-sdk": "2.1.818",
      "support-phase": "eol",
      "release-type": "lts",
      "releases.json": "https://example.invalid/2.1/releases.json"
    },
    {
      "channel-version": "8.0",
      "latest-sdk": "8.0.425",
      "support-phase": "maintenance",
      "release-type": "lts",
      "releases.json": "https://example.invalid/8.0/releases.json"
    },
    {
      "channel-version": "2.2",
      "latest-sdk": "2.2.207",
      "support-phase": "eol",
      "release-type": "sts",
      "releases.json": "https://example.invalid/2.2/releases.json"
    },
    {
      "channel-version": "oops",
      "latest-sdk": "0.0.100",
      "support-phase": "eol",
      "release-type": "sts",
      "releases.json": "https://example.invalid/oops/releases.json"
    },
    {
      "channel-version": "2.0",
      "latest-sdk": "2.1.202",
      "support-phase": "eol",
      "release-type": "sts",
      "releases.json": "https://example.invalid/2.0/releases.json"
    },
    {
      "channel-version": "10.0",
      "latest-sdk": "10.0.402",
      "support-phase": "active",
      "release-type": "lts",
      "releases.json": "https://example.invalid/10.0/releases.json"
    },
    {
      "channel-version": "11.0",
      "latest-sdk": "11.0.100",
      "support-phase": "active",
      "release-type": "sts"
    }
  ]
}
JSON
    ;;
  https://example.invalid/*/releases.json)
    channel="$(printf '%s' "$url" | sed 's#^https://example.invalid/##;s#/.*##')"
    case "$channel" in
      10.0) version='10.0.402' ;;
      9.0) version='9.0.318' ;;
      8.0) version='8.0.425' ;;
      2.2) version='2.2.207' ;;
      2.1) version='2.1.818' ;;
      2.0) version='2.1.202' ;;
      oops) version='0.0.100' ;;
      *) exit 88 ;;
    esac
    printf '{"releases":[{"sdk":{"version":"%s","files":[{"url":"https://example.invalid/dotnet/Sdk/%s/archive"}]}}]}\n' "$version" "$version" > "$out_file"
    ;;
  *) exit 88 ;;
esac
EOF
  chmod +x "$fake_bin/curl"
}

teardown() {
  rm -rf "$test_root"
}

run_channel_picker() {
  local answers="$1"
  run bash -c 'printf "%b" "$1" | env HOME="$2" PATH="$3:$PATH" "$4" install' _ \
    "$answers" "$test_root/home" "$fake_bin" "$tool_path"
}

channel_menu_versions() {
  local heading="$1"
  local toggle="$2"
  printf '%s\n' "$output" | awk -v heading="$heading" -v toggle="$toggle" '
    index($0, heading) { inside=1; next }
    inside && index($0, toggle) { exit }
    inside && /^[[:space:]]*[0-9]+\. \.NET / { print $3 }
  '
}

@test "shuffled Install channel records sort newest-first in both views" {
  run_channel_picker 's\nq\n'
  [ "$status" -eq 0 ]
  supported="$(channel_menu_versions 'Select a supported or development .NET channel:' 'S. Show end-of-life channels')"
  archived="$(channel_menu_versions 'Select an end-of-life .NET channel:' 'S. Show supported/development channels')"
  [ "$supported" = $'10.0\n9.0\n8.0' ]
  [ "$archived" = $'2.2\n2.1\n2.0\noops' ]
  [[ "$output" != *'.NET 11.0'* ]]
}

@test "ordered EOL selection loads its own release URL and SDK list" {
  run_channel_picker 's\n2\nb\nq\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *'Available .NET 2.1 SDKs:'* ]]
  [[ "$output" == *'1. 2.1.818 (latest)'* ]]
  [[ "$output" != *'Available .NET 2.2 SDKs:'* ]]
}

@test "supported selection, Back and Cancel remain intact after ordering" {
  run_channel_picker '1\nb\nq\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *'Available .NET 10.0 SDKs:'* ]]
  [[ "$output" == *'1. 10.0.402 (latest)'* ]]
  [[ "$output" != *'Available .NET 9.0 SDKs:'* ]]
}
