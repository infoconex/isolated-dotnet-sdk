#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
base_temp="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
test_root="$(mktemp -d "$base_temp/isolated-dotnet-sdk-e2e-latest-bootstrap.XXXXXX")"
test_home="$test_root/home"
checksums="$test_root/SHA256SUMS"
output="$test_root/bootstrap-output.txt"
mkdir -p "$test_home"

cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT

export HOME="$test_home"

repository='infoconex/isolated-dotnet-sdk'
latest_release_url="https://api.github.com/repos/$repository/releases/latest"
release_download_base_url="https://github.com/$repository/releases/download"

release_json="$(curl -fsSL \
  -H 'Accept: application/vnd.github+json' \
  -H 'X-GitHub-Api-Version: 2022-11-28' \
  "$latest_release_url")"
release_tag="$(jq -er '
  select(.draft == false and .prerelease == false)
  | .tag_name
  | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))
' <<< "$release_json")"

curl -fsSL "$release_download_base_url/$release_tag/SHA256SUMS" -o "$checksums"
expected="$(awk '
  NF == 2 && $2 == "isolated-dotnet-sdk.sh" && $1 ~ /^[0-9a-fA-F]{64}$/ {
    print tolower($1)
  }
' "$checksums")"
if [[ ! "$expected" =~ ^[0-9a-f]{64}$ ]]; then
  printf '%s\n' 'Current stable release does not contain exactly one valid Bash checksum entry.' >&2
  exit 1
fi

printf 'E\n' | bash "$repo_root/install.sh" > "$output" 2>&1
cat "$output"

saved_tool="$HOME/dotnet-sdks/isolated-dotnet-sdk.sh"
if [[ ! -f "$saved_tool" ]]; then
  printf 'Latest-stable bootstrap did not save the released Bash tool at %s.\n' "$saved_tool" >&2
  exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$saved_tool" | awk '{print tolower($1)}')"
elif command -v shasum >/dev/null 2>&1; then
  actual="$(shasum -a 256 "$saved_tool" | awk '{print tolower($1)}')"
else
  printf '%s\n' 'E2E verification requires sha256sum or shasum.' >&2
  exit 1
fi

if [[ "$actual" != "$expected" ]]; then
  printf 'Saved Bash tool does not match current stable release %s. Expected %s, got %s.\n' \
    "$release_tag" "$expected" "$actual" >&2
  exit 1
fi

if ! grep -Fq 'Exiting.' "$output"; then
  printf '%s\n' 'Latest-stable Bash bootstrap did not reach the released tool interactive exit.' >&2
  exit 1
fi

printf 'Latest-stable Bash bootstrap E2E passed for %s.\n' "$release_tag"
