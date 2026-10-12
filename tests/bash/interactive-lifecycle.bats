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

count_acknowledgement_prompts() {
  printf '%s\n' "$1" | grep -Ec 'Press Enter to return to .+\.\.\.' || true
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

@test "terminal interactive List waits for Enter before returning to Main" {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    skip "BSD script does not deterministically drive bidirectional PTY input in CI"
  fi

  bootstrap_tool
  wrapper="$test_root/interactive-tty.sh"
  cat > "$wrapper" <<EOF
#!/usr/bin/env bash
export HOME="$test_home"
exec "$tool_path"
EOF
  chmod +x "$wrapper"

  run bash -c 'printf "l\n\ne\n" | TERM=xterm script -q -c "$1" /dev/null' _ "$wrapper"

  [ "$status" -eq 0 ]
  [ "$(count_main_prompts "$output")" -eq 2 ]
  [ "$(count_acknowledgement_prompts "$output")" -eq 1 ]
  [[ "$output" == *"Press Enter to return to Main..."* ]]
  [[ "$output" == *"Exiting."* ]]

  # The completed result precedes Enter; the cleared parent screen follows it.
  before_ack="${output%%Press Enter to return to Main...*}"
  after_ack="${output#*Press Enter to return to Main...}"
  [[ "$before_ack" == *$'\e[H\e[2J'* ]]
  [[ "$after_ack" == *$'\e[H\e[2J'* ]]
  [[ "$after_ack" == *"What would you like to do?"* ]]
}

@test "terminal without clearing capability retains scrolling and acknowledgement" {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    skip "BSD script does not deterministically drive bidirectional PTY input in CI"
  fi

  bootstrap_tool
  wrapper="$test_root/interactive-dumb-tty.sh"
  cat > "$wrapper" <<EOF
#!/usr/bin/env bash
export HOME="$test_home"
exec "$tool_path"
EOF
  chmod +x "$wrapper"

  run bash -c 'printf "l\n\ne\n" | TERM=dumb script -q -c "$1" /dev/null' _ "$wrapper"

  [ "$status" -eq 0 ]
  [ "$(count_main_prompts "$output")" -eq 2 ]
  [ "$(count_acknowledgement_prompts "$output")" -eq 1 ]
  [[ "$output" != *$'\e[H\e[2J'* ]]
}

@test "captured persistent List returns to Main without acknowledgement" {
  prepare_source

  run bash -c 'printf "l\ne\n" | env HOME="$1" "$2"' _ "$test_home" "$source_copy"

  [ "$status" -eq 0 ]
  [ "$(count_main_prompts "$output")" -eq 2 ]
  [ "$(count_acknowledgement_prompts "$output")" -eq 0 ]
  [[ "$output" == *"Isolated SDKs:"* ]]
  [[ "$output" == *"System SDKs:"* ]]
  [[ "$output" == *"Exiting."* ]]
  [[ "$output" != *$'\e[H\e[2J'* ]]
}

@test "captured persistent Remove no-change returns without acknowledgement" {
  prepare_source

  run bash -c 'printf "r\ne\n" | env HOME="$1" "$2"' _ "$test_home" "$source_copy"

  [ "$status" -eq 0 ]
  [ "$(count_main_prompts "$output")" -eq 2 ]
  [ "$(count_acknowledgement_prompts "$output")" -eq 0 ]
  [[ "$output" == *"No isolated SDKs are installed"* ]]
  [[ "$output" == *"Removal cancelled."* ]]
}

@test "explicit List remains one-shot without acknowledgement" {
  bootstrap_tool

  run env HOME="$test_home" "$tool_path" list

  [ "$status" -eq 0 ]
  [ "$(count_main_prompts "$output")" -eq 0 ]
  [ "$(count_acknowledgement_prompts "$output")" -eq 0 ]
  [[ "$output" == *"Installed .NET SDKs"* ]]
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

  run bash -c 'printf "i\ne\n" | env HOME="$1" PATH="$2:$PATH" "$3"' _ \
    "$test_home" "$fake_bin" "$tool_path"

  [ "$status" -ne 0 ]
  [ "$(count_main_prompts "$output")" -eq 1 ]
  [ "$(count_acknowledgement_prompts "$output")" -eq 0 ]
  [[ "$output" == *"Unable to load .NET release metadata from Microsoft."* ]]
  [[ "$output" != *"Exiting."* ]]
}

@test "terminal Install Verify and Remove clear selected picker before their operation result" {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    skip "BSD script does not deterministically drive bidirectional PTY input in CI"
  fi

  bootstrap_tool
  fake_bin="$test_root/operation-tty-bin"
  write_metadata_fake_curl "$fake_bin"
  for version in '10.0.401' '9.0.318'; do
    mkdir -p "$tool_root/$version"
    cat > "$tool_root/$version/dotnet" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == '--list-sdks' ]]; then
  printf '%s\n' '$version [/fake/sdk]'
