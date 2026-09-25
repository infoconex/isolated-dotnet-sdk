#!/usr/bin/env bash
set -euo pipefail

required_version="0.11.0"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Keep the repository-owned analysis contract deterministic. User-level ShellCheck
# options and rc files must not change which rules this runner applies.
unset SHELLCHECK_OPTS

if ! command -v shellcheck >/dev/null 2>&1; then
    printf 'ShellCheck %s is required.\n' "$required_version" >&2
    exit 2
fi

actual_version="$(shellcheck --norc --version | awk '$1 == "version:" { print $2 }')"
if [[ "$actual_version" != "$required_version" ]]; then
    printf 'ShellCheck %s is required; found %s.\n' "$required_version" "${actual_version:-unknown}" >&2
    exit 2
fi

shellcheck --norc \
    "$repo_root/isolated-dotnet-sdk.sh" \
    "$repo_root/tests/bash/run-tests.sh" \
    "${BASH_SOURCE[0]}"

printf 'ShellCheck %s passed for 3 file(s).\n' "$required_version"
