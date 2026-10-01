from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    return text.replace(old, new, 1)


source_path = Path("isolated-dotnet-sdk.sh")
source = source_path.read_text()

selection_block = '''selection_range() {
    local count="$1"
    if (( count <= 1 )); then
        printf '%s' '1'
    else
        printf '1-%d' "$count"
    fi
}
'''
selection_with_join = selection_block + r'''
join_sdk_inventory_path() {
    local sdk_root="$1"
    local version="$2"

    if [[ "$sdk_root" == *\\* ]]; then
        sdk_root="${sdk_root%\\}"
        printf '%s\\%s' "$sdk_root" "$version"
    else
        sdk_root="${sdk_root%/}"
        printf '%s/%s' "$sdk_root" "$version"
    fi
}
'''
source = replace_once(source, selection_block, selection_with_join, "insert path join helper")
source = replace_once(
    source,
    '            sdk_path="${BASH_REMATCH[2]%/}/$version"',
    '            sdk_path="$(join_sdk_inventory_path "${BASH_REMATCH[2]}" "$version")"',
    "list path join",
)
source = replace_once(
    source,
    '            system_sdk_path="${BASH_REMATCH[1]%/}/$VERSION"',
    '            system_sdk_path="$(join_sdk_inventory_path "${BASH_REMATCH[1]}" "$VERSION")"',
    "install path join",
)
source_path.write_text(source)

listing_path = Path("tests/bash/installed-sdk-listing.bats")
listing = listing_path.read_text()
anchor = '''@test "direct list shows isolated SDKs before system SDKs and preserves overlap" {
'''
new_test = r'''@test "direct list preserves Windows-style system SDK path separators" {
  bootstrap_tool
  fake_bin="$test_root/windows-system-bin"
  write_fake_system_dotnet "$fake_bin" '10.0.401 [C:\Program Files\dotnet\sdk]'

  run env HOME="$test_home" PATH="$fake_bin:$PATH" "$tool_path" list

  [ "$status" -eq 0 ]
  [[ "$output" == *'10.0.401  C:\Program Files\dotnet\sdk\10.0.401'* ]]
  [[ "$output" != *'C:\Program Files\dotnet\sdk/10.0.401'* ]]
}

'''
listing = replace_once(listing, anchor, new_test + anchor, "listing Windows path test")
listing_path.write_text(listing)

status_path = Path("tests/bash/install-status.bats")
status = status_path.read_text()
helper_anchor = '''make_isolated_dotnet() {
'''
windows_helper = r'''make_windows_system_dotnet() {
  system_bin="$test_root/windows-system-bin"
  mkdir -p "$system_bin"

  cat > "$system_bin/dotnet" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" != "--list-sdks" ]]; then
  exit 91
fi
printf '%s\n' '$version [C:\Program Files\dotnet\sdk]'
EOF
  chmod +x "$system_bin/dotnet"
}

'''
status = replace_once(status, helper_anchor, windows_helper + helper_anchor, "install Windows helper")
status_anchor = '''@test "install reports an existing isolated target without unrelated System inventory" {
'''
windows_status_test = r'''@test "install status preserves Windows-style system SDK path separators" {
  make_windows_system_dotnet

  run bash -c 'printf "\n" | env HOME="$1" PATH="$2:$PATH" "$3" install "$4"' _ \
    "$test_home" "$system_bin" "$tool_path" "$version"

  [ "$status" -eq 0 ]
  [[ "$output" == *'Location: C:\Program Files\dotnet\sdk\99.0.100'* ]]
  [[ "$output" != *'C:\Program Files\dotnet\sdk/99.0.100'* ]]
  [[ "$output" == *"Installation cancelled."* ]]
}

'''
status = replace_once(status, status_anchor, windows_status_test + status_anchor, "install Windows path test")
status_path.write_text(status)
