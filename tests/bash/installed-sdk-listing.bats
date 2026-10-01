#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-installed-list-tests.XXXXXX")"
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

write_fake_system_dotnet() {
  local fake_bin="$1"
  shift
  mkdir -p "$fake_bin"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' 'if [[ "${1:-}" != "--list-sdks" ]]; then exit 97; fi'
    for line in "$@"; do
      printf 'printf "%%s\\n" %q\n' "$line"
    done
  } > "$fake_bin/dotnet"
  chmod +x "$fake_bin/dotnet"
}

bootstrap_tool() {
  prepare_source
  bootstrap_bin="$test_root/bootstrap-bin"
  write_fake_system_dotnet "$bootstrap_bin"

  run env HOME="$test_home" PATH="$bootstrap_bin:$PATH" "$source_copy" list
  [ "$status" -eq 0 ]
}

create_isolated_sdk() {
  local version="$1"
  local install_dir="$tool_root/$version"
  mkdir -p "$install_dir"
  cat > "$install_dir/dotnet" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$install_dir/dotnet"
}

@test "direct list shows an isolated-only inventory with an empty System SDKs group" {
  bootstrap_tool
  create_isolated_sdk '10.0.401'
  fake_bin="$test_root/empty-system-bin"
  write_fake_system_dotnet "$fake_bin"

  run env HOME="$test_home" PATH="$fake_bin:$PATH" "$tool_path" list

  [ "$status" -eq 0 ]
  [[ "$output" == *"10.0.401  $tool_root/10.0.401"* ]]
  system_section="$(printf '%s\n' "$output" | sed -n '/^System SDKs:$/,$p')"
  [[ "$system_section" == *"  None"* ]]
}

@test "direct list shows a system-only inventory with an empty Isolated SDKs group" {
  bootstrap_tool
  fake_bin="$test_root/system-only-bin"
  write_fake_system_dotnet "$fake_bin" '10.0.401 [/usr/share/dotnet/sdk]'

  run env HOME="$test_home" PATH="$fake_bin:$PATH" "$tool_path" list

  [ "$status" -eq 0 ]
  isolated_section="$(printf '%s\n' "$output" | sed -n '/^Isolated SDKs:$/,/^System SDKs:$/p')"
  [[ "$isolated_section" == *"  None"* ]]
  [[ "$output" == *"10.0.401  /usr/share/dotnet/sdk/10.0.401"* ]]
}

@test "direct list shows isolated SDKs before system SDKs and preserves overlap" {
  bootstrap_tool
  create_isolated_sdk '11.0.100-rc.1.26425.128'
  create_isolated_sdk '10.0.401'

  fake_bin="$test_root/system-bin"
  write_fake_system_dotnet \
    "$fake_bin" \
    '10.0.401 [/usr/share/dotnet/sdk]' \
    '9.0.318 [/opt/dotnet sdk]'

  run env HOME="$test_home" PATH="$fake_bin:$PATH" "$tool_path" list

  [ "$status" -eq 0 ]
  [[ "$output" == *"Installed .NET SDKs"* ]]
  [[ "$output" == *"Isolated SDKs:"* ]]
  [[ "$output" == *"System SDKs:"* ]]
  [[ "$output" == *"11.0.100-rc.1.26425.128  $tool_root/11.0.100-rc.1.26425.128"* ]]
  [[ "$output" == *"10.0.401  $tool_root/10.0.401"* ]]
  [[ "$output" == *"10.0.401  /usr/share/dotnet/sdk/10.0.401"* ]]
  [[ "$output" == *"9.0.318  /opt/dotnet sdk/9.0.318"* ]]
  [ "$(printf '%s\n' "$output" | grep -c '10\.0\.401')" -eq 2 ]

  isolated_line="$(printf '%s\n' "$output" | grep -n -m1 '^Isolated SDKs:$' | cut -d: -f1)"
  system_line="$(printf '%s\n' "$output" | grep -n -m1 '^System SDKs:$' | cut -d: -f1)"
  [ "$isolated_line" -lt "$system_line" ]
}

@test "direct list shows None for both empty ownership groups" {
  bootstrap_tool
  fake_bin="$test_root/empty-system-bin"
  write_fake_system_dotnet "$fake_bin"

  run env HOME="$test_home" PATH="$fake_bin:$PATH" "$tool_path" list

  [ "$status" -eq 0 ]
  [[ "$output" == *"Isolated SDKs:"* ]]
  [[ "$output" == *"System SDKs:"* ]]
  [ "$(printf '%s\n' "$output" | grep -c '^  None$')" -eq 2 ]
}

@test "direct list treats an unavailable system dotnet host as an empty System SDKs group" {
  bootstrap_tool
  no_dotnet_bin="$test_root/no-dotnet-bin"
  mkdir -p "$no_dotnet_bin"

  for command_name in bash mkdir dirname basename; do
    command_path="$(command -v "$command_name")"
    ln -s "$command_path" "$no_dotnet_bin/$command_name"
  done

  run env HOME="$test_home" PATH="$no_dotnet_bin" "$tool_path" list

  [ "$status" -eq 0 ]
  [[ "$output" == *"System SDKs:"* ]]
  system_section="$(printf '%s\n' "$output" | sed -n '/^System SDKs:$/,$p')"
  [[ "$system_section" == *"  None"* ]]
}

@test "direct list fails when the resolved system dotnet host inventory fails" {
  bootstrap_tool
  fake_bin="$test_root/failing-system-bin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/dotnet" <<'EOF'
#!/usr/bin/env bash
exit 71
EOF
  chmod +x "$fake_bin/dotnet"

  run env HOME="$test_home" PATH="$fake_bin:$PATH" "$tool_path" list

  [ "$status" -ne 0 ]
  [[ "$output" == *"Unable to list SDKs through the system dotnet host with exit code 71."* ]]
  [[ "$output" != *"System SDKs:"* ]]
}

@test "interactive main menu calls the combined view List installed SDKs" {
  bootstrap_tool

  run bash -c 'printf "e\n" | env HOME="$1" "$2"' _ "$test_home" "$tool_path"

  [ "$status" -eq 0 ]
  [[ "$output" == *"3. List installed SDKs"* ]]
  [[ "$output" != *"3. List isolated SDKs"* ]]
}

@test "system-only SDKs do not become removable" {
  bootstrap_tool
  fake_bin="$test_root/system-only-bin"
  write_fake_system_dotnet "$fake_bin" '10.0.401 [/usr/share/dotnet/sdk]'

  run env HOME="$test_home" PATH="$fake_bin:$PATH" "$tool_path" remove 10.0.401 --yes

  [ "$status" -ne 0 ]
  [[ "$output" == *"Isolated SDK 10.0.401 was not found"* ]]
  [ -x "$fake_bin/dotnet" ]
}
