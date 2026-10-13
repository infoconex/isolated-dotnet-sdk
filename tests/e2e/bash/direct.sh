#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
config="$repo_root/.config/e2e.json"
sdk_version="$(jq -er '.sdkVersion | select(type == "string" and length > 0)' "$config")"
audit_release_type="$(jq -er '.audit.releaseType | select(type == "string" and length > 0)' "$config")"
audit_release_date="$(jq -er '.audit.releaseDate | select(type == "string" and length > 0)' "$config")"
audit_end_of_support="$(jq -er '.audit.endOfSupport | select(type == "string" and length > 0)' "$config")"
base_temp="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
test_root="$(mktemp -d "$base_temp/isolated-dotnet-sdk-e2e-direct.XXXXXX")"
test_home="$test_root/home"
mkdir -p "$test_home"

cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT

export HOME="$test_home"
export DOTNET_CLI_HOME="$test_home/.dotnet-cli"
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
mkdir -p "$DOTNET_CLI_HOME"

source_tool="$repo_root/isolated-dotnet-sdk.sh"
tool_root="$HOME/dotnet-sdks"
saved_tool="$tool_root/isolated-dotnet-sdk.sh"
sdk_root="$tool_root/$sdk_version"
dotnet_host="$sdk_root/dotnet"

version_output="$(bash "$source_tool" --version)"
if [[ "$version_output" != 'isolated-dotnet-sdk development (main)' ]]; then
  printf 'Expected development tool identity but received: %s\n' "$version_output" >&2
  exit 1
fi
if [[ -e "$tool_root" ]]; then
  printf 'Tool version query unexpectedly created SDK state at %s.\n' "$tool_root" >&2
  exit 1
fi

echo "E2E direct: installing .NET SDK $sdk_version into $sdk_root"
bash "$source_tool" install "$sdk_version" --yes

test -f "$saved_tool"
test -x "$dotnet_host"

saved_version_output="$(bash "$saved_tool" --version)"
if [[ "$saved_version_output" != 'isolated-dotnet-sdk development (main)' ]]; then
  printf 'Expected saved development tool identity but received: %s\n' "$saved_version_output" >&2
  exit 1
fi

actual_version="$("$dotnet_host" --version)"
if [[ "$actual_version" != "$sdk_version" ]]; then
  printf 'Expected isolated SDK version %s but dotnet reported %s.\n' \
    "$sdk_version" "$actual_version" >&2
  exit 1
fi

verify_output="$(bash "$saved_tool" verify "$sdk_version")"
printf '%s\n' "$verify_output"
for check in 'Installation directory' '.NET host' 'SDK inventory' 'SDK resolution'; do
  if ! grep -Eq "^[[:space:]]+$check[[:space:]]+OK[[:space:]]" <<<"$verify_output"; then
    printf 'Verify did not report passing local check: %s\n' "$check" >&2
    exit 1
  fi
done
if ! grep -Fq "$sdk_version from $sdk_root/sdk" <<<"$verify_output"; then
  printf 'Verify did not prove exact SDK version and isolated origin.\n' >&2
  exit 1
fi
if ! grep -Fq "Release: $audit_release_date" <<<"$verify_output"; then
  printf 'Verify and Audit release-date classification differed.\n' >&2
  exit 1
fi
if ! grep -Fq "EOS: $audit_end_of_support" <<<"$verify_output"; then
  printf 'Verify and Audit end-of-support classification differed.\n' >&2
  exit 1
fi
if grep -q $'\033' <<<"$verify_output"; then
  printf 'Captured Verify output unexpectedly contained ANSI escape sequences.\n' >&2
  exit 1
fi

if ! grep -Fq "Isolated SDK $sdk_version verified successfully." <<<"$verify_output"; then
  printf 'Verify output did not report SDK %s verified successfully.\n' "$sdk_version" >&2
  exit 1
fi

list_output="$(bash "$saved_tool" list)"
printf '%s\n' "$list_output"
if ! grep -Fq "$sdk_version" <<<"$list_output"; then
  printf 'List output did not contain installed SDK %s.\n' "$sdk_version" >&2
  exit 1
fi

audit_output="$(bash "$saved_tool" audit)"
printf '%s\n' "$audit_output"
if ! grep -Fq '.NET SDK audit' <<<"$audit_output"; then
  printf 'Audit output did not contain the Audit heading.\n' >&2
  exit 1
fi
if ! grep -Fq "$sdk_version  $audit_release_type" <<<"$audit_output"; then
  printf 'Audit output did not report SDK %s as %s.\n' "$sdk_version" "$audit_release_type" >&2
  exit 1
fi
if ! grep -Fq "Release: $audit_release_date" <<<"$audit_output"; then
  printf 'Audit output did not report SDK %s release date %s.\n' "$sdk_version" "$audit_release_date" >&2
  exit 1
fi
if ! grep -Fq "EOS: $audit_end_of_support" <<<"$audit_output"; then
  printf 'Audit output did not report SDK %s end of support %s.\n' "$sdk_version" "$audit_end_of_support" >&2
  exit 1
fi
if grep -q $'\033' <<<"$audit_output"; then
  printf 'Captured Audit output unexpectedly contained ANSI escape sequences.\n' >&2
  exit 1
fi

echo "E2E direct: removing .NET SDK $sdk_version"
bash "$saved_tool" remove "$sdk_version" --yes

if [[ -e "$sdk_root" ]]; then
  printf 'SDK directory still exists after removal: %s\n' "$sdk_root" >&2
  exit 1
fi

echo "E2E direct lifecycle passed for .NET SDK $sdk_version."
