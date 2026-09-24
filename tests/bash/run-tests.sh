#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-tests.XXXXXX")"

test_home="$test_root/home"
tool_root="$test_home/dotnet-sdks"
tool_path="$tool_root/isolated-dotnet-sdk.sh"
source_copy="$test_root/isolated-dotnet-sdk-source.sh"

cleanup() {
  rm -rf "$test_root"
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'PASS: %s\n' "$1"
}

trap cleanup EXIT

mkdir -p "$test_home"

actual_home="$(HOME="$test_home" bash -c 'printf "%s" "$HOME"')"
if [[ "$actual_home" != "$test_home" ]]; then
  fail "child Bash process did not use the isolated HOME"
fi
pass "isolated HOME contract"

cp "$repo_root/isolated-dotnet-sdk.sh" "$source_copy"
printf '\n# bootstrap-source-marker\n' >> "$source_copy"
chmod +x "$source_copy"

HOME="$test_home" "$source_copy" list >/dev/null

if ! grep -Fq '# bootstrap-source-marker' "$tool_path"; then
  fail "file-based bootstrap did not preserve the exact source script"
fi
pass "file-based bootstrap preserves source"

list_output="$(HOME="$test_home" "$tool_path" list)"
if ! grep -Fq 'Isolated SDKs under' <<< "$list_output"; then
  fail "list output did not include the isolated SDK root heading"
fi
pass "list command"

if HOME="$test_home" "$tool_path" install 'invalid/version' --yes >/dev/null 2>&1; then
  fail "invalid SDK version was accepted"
fi
pass "invalid SDK version rejection"

printf 'All Bash behavioral tests passed.\n'
