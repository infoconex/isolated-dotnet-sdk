#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
config="$repo_root/.config/test-frameworks.json"
expected_version="$(jq -er '.batsVersion | select(type == "string" and length > 0)' "$config")"

if ! command -v bats >/dev/null 2>&1; then
  printf 'Bats %s is required. See docs/testing.md.\n' "$expected_version" >&2
  exit 1
fi

actual_version="$(bats --version | awk '{print $2}')"
if [[ "$actual_version" != "$expected_version" ]]; then
  printf 'Bats version mismatch: expected %s, found %s.\n' "$expected_version" "$actual_version" >&2
  exit 1
fi

exec bats "$repo_root/tests/bash/behavior.bats"
