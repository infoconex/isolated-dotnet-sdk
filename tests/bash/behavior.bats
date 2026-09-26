#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-tests.XXXXXX")"
  test_home="$test_root/home"
  tool_root="$test_home/dotnet-sdks"
  tool_path="$tool_root/isolated-dotnet-sdk.sh"
  source_copy="$test_root/isolated-dotnet-sdk-source.sh"

  mkdir -p "$test_home"
}

teardown() {
  rm -rf "$test_root"
}

prepare_source() {
  cp "$repo_root/isolated-dotnet-sdk.sh" "$source_copy"
  printf '\n# bootstrap-source-marker\n' >> "$source_copy"
  chmod +x "$source_copy"
}

bootstrap_tool() {
  prepare_source

  run env HOME="$test_home" "$source_copy" list
  [ "$status" -eq 0 ]
}

@test "child Bash process uses the isolated HOME" {
  run env HOME="$test_home" bash -c 'printf "%s" "$HOME"'

  [ "$status" -eq 0 ]
  [ "$output" = "$test_home" ]
}

@test "file-based bootstrap preserves the exact source script" {
  bootstrap_tool

  grep -Fq '# bootstrap-source-marker' "$tool_path"
  [ -z "$(find "$tool_root" -maxdepth 1 -type f -name '.isolated-dotnet-sdk.sh.*.tmp' -print -quit)" ]
}

@test "list command reports the isolated SDK root" {
  bootstrap_tool

  run env HOME="$test_home" "$tool_path" list

  [ "$status" -eq 0 ]
  [[ "$output" == *"Isolated SDKs under"* ]]
}

@test "invalid SDK version is rejected" {
  bootstrap_tool

  run env HOME="$test_home" "$tool_path" install 'invalid/version' --yes

  [ "$status" -ne 0 ]
}

@test "bootstrap path conflict fails without mutating the conflicting destination" {
  prepare_source
  mkdir -p "$tool_path"

  run env HOME="$test_home" "$source_copy" list

  [ "$status" -ne 0 ]
  [[ "$output" != *"Tool installed."* ]]
  [ -d "$tool_path" ]
  [ -z "$(find "$tool_path" -mindepth 1 -maxdepth 1 -print -quit)" ]
}

@test "bootstrap staging failure preserves the saved tool and cleans its candidate" {
  prepare_source
  mkdir -p "$tool_root"
  printf '%s\n' '# existing saved tool' > "$tool_path"

  fake_bin="$test_root/fake-bin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/cp" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'partial candidate' > "$2"
exit 73
EOF
  chmod +x "$fake_bin/cp"

  run env HOME="$test_home" PATH="$fake_bin:$PATH" "$source_copy" list

  [ "$status" -eq 73 ]
  [[ "$output" != *"Tool installed."* ]]
  [ "$(cat "$tool_path")" = '# existing saved tool' ]
  [ -z "$(find "$tool_root" -maxdepth 1 -type f -name '.isolated-dotnet-sdk.sh.*.tmp' -print -quit)" ]
}

@test "metadata processing failure cleans only the operation-owned temporary file" {
  bootstrap_tool

  fake_bin="$test_root/metadata-fake-bin"
  mkdir -p "$fake_bin"
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
    printf '%s\n' '{"releases":[]}' > "$out_file"
    ;;
  *)
    exit 88
    ;;
esac
EOF
  chmod +x "$fake_bin/curl"

  printf '%s\n' 'unowned sentinel' > "$tool_root/.release-metadata.keep"

  run bash -c 'printf "1\n" | env HOME="$1" PATH="$2:$PATH" "$3" install' _ \
    "$test_home" "$fake_bin" "$tool_path"

  [ "$status" -ne 0 ]
  [ -f "$tool_root/.release-metadata.keep" ]
  [ "$(cat "$tool_root/.release-metadata.keep")" = 'unowned sentinel' ]
  [ -z "$(find "$tool_root" -maxdepth 1 -type f -name '.release-metadata.*' ! -name '.release-metadata.keep' -print -quit)" ]
}
