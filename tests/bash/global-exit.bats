#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-global-exit.XXXXXX")"
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
  chmod +x "$source_copy"
}

bootstrap_tool() {
  prepare_source
  run env HOME="$test_home" "$source_copy" list
  [ "$status" -eq 0 ]
}

count_main_prompts() {
  printf '%s\n' "$1" | grep -c 'What would you like to do?' || true
}

write_global_exit_fake_curl() {
  local fake_bin="$1"
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
      "channel-version": "10.0",
      "latest-sdk": "10.0.401",
      "support-phase": "active",
      "release-type": "lts",
      "releases.json": "https://example.invalid/10.0/releases.json"
    },
    {
      "channel-version": "7.0",
      "latest-sdk": "7.0.410",
      "support-phase": "eol",
      "release-type": "sts",
      "releases.json": "https://example.invalid/7.0/releases.json"
    }
  ]
}
JSON
    ;;
  https://example.invalid/10.0/releases.json|https://example.invalid/7.0/releases.json)
    cat > "$out_file" <<'JSON'
{
  "releases": [
    {"sdk":{"version":"10.0.401","files":[{"url":"https://example.invalid/dotnet/Sdk/10.0.401/a"}]}},
    {"sdk":{"version":"10.0.400","files":[{"url":"https://example.invalid/dotnet/Sdk/10.0.400/a"}]}},
    {"sdk":{"version":"10.0.303","files":[{"url":"https://example.invalid/dotnet/Sdk/10.0.303/a"}]}}
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
}

@test "Main advertises E Exit and rejects numeric 4 as an Exit alias" {
  bootstrap_tool

  run bash -c 'printf "4\ne\n" | env HOME="$1" "$2"' _ "$test_home" "$tool_path"

  [ "$status" -eq 0 ]
  [ "$(count_main_prompts "$output")" -eq 2 ]
  [[ "$output" == *"E. Exit"* ]]
  [[ "$output" != *"4. Exit"* ]]
  [[ "$output" == *"Please choose 1, 2, 3, or E."* ]]
  [[ "$output" == *"Exiting."* ]]
}

@test "E exits persistent session directly from supported channel selection" {
  bootstrap_tool
  fake_bin="$test_root/supported-fake-bin"
  write_global_exit_fake_curl "$fake_bin"

  run bash -c 'printf "1\ne\n" | env HOME="$1" PATH="$2:$PATH" "$3"' _ \
    "$test_home" "$fake_bin" "$tool_path"

  [ "$status" -eq 0 ]
  [ "$(count_main_prompts "$output")" -eq 1 ]
  [[ "$output" == *"E. Exit"* ]]
  [[ "$output" != *"Installation cancelled."* ]]
  [[ "$output" == *"Exiting."* ]]
}

@test "E exits persistent session directly from end-of-life channel view" {
  bootstrap_tool
  fake_bin="$test_root/eol-fake-bin"
  write_global_exit_fake_curl "$fake_bin"

  run bash -c 'printf "1\ns\ne\n" | env HOME="$1" PATH="$2:$PATH" "$3"' _ \
    "$test_home" "$fake_bin" "$tool_path"

  [ "$status" -eq 0 ]
  [ "$(count_main_prompts "$output")" -eq 1 ]
  [[ "$output" == *"Select an end-of-life .NET channel:"* ]]
  [[ "$output" == *"E. Exit"* ]]
  [[ "$output" != *"Installation cancelled."* ]]
  [[ "$output" == *"Exiting."* ]]
}

@test "S toggles the channel view in both directions" {
  bootstrap_tool
  fake_bin="$test_root/toggle-fake-bin"
  write_global_exit_fake_curl "$fake_bin"

  run bash -c 'printf "1\ns\ns\ne\n" | env HOME="$1" PATH="$2:$PATH" "$3"' _ \
    "$test_home" "$fake_bin" "$tool_path"

  [ "$status" -eq 0 ]
  [ "$(count_main_prompts "$output")" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c 'Select a supported or development \.NET channel:' || true)" -eq 2 ]
  [ "$(printf '%s\n' "$output" | grep -c 'Select an end-of-life \.NET channel:' || true)" -eq 1 ]
  [[ "$output" == *"S. Show end-of-life channels"* ]]
  [[ "$output" == *"S. Show supported/development channels"* ]]
}

@test "A is rejected instead of toggling the channel view" {
  bootstrap_tool
  fake_bin="$test_root/reject-a-fake-bin"
  write_global_exit_fake_curl "$fake_bin"

  run bash -c 'printf "1\na\ne\n" | env HOME="$1" PATH="$2:$PATH" "$3"' _ \
    "$test_home" "$fake_bin" "$tool_path"

  [ "$status" -eq 0 ]
  [ "$(count_main_prompts "$output")" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c 'Select a supported or development \.NET channel:' || true)" -eq 2 ]
  [[ "$output" == *"Invalid selection."* ]]
  [[ "$output" != *"Select an end-of-life .NET channel:"* ]]
}

@test "E exits persistent session directly from SDK version selection" {
  bootstrap_tool
  fake_bin="$test_root/version-fake-bin"
  write_global_exit_fake_curl "$fake_bin"

  run bash -c 'printf "1\n1\ne\n" | env HOME="$1" PATH="$2:$PATH" "$3"' _ \
    "$test_home" "$fake_bin" "$tool_path"

  [ "$status" -eq 0 ]
  [ "$(count_main_prompts "$output")" -eq 1 ]
  [[ "$output" == *"Available .NET 10.0 SDKs:"* ]]
  [[ "$output" == *"E. Exit"* ]]
  [[ "$output" != *"Installation cancelled."* ]]
  [[ "$output" == *"Exiting."* ]]
}

@test "E exits persistent session directly from expanded SDK version selection" {
  bootstrap_tool
  fake_bin="$test_root/expanded-version-fake-bin"
  write_global_exit_fake_curl "$fake_bin"

  run bash -c 'printf "1\n1\ns\ne\n" | env HOME="$1" PATH="$2:$PATH" "$3"' _ \
    "$test_home" "$fake_bin" "$tool_path"

  [ "$status" -eq 0 ]
  [ "$(count_main_prompts "$output")" -eq 1 ]
  [[ "$output" == *"S. Show all versions"* ]]
  [[ "$output" == *"10.0.400"* ]]
  [[ "$output" == *"E. Exit"* ]]
  [[ "$output" == *"Exiting."* ]]
}

@test "E exits persistent session directly from Remove selection" {
  bootstrap_tool
  version='99.0.100'
  mkdir -p "$tool_root/$version"
  cat > "$tool_root/$version/dotnet" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$tool_root/$version/dotnet"

  run bash -c 'printf "2\ne\n" | env HOME="$1" "$2"' _ "$test_home" "$tool_path"

  [ "$status" -eq 0 ]
  [ "$(count_main_prompts "$output")" -eq 1 ]
  [[ "$output" == *"E. Exit"* ]]
  [[ "$output" != *"Removal cancelled."* ]]
  [[ "$output" == *"Exiting."* ]]
}

@test "explicit one-shot interactive Install keeps Q as Cancel" {
  bootstrap_tool
  fake_bin="$test_root/explicit-fake-bin"
  write_global_exit_fake_curl "$fake_bin"

  run bash -c 'printf "q\n" | env HOME="$1" PATH="$2:$PATH" "$3" install' _ \
    "$test_home" "$fake_bin" "$tool_path"

  [ "$status" -eq 0 ]
  [ "$(count_main_prompts "$output")" -eq 0 ]
  [[ "$output" == *"Q. Cancel"* ]]
  [[ "$output" == *"Installation cancelled."* ]]
  [[ "$output" != *"Exiting."* ]]
}
