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

write_metadata_fake_curl() {
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
    }
  ]
}
JSON
    ;;
  https://example.invalid/10.0/releases.json)
    cat > "$out_file" <<'JSON'
{
  "releases": [
    {"sdk":{"version":"10.0.303","files":[{"url":"https://example.invalid/dotnet/Sdk/10.0.303/a"}]}},
    {"sdk":{"version":"10.0.401","files":[{"url":"https://example.invalid/dotnet/Sdk/10.0.401/a"}]}},
    {"sdk":{"version":"10.0.201","files":[{"url":"https://example.invalid/dotnet/Sdk/10.0.201/a"}]}},
    {"sdk":{"version":"10.0.400","files":[{"url":"https://example.invalid/dotnet/Sdk/10.0.400/a"}]}},
    {"sdk":{"version":"10.0.305","files":[{"url":"https://example.invalid/dotnet/Sdk/10.0.305/a"}]}}
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

@test "Install channel Back returns to Main" {
  bootstrap_tool
  fake_bin="$test_root/channel-back-fake-bin"
  write_metadata_fake_curl "$fake_bin"

  run bash -c 'printf "1\nb\n4\n" | env HOME="$1" PATH="$2:$PATH" "$3"' _ \
    "$test_home" "$fake_bin" "$tool_path"

  [ "$status" -eq 0 ]
  [ "$(count_main_prompts "$output")" -eq 2 ]
  [[ "$output" == *"B. Back to Main"* ]]
}

@test "Install SDK Back returns to channel selection" {
  bootstrap_tool
  fake_bin="$test_root/version-back-fake-bin"
  write_metadata_fake_curl "$fake_bin"

  run bash -c 'printf "1\nb\nq\n" | env HOME="$1" PATH="$2:$PATH" "$3" install' _ \
    "$test_home" "$fake_bin" "$tool_path"

  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'Select a supported or development .NET channel:' || true)" -eq 2 ]
  [[ "$output" == *"B. Back to .NET channels"* ]]
}

@test "Remove Back returns to Main without confirmation semantics" {
  bootstrap_tool
  version='99.0.100'
  mkdir -p "$tool_root/$version"
  cat > "$tool_root/$version/dotnet" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$tool_root/$version/dotnet"

  run bash -c 'printf "2\nb\n4\n" | env HOME="$1" "$2"' _ "$test_home" "$tool_path"

  [ "$status" -eq 0 ]
  [ "$(count_main_prompts "$output")" -eq 2 ]
  [[ "$output" == *"B. Back to Main"* ]]
  [[ "$output" != *"Continue?"* ]]
}

@test "SDK picker shows latest and newest feature bands before older servicing versions" {
  bootstrap_tool
  fake_bin="$test_root/version-list-fake-bin"
  write_metadata_fake_curl "$fake_bin"

  run bash -c 'printf "1\ns\nq\n" | env HOME="$1" PATH="$2:$PATH" "$3" install' _ \
    "$test_home" "$fake_bin" "$tool_path"

  [ "$status" -eq 0 ]
  [[ "$output" == *"1. 10.0.401 (latest)"* ]]
  [[ "$output" == *"2. 10.0.305"* ]]
  [[ "$output" == *"3. 10.0.201"* ]]
  [[ "$output" == *"S. Show all versions"* ]]
  [ "$(printf '%s\n' "$output" | grep -c '10\.0\.400' || true)" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c '10\.0\.303' || true)" -eq 1 ]
}

@test "one interactive session can Install List Remove and Exit" {
  bootstrap_tool
  fake_bin="$test_root/multi-operation-fake-bin"
  write_metadata_fake_curl "$fake_bin"
  version='10.0.401'
  install_dir="$tool_root/$version"
  mkdir -p "$install_dir"
  cat > "$install_dir/dotnet" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == '--list-sdks' ]]; then
  printf '%s\n' '$version [/fake]'
fi
exit 0
EOF
  chmod +x "$install_dir/dotnet"

  run bash -c 'printf "1\n1\n1\n3\n2\n1\ny\n4\n" | env HOME="$1" PATH="$2:$PATH" "$3"' _ \
    "$test_home" "$fake_bin" "$tool_path"

  [ "$status" -eq 0 ]
  [ "$(count_main_prompts "$output")" -eq 4 ]
  [[ "$output" == *"Isolated SDK $version is already installed."* ]]
  [[ "$output" == *"Isolated SDK $version was removed."* ]]
  [[ "$output" == *"Exiting."* ]]
  [ ! -d "$install_dir" ]
}
