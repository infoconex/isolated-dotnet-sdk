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


@test "bootstrap output is separated from invocation and saved-tool output" {
  run env HOME="$test_home" "$source_copy" list

  [ "$status" -eq 0 ]
  [[ "$output" == $'\nInstalling tool to '* ]]
  tool_installed_line=-1
  installed_heading_line=-1
  for ((i=0; i<${#lines[@]}; i++)); do
    [[ "${lines[$i]}" == "Tool installed." ]] && tool_installed_line=$i
    [[ "${lines[$i]}" == "Installed .NET SDKs" ]] && installed_heading_line=$i
  done
  [ "$tool_installed_line" -ge 0 ]
  [ "$installed_heading_line" -gt "$tool_installed_line" ]

  blank_boundary='false'
  for ((i=tool_installed_line + 1; i<installed_heading_line; i++)); do
    if [[ -z "${lines[$i]}" ]]; then
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
