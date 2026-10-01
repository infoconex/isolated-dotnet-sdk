#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-presentation.XXXXXX")"
  test_home="$test_root/home"
  source_copy="$test_root/isolated-dotnet-sdk-source.sh"
  tool_path="$test_home/dotnet-sdks/isolated-dotnet-sdk.sh"

  mkdir -p "$test_home"
  cp "$repo_root/isolated-dotnet-sdk.sh" "$source_copy"
  chmod +x "$source_copy"
}

teardown() {
  rm -rf "$test_root"
}

@test "captured List output is ANSI-free and does not repeat the CLI-name prefix" {
  run env HOME="$test_home" "$source_copy" list

  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033['* ]]
  [[ "$output" != *"isolated-dotnet-sdk:"* ]]
  [[ "$output" == *"Installed .NET SDKs"* ]]
  [[ "$output" == *"Isolated SDKs:"* ]]
  [[ "$output" == *"System SDKs:"* ]]
}

@test "failures remain on the failure path without the CLI-name prefix" {
  run env HOME="$test_home" "$source_copy" list unexpected

  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown argument: unexpected"* ]]
  [[ "$output" != *"isolated-dotnet-sdk:"* ]]
}

@test "semantic headings use an explicit heading role rather than punctuation inference" {
  grep -Fq 'tool_heading() {' "$repo_root/isolated-dotnet-sdk.sh"
  grep -Fq 'tool_heading "Installed .NET SDKs"' "$repo_root/isolated-dotnet-sdk.sh"
  grep -Fq 'tool_label_value "Target SDK:" "$VERSION"' "$repo_root/isolated-dotnet-sdk.sh"
}

@test "bootstrap output is separated from invocation and the first Main menu" {
  raw_output="$test_root/bootstrap-output.txt"

  printf 'e\n' | env HOME="$test_home" "$source_copy" >"$raw_output" 2>&1
  status=$?

  [ "$status" -eq 0 ]
  [ -z "$(sed -n '1p' "$raw_output")" ]
  [[ "$(sed -n '2p' "$raw_output")" == "Installing tool to "* ]]

  tool_installed_line="$(grep -nFx 'Tool installed.' "$raw_output" | head -n 1 | cut -d: -f1)"
  main_heading_line="$(grep -nFx 'What would you like to do?' "$raw_output" | head -n 1 | cut -d: -f1)"
  [ -n "$tool_installed_line" ]
  [ -n "$main_heading_line" ]
  [ "$main_heading_line" -gt "$tool_installed_line" ]

  blank_boundary='false'
  for ((line_number=tool_installed_line + 1; line_number<main_heading_line; line_number++)); do
    if [[ -z "$(sed -n "${line_number}p" "$raw_output")" ]]; then
      blank_boundary='true'
      break
    fi
  done
  [ "$blank_boundary" = 'true' ]
}

@test "presentation source defines semantic accent and stderr-aware error roles" {
  grep -Fq 'tool_label_value() {' "$repo_root/isolated-dotnet-sdk.sh"
  grep -Fq 'tool_metadata() {' "$repo_root/isolated-dotnet-sdk.sh"
  grep -Fq 'if [[ -t 2 ]]; then' "$repo_root/isolated-dotnet-sdk.sh"
  grep -Fq "RED='\\033[0;31m'" "$repo_root/isolated-dotnet-sdk.sh"
}

@test "invalid input formatting replaces terminal control characters" {
  eval "$(sed -n '/^format_tool_input()/,/^}/p' "$repo_root/isolated-dotnet-sdk.sh")"
  result="$(format_tool_input $'x\t')"
  [ "$result" = 'x?' ]
}
