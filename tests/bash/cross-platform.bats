#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-cross-platform.XXXXXX")"
  source_copy="$test_root/isolated-dotnet-sdk-source.sh"
}

teardown() {
  rm -rf "$test_root"
}

@test "file bootstrap and List preserve a HOME path containing whitespace" {
  test_home="$test_root/home with spaces"
  tool_root="$test_home/dotnet-sdks"
  tool_path="$tool_root/isolated-dotnet-sdk.sh"

  mkdir -p "$test_home"
  cp "$repo_root/isolated-dotnet-sdk.sh" "$source_copy"
  printf '\n# cross-platform-source-marker\n' >> "$source_copy"
  chmod +x "$source_copy"

  run env HOME="$test_home" "$source_copy" list

  [ "$status" -eq 0 ]
  [ -f "$tool_path" ]
  grep -Fq '# cross-platform-source-marker' "$tool_path"
  [[ "$output" == *"Isolated SDKs under $tool_root:"* ]]
  [[ "$output" == *"None"* ]]
}
