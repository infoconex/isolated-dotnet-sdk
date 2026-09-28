#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-interactive.XXXXXX")"
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

@test "no-action invocation returns to Main after List and exits explicitly" {
  prepare_source

  run bash -c 'printf "3\n4\n" | env HOME="$1" "$2"' _ "$test_home" "$source_copy"

  [ "$status" -eq 0 ]
  [ "$(count_main_prompts "$output")" -eq 2 ]
  [[ "$output" == *"Isolated SDKs under"* ]]
  [[ "$output" == *"Exiting."* ]]
}

@test "normal interactive Remove no-change returns to Main" {
  prepare_source

  run bash -c 'printf "2\n4\n" | env HOME="$1" "$2"' _ "$test_home" "$source_copy"

  [ "$status" -eq 0 ]
  [ "$(count_main_prompts "$output")" -eq 2 ]
  [[ "$output" == *"No isolated SDKs are installed"* ]]
  [[ "$output" == *"Removal cancelled."* ]]
}

@test "explicit List remains one-shot" {
  bootstrap_tool

  run env HOME="$test_home" "$tool_path" list

  [ "$status" -eq 0 ]
  [ "$(count_main_prompts "$output")" -eq 0 ]
  [[ "$output" == *"Isolated SDKs under"* ]]
}

@test "interactive operational failure is not masked by later Exit input" {
  bootstrap_tool
  fake_bin="$test_root/fake-bin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
exit 7
EOF
  chmod +x "$fake_bin/curl"

  run bash -c 'printf "1\n4\n" | env HOME="$1" PATH="$2:$PATH" "$3"' _ \
    "$test_home" "$fake_bin" "$tool_path"

  [ "$status" -ne 0 ]
  [ "$(count_main_prompts "$output")" -eq 1 ]
  [[ "$output" == *"Unable to load .NET release metadata from Microsoft."* ]]
  [[ "$output" != *"Exiting."* ]]
}