fi
exit 0
EOF
    chmod +x "$tool_root/$version/dotnet"
  done
  wrapper="$test_root/operation-tty.sh"
  cat > "$wrapper" <<EOF
#!/usr/bin/env bash
export HOME="$test_home"
export PATH="$fake_bin:$PATH"
exec "$tool_path"
EOF
  chmod +x "$wrapper"
  clear_sequence="$(printf '\033[H\033[2J')"

  assert_operation_view() {
    local picker_tail="$1" first_output="$2" success="$3" acknowledgement="$4" parent="$5"
    local after_picker before_first after_first before_ack after_ack without_clear
    after_picker="${output#*"$picker_tail"}"
    [[ "$after_picker" != "$output" ]] || return 1
    before_first="${after_picker%%"$first_output"*}"
    [[ "$before_first" == *"$clear_sequence"* ]] || return 1
    without_clear="${before_first//"$clear_sequence"/}"
    [ "$(( (${#before_first} - ${#without_clear}) / ${#clear_sequence} ))" -eq 1 ] || return 1
    after_first="${after_picker#*"$first_output"}"
    before_ack="${after_first%%"$acknowledgement"*}"
    [[ "$before_ack" == *"$success"* ]] || return 1
    [[ "$before_ack" != *"$clear_sequence"* ]] || return 1
    after_ack="${after_first#*"$acknowledgement"}"
    [[ "$after_ack" == *"$clear_sequence"* ]] || return 1
    [[ "$after_ack" == *"$parent"* ]]
  }

  run bash -c 'printf "i\n1\n1\n\nb\nb\ne\n" | TERM=xterm script -q -c "$1" /dev/null' _ "$wrapper"
  [ "$status" -eq 0 ]
  [ "$(count_acknowledgement_prompts "$output")" -eq 1 ]
  assert_operation_view 'B. Back to .NET channels' 'Target SDK:' \
    'Already installed' 'Press Enter to return to SDK selection...' \
    'Available .NET 10.0 SDKs:'

  run bash -c 'printf "v\n1\n\nb\ne\n" | TERM=xterm script -q -c "$1" /dev/null' _ "$wrapper"
  [ "$status" -eq 0 ]
  [ "$(count_acknowledgement_prompts "$output")" -eq 1 ]
  assert_operation_view 'B. Back to Main' 'Isolated SDK 10.0.401 is healthy.' \
    'Location:' 'Press Enter to return to Verify...' 'Select an isolated SDK to verify:'

  run bash -c 'printf "r\n1\ny\n\nb\ne\n" | TERM=xterm script -q -c "$1" /dev/null' _ "$wrapper"
  [ "$status" -eq 0 ]
  [ "$(count_acknowledgement_prompts "$output")" -eq 1 ]
  assert_operation_view 'B. Back to Main' 'Isolated SDK 10.0.401 will be removed' \
    'Isolated SDK 10.0.401 was removed.' 'Press Enter to return to Remove...' \
    'Select an isolated SDK to remove:'
}

@test "terminal nested Install Back clears each destination without waiting" {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    skip "BSD script does not deterministically drive bidirectional PTY input in CI"
  fi

  bootstrap_tool
  fake_bin="$test_root/channel-back-tty-bin"
  write_metadata_fake_curl "$fake_bin"
  wrapper="$test_root/interactive-channel-tty.sh"
  cat > "$wrapper" <<EOF
#!/usr/bin/env bash
export HOME="$test_home"
export PATH="$fake_bin:$PATH"
exec "$tool_path"
EOF
  chmod +x "$wrapper"

  run bash -c 'printf "i\n1\nb\nb\ne\n" | TERM=xterm script -q -c "$1" /dev/null' _ "$wrapper"

  [ "$status" -eq 0 ]
  [ "$(count_main_prompts "$output")" -eq 2 ]
  [ "$(count_acknowledgement_prompts "$output")" -eq 0 ]
  [[ "$output" == *"Available .NET 10.0 SDKs:"* ]]
  [[ "$output" == *$'\e[H\e[2J'* ]]
  clear_sequences="${output//$'\e[H\e[2J'/}"
  [ "$(( (${#output} - ${#clear_sequences}) / 7 ))" -ge 4 ]
}

