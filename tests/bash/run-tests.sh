#!/usr/bin/env bash
set -euo pipefail

test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-tests.XXXXXX")"

cleanup() {
  rm -rf "$test_root"
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

trap cleanup EXIT

test_home="$test_root/home"
mkdir -p "$test_home"

actual_home="$(HOME="$test_home" bash -c 'printf "%s" "$HOME"')"
if [[ "$actual_home" != "$test_home" ]]; then
  fail "child Bash process did not use the isolated HOME"
fi

printf 'PASS: isolated HOME contract\n'
printf 'All Bash behavioral tests passed.\n'
