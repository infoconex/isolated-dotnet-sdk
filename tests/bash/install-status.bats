#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-install-status.XXXXXX")"
  test_home="$test_root/home"
  tool_root="$test_home/dotnet-sdks"
  tool_path="$tool_root/isolated-dotnet-sdk.sh"
  source_copy="$test_root/isolated-dotnet-sdk-source.sh"
  version='99.0.100'
  unrelated_version='8.0.425'

  mkdir -p "$test_home"
  cp "$repo_root/isolated-dotnet-sdk.sh" "$source_copy"
  chmod +x "$source_copy"

  run env HOME="$test_home" "$source_copy" list
  [ "$status" -eq 0 ]
}

teardown() {
  rm -rf "$test_root"
}

make_system_dotnet() {
  local include_target="$1"
  system_bin="$test_root/system-bin"
  mkdir -p "$system_bin"

  cat > "$system_bin/dotnet" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" != "--list-sdks" ]]; then
  exit 91
fi
printf '%s\n' '$unrelated_version [/system/sdk]'
if [[ '$include_target' == 'true' ]]; then
  printf '%s\n' '$version [/system/sdk]'
fi
EOF
  chmod +x "$system_bin/dotnet"
}

make_isolated_dotnet() {
  local install_dir="$tool_root/$version"
  mkdir -p "$install_dir"
  cat > "$install_dir/dotnet" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "--list-sdks" ]]; then
  printf '%s\n' '$version [$install_dir/sdk]'
  exit 0
fi
exit 92
EOF
  chmod +x "$install_dir/dotnet"
}

@test "install reports only the selected System SDK and preserves confirmation" {
  make_system_dotnet true

  run bash -c 'printf "\n" | env HOME="$1" PATH="$2:$PATH" "$3" install "$4"' _ \
    "$test_home" "$system_bin" "$tool_path" "$version"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Checking existing installations..."* ]]
  [[ "$output" == *"System SDK: Already installed"* ]]
  [[ "$output" == *"Location: /system/sdk/$version"* ]]
  [[ "$output" == *"Isolated SDK: Not installed"* ]]
  [[ "$output" == *$'Isolated SDK: Not installed\n\nSystem SDK: Already installed'* ]]
  [[ "$output" == *"Installation cancelled."* ]]
  [[ "$output" != *"Loading Microsoft release metadata"* ]]
  [[ "$output" != *"$unrelated_version"* ]]
  [[ "$output" != *"normal dotnet host"* ]]
  [[ "$output" != *"installed normally"* ]]
}

@test "install reports an existing isolated target without unrelated System inventory" {
  make_system_dotnet false
  make_isolated_dotnet

  run env HOME="$test_home" PATH="$system_bin:$PATH" "$tool_path" install "$version" --yes

  [ "$status" -eq 0 ]
  [[ "$output" == *"Checking existing installations..."* ]]
  [[ "$output" == *"System SDK: Not installed"* ]]
  [[ "$output" == *"Location: $tool_root/$version"*$'\n\nSystem SDK: Not installed'* ]]
  [[ "$output" == *"Isolated SDK: Already installed"* ]]
  [[ "$output" == *"Location: $tool_root/$version"* ]]
  [[ "$output" != *"$unrelated_version"* ]]
  [[ "$output" != *"Loading Microsoft release metadata"* ]]
}

@test "install reports both ownership states when the selected target exists in both" {
  make_system_dotnet true
  make_isolated_dotnet

  run env HOME="$test_home" PATH="$system_bin:$PATH" "$tool_path" install "$version" --yes

  [ "$status" -eq 0 ]
  [[ "$output" == *"System SDK: Already installed"* ]]
  [[ "$output" == *"Location: /system/sdk/$version"* ]]
  [[ "$output" == *"Location: $tool_root/$version"*$'\n\nSystem SDK: Already installed'* ]]
  [[ "$output" == *"Isolated SDK: Already installed"* ]]
  [[ "$output" == *"Location: $tool_root/$version"* ]]
  [[ "$output" != *"$unrelated_version"* ]]
  [[ "$output" != *"Loading Microsoft release metadata"* ]]
}

@test "install reports neither ownership state before continuing to acquisition" {
  make_system_dotnet false
  cat > "$system_bin/curl" <<'EOF'
#!/usr/bin/env bash
exit 88
EOF
  chmod +x "$system_bin/curl"

  run env HOME="$test_home" PATH="$system_bin:$PATH" "$tool_path" install "$version" --yes

  [ "$status" -ne 0 ]
  [[ "$output" == *"Checking existing installations..."* ]]
  [[ "$output" == *"System SDK: Not installed"* ]]
  [[ "$output" == *$'Isolated SDK: Not installed\n\nSystem SDK: Not installed'* ]]
  [[ "$output" == *"Isolated SDK: Not installed"* ]]
  [[ "$output" != *"$unrelated_version"* ]]
}