@test "terminal Install view toggles clear only changed selection views" {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    skip "BSD script does not deterministically drive bidirectional PTY input in CI"
  fi

  bootstrap_tool
  fake_bin="$test_root/channel-view-tty-bin"
  write_metadata_fake_curl "$fake_bin"
  wrapper="$test_root/interactive-view-tty.sh"
  cat > "$wrapper" <<EOF
#!/usr/bin/env bash
export HOME="$test_home"
export PATH="$fake_bin:$PATH"
exec "$tool_path"
EOF
  chmod +x "$wrapper"

  run bash -c 'printf "i\ns\ns\n1\ns\nb\nb\ne\n" | TERM=xterm script -q -c "$1" /dev/null' _ "$wrapper"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Select an end-of-life .NET channel:"* ]]
  [[ "$output" == *"S. Show all versions"* ]]
  [[ "$output" == *"S. Show featured versions"* ]]
  clear_sequences="${output//$'\e[H\e[2J'/}"
  [ "$(( (${#output} - ${#clear_sequences}) / 7 ))" -ge 7 ]
}

@test "terminal invalid Main selection and one-shot List never clear" {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    skip "BSD script does not deterministically drive bidirectional PTY input in CI"
  fi

  bootstrap_tool
  wrapper="$test_root/interactive-retry-tty.sh"
  cat > "$wrapper" <<EOF
#!/usr/bin/env bash
export HOME="$test_home"
exec "$tool_path" "\$@"
EOF
  chmod +x "$wrapper"

  run bash -c 'printf "\n6\ne\n" | TERM=xterm script -q -c "$1" /dev/null' _ "$wrapper"
  [ "$status" -eq 0 ]
  [[ "$output" == *"A selection is required."* ]]
  [[ "$output" == *"Invalid selection: 6."* ]]
  [[ "$output" != *$'\e[H\e[2J'* ]]

  run bash -c 'TERM=xterm script -q -c "$1 list" /dev/null' _ "$wrapper"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Installed .NET SDKs"* ]]
  [[ "$output" != *$'\e[H\e[2J'* ]]
}

@test "Install channel Back returns to Main" {
  bootstrap_tool
  fake_bin="$test_root/channel-back-fake-bin"
  write_metadata_fake_curl "$fake_bin"

  run bash -c 'printf "i\nb\ne\n" | env HOME="$1" PATH="$2:$PATH" "$3"' _ \
    "$test_home" "$fake_bin" "$tool_path"

  [ "$status" -eq 0 ]
  [ "$(count_main_prompts "$output")" -eq 2 ]
  [ "$(count_acknowledgement_prompts "$output")" -eq 0 ]
  [[ "$output" == *"B. Back to Main"* ]]
}


@test "completed Install returns to the selected channel SDK list" {
  bootstrap_tool
  fake_bin="$test_root/install-parent-fake-bin"
  write_metadata_fake_curl "$fake_bin"
  version='10.0.401'
  mkdir -p "$tool_root/$version"
  cat > "$tool_root/$version/dotnet" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == '--list-sdks' ]]; then
  printf '%s [/fake/sdk]\n' '$version'
fi
exit 0
EOF
  chmod +x "$tool_root/$version/dotnet"

  run bash -c 'printf "i\n1\n1\nb\nb\ne\n" | env HOME="$1" PATH="$2:$PATH" "$3"' _ \
    "$test_home" "$fake_bin" "$tool_path"

  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'Available .NET 10.0 SDKs:' || true)" -eq 2 ]
  [ "$(printf '%s\n' "$output" | grep -c 'Select a supported or development .NET channel:' || true)" -eq 2 ]
  [ "$(count_main_prompts "$output")" -eq 2 ]
  [ "$(count_acknowledgement_prompts "$output")" -eq 0 ]
}

@test "captured already-installed interactive Install returns without acknowledgement" {
  bootstrap_tool
  fake_bin="$test_root/install-fake-bin"
  write_metadata_fake_curl "$fake_bin"
  version='99.0.100'
  mkdir -p "$tool_root/$version"
  cat > "$tool_root/$version/dotnet" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == '--list-sdks' ]]; then
  printf '%s [/fake/sdk]\n' '$version'
fi
exit 0
EOF
  chmod +x "$tool_root/$version/dotnet"

  run bash -c 'printf "i\nm\n%s\nb\ne\n" "$4" | env HOME="$1" PATH="$2:$PATH" "$3"' _ \
    "$test_home" "$fake_bin" "$tool_path" "$version"

  [ "$status" -eq 0 ]
  [ "$(count_main_prompts "$output")" -eq 2 ]
  [ "$(count_acknowledgement_prompts "$output")" -eq 0 ]
  [[ "$output" == *"Isolated SDK:"*"Already installed"* ]]
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

  run bash -c 'printf "r\nb\ne\n" | env HOME="$1" "$2"' _ "$test_home" "$tool_path"

  [ "$status" -eq 0 ]
  [ "$(count_main_prompts "$output")" -eq 2 ]
  [[ "$output" == *"B. Back to Main"* ]]
  [[ "$output" != *"Continue?"* ]]
}

