#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-prerelease-picker.XXXXXX")"
  test_home="$test_root/home"
  tool_root="$test_home/dotnet-sdks"
  tool_path="$tool_root/isolated-dotnet-sdk.sh"
  fake_bin="$test_root/bin"
  mkdir -p "$test_home" "$fake_bin"
  cp "$repo_root/isolated-dotnet-sdk.sh" "$test_root/isolated-dotnet-sdk.sh"
  chmod +x "$test_root/isolated-dotnet-sdk.sh"

  run env HOME="$test_home" "$test_root/isolated-dotnet-sdk.sh" list
  [ "$status" -eq 0 ]

  cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url=""
out_file=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out_file="$2"; shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
case "$url" in
  *releases-index.json)
    cat <<JSON
{"releases-index":[{"channel-version":"99.0","latest-sdk":"${FAKE_LATEST:-}","support-phase":"${FAKE_PHASE:-preview}","release-type":"sts","releases.json":"https://example.invalid/99.0/releases.json"}]}
JSON
    ;;
  https://example.invalid/99.0/releases.json)
    if [[ "${FAKE_SINGLE:-0}" == "1" ]]; then
      cat > "$out_file" <<'JSON'
{"releases":[{"sdk":{"version":"99.0.100-rc.2.22","files":[{"url":"https://example.invalid/dotnet/Sdk/99.0.100-rc.2.22/a"}]}}]}
JSON
    elif [[ "${FAKE_STABLE:-0}" == "1" ]]; then
      cat > "$out_file" <<'JSON'
{"releases":[
{"sdk":{"version":"99.0.100-preview.5.5","files":[{"url":"https://example.invalid/dotnet/Sdk/99.0.100-preview.5.5/a"}]}},
{"sdk":{"version":"99.0.101","files":[{"url":"https://example.invalid/dotnet/Sdk/99.0.101/a"}]}},
{"sdk":{"version":"99.0.100-rc.2.22","files":[{"url":"https://example.invalid/dotnet/Sdk/99.0.100-rc.2.22/a"}]}},
{"sdk":{"version":"99.0.100","files":[{"url":"https://example.invalid/dotnet/Sdk/99.0.100/a"}]}}
]}
JSON
    else
      cat > "$out_file" <<'JSON'
{"releases":[
{"sdk":{"version":"99.0.100-preview.5.5","files":[{"url":"https://example.invalid/dotnet/Sdk/99.0.100-preview.5.5/a"}]}},
{"sdk":{"version":"99.0.100-rc.1.11","files":[{"url":"https://example.invalid/dotnet/Sdk/99.0.100-rc.1.11/a"}]}},
{"sdk":{"version":"99.0.100-preview.6.6","files":[{"url":"https://example.invalid/dotnet/Sdk/99.0.100-preview.6.6/a"}]}},
{"sdk":{"version":"99.0.100-rc.2.22","files":[{"url":"https://example.invalid/dotnet/Sdk/99.0.100-rc.2.22/a"}]}}
]}
JSON
    fi
    ;;
  *) exit 88 ;;
esac
EOF
  chmod +x "$fake_bin/curl"
}

teardown() {
  rm -rf "$test_root"
}

run_picker() {
  local input="$1"
  shift
  run bash -c 'printf "%b" "$1" | env HOME="$2" PATH="$3:$PATH" "$@"' _ \
    "$input" "$test_home" "$fake_bin" "$@"
}

picker_view() {
  local wanted="$1"
  printf '%s\n' "$output" | awk -v wanted="$wanted" '
    /Available \.NET 99\.0 SDKs:/ { count++; inside=1 }
    inside && count == wanted { print }
    /B\. Back to \.NET channels/ && inside { inside=0 }
  '
}

@test "prerelease defaults to all Preview and RC versions in SDK-aware order with latest marker" {
  run_picker '1\nq\n' FAKE_LATEST=99.0.100-rc.2.22 FAKE_PHASE=preview "$tool_path" install
  [ "$status" -eq 0 ]
  view="$(picker_view 1)"
  [[ "$view" == *"1. 99.0.100-rc.2.22 (latest)"* ]]
  [[ "$view" == *"2. 99.0.100-rc.1.11"* ]]
  [[ "$view" == *"3. 99.0.100-preview.6.6"* ]]
  [[ "$view" == *"4. 99.0.100-preview.5.5"* ]]
  [[ "$view" == *"S. Show featured versions"* ]]
  [[ "$view" == *"Q. Cancel"* ]]
}

@test "prerelease view toggle is reciprocal and returns to complete view" {
  run_picker '1\ns\ns\nq\n' FAKE_LATEST=99.0.100-rc.2.22 "$tool_path" install
  [ "$status" -eq 0 ]
  first="$(picker_view 1)"
  second="$(picker_view 2)"
  third="$(picker_view 3)"
  [[ "$first" == *"4. 99.0.100-preview.5.5"* ]]
  [[ "$second" == *"1. 99.0.100-rc.2.22 (latest)"* ]]
  [[ "$second" != *"2. 99.0.100-rc.1.11"* ]]
  [[ "$second" == *"S. Show all versions"* ]]
  [[ "$third" == *"4. 99.0.100-preview.5.5"* ]]
  [[ "$third" == *"S. Show featured versions"* ]]
}

@test "stable latest defaults featured even when old preview builds exist and phase says preview" {
  run_picker '1\ns\nq\n' FAKE_LATEST=99.0.101 FAKE_STABLE=1 FAKE_PHASE=preview "$tool_path" install
  [ "$status" -eq 0 ]
  first="$(picker_view 1)"
  second="$(picker_view 2)"
  [[ "$first" == *"1. 99.0.101 (latest)"* ]]
  [[ "$first" != *"2. 99.0.100"* ]]
  [[ "$first" == *"S. Show all versions"* ]]
  [[ "$second" == *"2. 99.0.100"* ]]
  [[ "$second" == *"S. Show featured versions"* ]]
}

@test "one discovered prerelease SDK has no meaningless S toggle" {
  run_picker '1\nq\n' FAKE_LATEST=99.0.100-rc.2.22 FAKE_SINGLE=1 "$tool_path" install
  [ "$status" -eq 0 ]
  view="$(picker_view 1)"
  [[ "$view" == *"1. 99.0.100-rc.2.22 (latest)"* ]]
  [[ "$view" != *"S. Show"* ]]
}

@test "missing or nonmatching latest metadata uses discovered newest prerelease without fabricated marker" {
  for latest in '' '99.0.100-rc.99.99'; do
    run_picker '1\nq\n' "FAKE_LATEST=$latest" "$tool_path" install
    [ "$status" -eq 0 ]
    view="$(picker_view 1)"
    [[ "$view" == *"1. 99.0.100-rc.2.22"* ]]
    [[ "$view" == *"4. 99.0.100-preview.5.5"* ]]
    [[ "$view" == *"S. Show featured versions"* ]]
    [[ "$view" != *"(latest)"* ]]
  done
}

@test "fallback to newest discovered stable SDK stays compact and preserves installed marker" {
  mkdir -p "$tool_root/99.0.101"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$tool_root/99.0.101/dotnet"
  chmod +x "$tool_root/99.0.101/dotnet"
  run_picker '1\nq\n' FAKE_LATEST=not-in-releases FAKE_STABLE=1 "$tool_path" install
  [ "$status" -eq 0 ]
  view="$(picker_view 1)"
  [[ "$view" == *"1. 99.0.101 (isolated)"* ]]
  [[ "$view" == *"S. Show all versions"* ]]
  [[ "$view" != *"(latest"* ]]
}
