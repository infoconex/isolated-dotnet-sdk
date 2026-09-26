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

bootstrap_tool() {
  cp "$repo_root/isolated-dotnet-sdk.sh" "$source_copy"
  printf '\n# bootstrap-source-marker\n' >> "$source_copy"
  chmod +x "$source_copy"

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