@test "completed Remove returns to the Remove SDK list" {
  bootstrap_tool
  for version in '99.0.100' '98.0.100'; do
    mkdir -p "$tool_root/$version"
    cat > "$tool_root/$version/dotnet" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$tool_root/$version/dotnet"
  done

  run bash -c 'printf "r\n1\nb\ne\n" | env HOME="$1" "$2" --yes' _ "$test_home" "$tool_path"

  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'Select an isolated SDK to remove:' || true)" -eq 2 ]
  [[ "$output" == *"Isolated SDK 99.0.100 was removed."* ]]
  [ "$(count_main_prompts "$output")" -eq 2 ]
  [ "$(count_acknowledgement_prompts "$output")" -eq 0 ]
}

@test "Remove choices are sorted newest to oldest" {
  bootstrap_tool
  for version in '8.0.425' '11.0.100-rc.1.26425.128' '10.0.401'; do
    mkdir -p "$tool_root/$version"
    cat > "$tool_root/$version/dotnet" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$tool_root/$version/dotnet"
  done

  run bash -c 'printf "r\nb\ne\n" | env HOME="$1" "$2"' _ "$test_home" "$tool_path"

  [ "$status" -eq 0 ]
  remove_section="$(printf '%s\n' "$output" | sed -n '/Select an isolated SDK to remove:/,/B. Back to Main/p')"
  [[ "$remove_section" == *"1. 11.0.100-rc.1.26425.128"* ]]
  [[ "$remove_section" == *"2. 10.0.401"* ]]
  [[ "$remove_section" == *"3. 8.0.425"* ]]
}

@test "SDK picker shows latest and newest feature bands before older servicing versions" {
  bootstrap_tool
  fake_bin="$test_root/version-list-fake-bin"
  write_metadata_fake_curl "$fake_bin"

  run bash -c 'printf "1\ns\nq\n" | env HOME="$1" PATH="$2:$PATH" "$3" install' _ \
    "$test_home" "$fake_bin" "$tool_path"

  [ "$status" -eq 0 ]
  [[ "$output" == *"1. 10.0.401 (latest"* ]]
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

  run bash -c 'printf "i\n1\n1\nb\nb\nl\nr\n1\ny\ne\n" | env HOME="$1" PATH="$2:$PATH" "$3"' _ \
    "$test_home" "$fake_bin" "$tool_path"

  [ "$status" -eq 0 ]
  [ "$(count_main_prompts "$output")" -eq 4 ]
  [ "$(count_acknowledgement_prompts "$output")" -eq 0 ]
  [[ "$output" == *"Isolated SDK: Already installed"* ]]
  [[ "$output" == *"Isolated SDK $version was removed."* ]]
  [[ "$output" == *"Exiting."* ]]
  [ ! -d "$install_dir" ]
}


@test "Main retry distinguishes blank and nonblank invalid selections" {
  prepare_source

  run bash -c 'printf "\n6\ne\n" | env HOME="$1" "$2" 2>&1' _ "$test_home" "$source_copy"

  [ "$status" -eq 0 ]
  [[ "$output" == *"A selection is required. Choose I, R, L, V, A, or E."* ]]
  [[ "$output" == *"Invalid selection: 6. Choose I, R, L, V, A, or E."* ]]
  [[ "$output" == *$'A selection is required. Choose I, R, L, V, A, or E.\n\nIsolated .NET SDK development (main)\n\nWhat would you like to do?'* ]]
  [[ "$output" == *$'Invalid selection: 6. Choose I, R, L, V, A, or E.\n\nIsolated .NET SDK development (main)\n\nWhat would you like to do?'* ]]
}

@test "Remove retry reports active choices and separates feedback from redraw" {
  bootstrap_tool
  version='99.0.100'
  mkdir -p "$tool_root/$version"
  cat > "$tool_root/$version/dotnet" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$tool_root/$version/dotnet"

  run bash -c 'printf "r\n\n6\nb\ne\n" | env HOME="$1" "$2" 2>&1' _ "$test_home" "$tool_path"

  [ "$status" -eq 0 ]
  [[ "$output" == *"A selection is required. Choose 1, B, or E."* ]]
  [[ "$output" == *"Invalid selection: 6. Choose 1, B, or E."* ]]
  [[ "$output" == *$'A selection is required. Choose 1, B, or E.\n\nSelect an isolated SDK to remove:'* ]]
  [[ "$output" == *$'Invalid selection: 6. Choose 1, B, or E.\n\nSelect an isolated SDK to remove:'* ]]
}
