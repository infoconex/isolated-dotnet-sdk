#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
config="$repo_root/.config/e2e.json"
channel_version="$(jq -er '.channelVersion | select(type == "string" and length > 0)' "$config")"
sdk_version="$(jq -er '.sdkVersion | select(type == "string" and length > 0)' "$config")"
audit_release_type="$(jq -er '.audit.releaseType | select(type == "string" and length > 0)' "$config")"
audit_release_date="$(jq -er '.audit.releaseDate | select(type == "string" and length > 0)' "$config")"
audit_end_of_support="$(jq -er '.audit.endOfSupport | select(type == "string" and length > 0)' "$config")"
base_temp="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
test_root="$(mktemp -d "$base_temp/isolated-dotnet-sdk-e2e-interactive.XXXXXX")"
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

# Discover the live channel position from the tool's own displayed picker instead
# of assuming that a particular .NET channel always has the same numeric ordinal.
echo "E2E interactive: discovering displayed selection for .NET $channel_version"
discovery_output="$(printf 'q\n' | bash "$source_tool" install 2>&1)"
printf '%s\n' "$discovery_output"

escaped_channel="${channel_version//./\\.}"
channel_line="$(printf '%s\n' "$discovery_output" |
  grep -E "^[[:space:]]+[0-9]+\.[[:space:]]+\.NET[[:space:]]+$escaped_channel([[:space:]]|$)" |
  head -n 1 || true)"

if [[ -z "$channel_line" ]]; then
  printf 'Unable to find .NET %s in the displayed live channel picker.\n' "$channel_version" >&2
  exit 1
fi

channel_selection="$(printf '%s\n' "$channel_line" |
  sed -E 's/^[[:space:]]*([0-9]+)\..*/\1/')"

if [[ ! "$channel_selection" =~ ^[0-9]+$ ]]; then
  printf 'Unable to derive a numeric selection from channel line: %s\n' "$channel_line" >&2
  exit 1
fi

test -f "$saved_tool"

# Main -> Install -> channel -> Back -> same discovered channel -> manual exact
# version -> Main -> List -> Main -> Audit -> Main -> Verify the only job-local
# SDK -> Main -> Remove the same SDK -> Main -> Exit.
interactive_input="$(printf 'i\n%s\nB\n%s\nM\n%s\nl\na\nv\n1\nr\n1\ne\n' \
  "$channel_selection" "$channel_selection" "$sdk_version")"

echo "E2E interactive: running persistent session for .NET SDK $sdk_version"
set +e
interactive_output="$(printf '%s\n' "$interactive_input" | bash "$saved_tool" --yes 2>&1)"
interactive_status=$?
set -e
printf '%s\n' "$interactive_output"
if [[ "$interactive_status" -ne 0 ]]; then
  printf 'Persistent interactive lifecycle failed with exit code %s.\n' "$interactive_status" >&2
  exit "$interactive_status"
fi

main_prompt_count="$(printf '%s\n' "$interactive_output" |
  grep -c 'What would you like to do?' || true)"
if [[ "$main_prompt_count" -ne 6 ]]; then
  printf 'Expected 6 Main prompts but observed %s.\n' "$main_prompt_count" >&2
  exit 1
fi

identity_count="$(printf '%s\n' "$interactive_output" |
  grep -cFx 'Isolated .NET SDK development (main)' || true)"
if [[ "$identity_count" -ne "$main_prompt_count" ]]; then
  printf 'Expected one development identity heading per Main prompt; observed %s identities for %s prompts.\n' \
    "$identity_count" "$main_prompt_count" >&2
  exit 1
fi

required_fragments=(
  "Back to .NET channels"
  "Isolated SDK installation completed successfully."
  "Isolated SDKs:"
  "System SDKs:"
  ".NET SDK audit"
  "$sdk_version  $audit_release_type"
  "Release date: $audit_release_date"
  "End of support: $audit_end_of_support"
  "Select an isolated SDK to verify:"
  "Isolated SDK $sdk_version is healthy."
  "$sdk_version"
  "was removed."
  "Exiting."
)

for fragment in "${required_fragments[@]}"; do
  if ! grep -Fq "$fragment" <<<"$interactive_output"; then
    printf 'Interactive output did not contain required text: %s\n' "$fragment" >&2
    exit 1
  fi
done

if [[ -e "$sdk_root" ]]; then
  printf 'SDK directory still exists after interactive removal: %s\n' "$sdk_root" >&2
  exit 1
fi

echo "E2E interactive lifecycle passed for .NET SDK $sdk_version."
