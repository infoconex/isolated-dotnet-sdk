#!/usr/bin/env bash
set -euo pipefail

REPOSITORY="infoconex/isolated-dotnet-sdk"
LATEST_RELEASE_URL="https://api.github.com/repos/$REPOSITORY/releases/latest"
RAW_BASE_URL="https://raw.githubusercontent.com/$REPOSITORY"
RELEASE_DOWNLOAD_BASE_URL="https://github.com/$REPOSITORY/releases/download"
TOOL_NAME="isolated-dotnet-sdk.sh"

release_json="$(curl -fsSL \
  -H 'Accept: application/vnd.github+json' \
  -H 'X-GitHub-Api-Version: 2022-11-28' \
  "$LATEST_RELEASE_URL")"

if ! grep -Eq '"draft"[[:space:]]*:[[:space:]]*false' <<< "$release_json" || \
   ! grep -Eq '"prerelease"[[:space:]]*:[[:space:]]*false' <<< "$release_json"; then
  printf '%s\n' 'Latest release metadata is missing the required stable-release state.' >&2
  exit 1
fi

release_tag="$(printf '%s\n' "$release_json" | sed -nE 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p')"
if [[ ! "$release_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf '%s\n' 'Latest release metadata does not contain one valid stable release tag.' >&2
  exit 1
fi

tool_temp="$(mktemp "${TMPDIR:-/tmp}/isolated-dotnet-sdk.XXXXXX.sh")"
checksums_temp="$(mktemp "${TMPDIR:-/tmp}/isolated-dotnet-sdk.XXXXXX.SHA256SUMS")"
trap 'rm -f "$tool_temp" "$checksums_temp"' EXIT

curl -fsSL "$RAW_BASE_URL/$release_tag/$TOOL_NAME" -o "$tool_temp"
curl -fsSL "$RELEASE_DOWNLOAD_BASE_URL/$release_tag/SHA256SUMS" -o "$checksums_temp"

expected="$(awk -v name="$TOOL_NAME" '$2 == name && $1 ~ /^[0-9a-fA-F]{64}$/ { print tolower($1) }' "$checksums_temp")"
if [[ ! "$expected" =~ ^[0-9a-f]{64}$ ]]; then
  printf 'SHA256SUMS does not contain exactly one valid %s entry.\n' "$TOOL_NAME" >&2
  exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$tool_temp" | awk '{print tolower($1)}')"
elif command -v shasum >/dev/null 2>&1; then
  actual="$(shasum -a 256 "$tool_temp" | awk '{print tolower($1)}')"
else
  printf '%s\n' 'SHA-256 verification requires sha256sum or shasum.' >&2
  exit 1
fi

if [[ "$actual" != "$expected" ]]; then
  printf 'Checksum verification failed for %s. Expected %s, got %s.\n' \
    "$TOOL_NAME" "$expected" "$actual" >&2
  exit 1
fi

chmod +x "$tool_temp"
set +e
"$tool_temp"
tool_status=$?
set -e
exit "$tool_status"
