#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-cross-platform.XXXXXX")"
  source_copy="$test_root/isolated-dotnet-sdk-source.sh"
}

teardown() {
  rm -rf "$test_root"
}

prepare_source() {
  cp "$repo_root/isolated-dotnet-sdk.sh" "$source_copy"
  printf '\n# cross-platform-source-marker\n' >> "$source_copy"
  chmod +x "$source_copy"
}

@test "file bootstrap and List preserve a HOME path containing whitespace" {
  test_home="$test_root/home with spaces"
  tool_root="$test_home/dotnet-sdks"
  tool_path="$tool_root/isolated-dotnet-sdk.sh"

  mkdir -p "$test_home"
  prepare_source

  run env HOME="$test_home" "$source_copy" list

  [ "$status" -eq 0 ]
  [ -f "$tool_path" ]
  grep -Fq '# cross-platform-source-marker' "$tool_path"
  [[ "$output" == *"Isolated SDKs:"* ]]
  [[ "$output" == *"System SDKs:"* ]]
  [[ "$output" == *"None"* ]]
}

@test "bootstrap saves an executable tool that is directly invokable" {
  test_home="$test_root/direct-home"
  tool_root="$test_home/dotnet-sdks"
  tool_path="$tool_root/isolated-dotnet-sdk.sh"

  mkdir -p "$test_home"
  prepare_source

  run env HOME="$test_home" "$source_copy" list
  [ "$status" -eq 0 ]
  [ -x "$tool_path" ]

  run env HOME="$test_home" "$tool_path" list

  [ "$status" -eq 0 ]
  [[ "$output" == *"Isolated SDKs:"* ]]
}

@test "captured non-TTY output contains no ANSI escape sequences CLI-name prefix or tty diagnostic" {
  test_home="$test_root/non-tty-home"

  mkdir -p "$test_home"
  prepare_source

  run env HOME="$test_home" "$source_copy" list

  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033['* ]]
  [[ "$output" != *"isolated-dotnet-sdk:"* ]]
  [[ "$output" != *"/dev/tty:"* ]]
  [[ "$output" != *"Device not configured"* ]]
}
