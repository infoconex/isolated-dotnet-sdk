#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
config="$repo_root/.config/e2e.json"
sdk_version="$(jq -er '.sdkVersion | select(type == "string" and length > 0)' "$config")"
base_temp="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
test_root="$(mktemp -d "$base_temp/isolated-dotnet-sdk-e2e-direct.XXXXXX")"
test_home="$test_root/home"
mkdir -p "$test_home"

cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT

export HOME="$test_home"
source_tool="$repo_root/isolated-dotnet-sdk.sh"
tool_root="$HOME/dotnet-sdks"
saved_tool="$tool_root/isolated-dotnet-sdk.sh"
sdk_root="$tool_root/$sdk_version"
dotnet_host="$sdk_root/dotnet"

echo "E2E direct: installing .NET SDK $sdk_version into $sdk_root"
bash "$source_tool" install "$sdk_version" --yes

test -f "$saved_tool"
test -x "$dotnet_host"

actual_version="$("$dotnet_host" --version)"
if [[ "$actual_version" != "$sdk_version" ]]; then
  printf 'Expected isolated SDK version %s but dotnet reported %s.\n' \
    "$sdk_version" "$actual_version" >&2
  exit 1
fi

list_output="$(bash "$saved_tool" list)"
printf '%s\n' "$list_output"
if ! grep -Fq "$sdk_version" <<<"$list_output"; then
  printf 'List output did not contain installed SDK %s.\n' "$sdk_version" >&2
  exit 1
fi

echo "E2E direct: removing .NET SDK $sdk_version"
bash "$saved_tool" remove "$sdk_version" --yes

if [[ -e "$sdk_root" ]]; then
  printf 'SDK directory still exists after removal: %s\n' "$sdk_root" >&2
  exit 1
fi

echo "E2E direct lifecycle passed for .NET SDK $sdk_version."
