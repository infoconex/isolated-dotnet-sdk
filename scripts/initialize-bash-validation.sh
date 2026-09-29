#!/usr/bin/env bash
set -euo pipefail

bats_cache_hit="${1:-false}"
shellcheck_cache_hit="${2:-false}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runner_temp="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
cache_root="$runner_temp/isolated-dotnet-sdk-cache"

test_config="$repo_root/.config/test-frameworks.json"
analysis_config="$repo_root/.config/static-analysis.json"

for path in \
    "$repo_root/isolated-dotnet-sdk.sh" \
    "$repo_root/tests/e2e/bash/direct.sh" \
    "$repo_root/tests/e2e/bash/interactive.sh"; do
    bash -n "$path"
done

bats_version="$(jq -er '.batsVersion | select(type == "string" and length > 0)' "$test_config")"
bats_commit="$(jq -er '.batsCommit | select(type == "string" and test("^[0-9a-f]{40}$"))' "$test_config")"
bats_cache_dir="$cache_root/bats"
bats_prefix="$bats_cache_dir/prefix"
bats_commit_marker="$bats_cache_dir/source-commit"

if [[ "$bats_cache_hit" == "true" ]]; then
    test -x "$bats_prefix/bin/bats"
    test -f "$bats_commit_marker"
    test "$(cat "$bats_commit_marker")" = "$bats_commit"
else
    rm -rf "$bats_cache_dir"
    mkdir -p "$bats_cache_dir"
    bats_source_dir="$runner_temp/bats-core-source"
    rm -rf "$bats_source_dir"
    git -C "$runner_temp" init bats-core-source >/dev/null
    git -C "$bats_source_dir" remote add origin https://github.com/bats-core/bats-core.git
    git -C "$bats_source_dir" fetch --depth=1 origin "$bats_commit"
    git -C "$bats_source_dir" checkout --detach FETCH_HEAD
    test "$(git -C "$bats_source_dir" rev-parse HEAD)" = "$bats_commit"
    "$bats_source_dir/install.sh" "$bats_prefix"
    printf '%s\n' "$bats_commit" > "$bats_commit_marker"
fi

test "$($bats_prefix/bin/bats --version | awk '{print $2}')" = "$bats_version"
if [[ -n "${GITHUB_PATH:-}" ]]; then
    printf '%s\n' "$bats_prefix/bin" >> "$GITHUB_PATH"
fi

if [[ "${RUNNER_OS:-}" == "Linux" ]]; then
    shellcheck_version="$(jq -er '.shellCheckVersion | select(type == "string" and length > 0)' "$analysis_config")"
    shellcheck_checksum="$(jq -er '.shellCheckLinuxX64Sha256 | select(type == "string" and length > 0)' "$analysis_config")"
    shellcheck_cache_dir="$cache_root/shellcheck"
    shellcheck_archive="$shellcheck_cache_dir/shellcheck-v${shellcheck_version}.linux.x86_64.tar.xz"
    shellcheck_url="https://github.com/koalaman/shellcheck/releases/download/v${shellcheck_version}/shellcheck-v${shellcheck_version}.linux.x86_64.tar.xz"

    mkdir -p "$shellcheck_cache_dir"
    if [[ "$shellcheck_cache_hit" != "true" ]]; then
        curl -fsSL "$shellcheck_url" -o "$shellcheck_archive"
    fi

    test -f "$shellcheck_archive"
    printf '%s  %s\n' "$shellcheck_checksum" "$shellcheck_archive" | sha256sum -c -
    rm -rf "$runner_temp/shellcheck-v${shellcheck_version}"
    tar -xJf "$shellcheck_archive" -C "$runner_temp"
    sudo install "$runner_temp/shellcheck-v${shellcheck_version}/shellcheck" /usr/local/bin/shellcheck
    test "$(shellcheck --version | awk '/^version:/ {print $2}')" = "$shellcheck_version"
fi

printf 'Bats-core %s validation setup passed.\n' "$bats_version"
