#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
base_temp="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
test_root="$(mktemp -d "$base_temp/isolated-dotnet-sdk-e2e-latest-bootstrap.XXXXXX")"
test_home="$test_root/home"
release_json="$test_root/latest-release.json"
checksums="$test_root/SHA256SUMS"
output="$test_root/bootstrap-output.txt"
curl_wrapper_dir="$test_root/curl-wrapper"
mkdir -p "$test_home" "$curl_wrapper_dir"

cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT

export HOME="$test_home"

repository='infoconex/isolated-dotnet-sdk'
latest_release_url="https://api.github.com/repos/$repository/releases/latest"
release_download_base_url="https://github.com/$repository/releases/download"

github_api_args=(
  -H 'Accept: application/vnd.github+json'
  -H 'X-GitHub-Api-Version: 2022-11-28'
)
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  github_api_args+=(-H "Authorization: Bearer $GITHUB_TOKEN")
fi

real_curl="$(command -v curl)"
cat > "$curl_wrapper_dir/curl" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail

real_curl="${LATEST_STABLE_E2E_REAL_CURL:?}"
max_attempts=3
attempt=1
status=0
url=''
destination=''
args=("$@")

for ((index = 0; index < ${#args[@]}; index++)); do
  case "${args[$index]}" in
    -o|--output)
      if ((index + 1 < ${#args[@]})); then
        destination="${args[$((index + 1))]}"
      fi
      ;;
    http://*|https://*)
      url="${args[$index]}"
      ;;
  esac
done

case "$url" in
  */releases/latest)
    stage='release metadata'
    ;;
  */SHA256SUMS)
    stage='release checksums'
    ;;
  https://raw.githubusercontent.com/*/isolated-dotnet-sdk.sh)
    stage='released Bash tool'
    ;;
  *)
    stage='network resource'
    ;;
esac

attempt_output="$(mktemp "${TMPDIR:-/tmp}/isolated-dotnet-sdk-e2e-curl.XXXXXX")"
cleanup_wrapper() {
  rm -f "$attempt_output"
}
trap cleanup_wrapper EXIT

while true; do
  : > "$attempt_output"
  if [[ -n "$destination" ]]; then
    rm -f "$destination"
  fi

  if "$real_curl" "${args[@]}" > "$attempt_output"; then
    cat "$attempt_output"
    exit 0
  else
    status=$?
  fi

  if [[ -n "$destination" ]]; then
    rm -f "$destination"
  fi

  if [[ "$status" -ne 56 ]]; then
    printf 'Latest-stable bootstrap fetch failed during %s (curl exit %d, attempt %d/%d).\n' \
      "$stage" "$status" "$attempt" "$max_attempts" >&2
    exit "$status"
  fi

  if [[ "$attempt" -ge "$max_attempts" ]]; then
    printf 'Latest-stable bootstrap fetch failed during %s after %d attempts (curl exit %d).\n' \
      "$stage" "$max_attempts" "$status" >&2
    exit "$status"
  fi

  printf 'Latest-stable bootstrap fetch retry: %s failed with curl exit %d (attempt %d/%d); retrying.\n' \
    "$stage" "$status" "$attempt" "$max_attempts" >&2
  attempt=$((attempt + 1))
  sleep 1
done
EOF
chmod +x "$curl_wrapper_dir/curl"
export LATEST_STABLE_E2E_REAL_CURL="$real_curl"
export PATH="$curl_wrapper_dir:$PATH"

curl -fsSL \
  "${github_api_args[@]}" \
  "$latest_release_url" \
  -o "$release_json"
release_tag="$(jq -er '
  select(.draft == false and .prerelease == false)
  | .tag_name
  | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))
' "$release_json")"

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

set +e
printf 'E\n' | bash "$repo_root/install.sh" > "$output" 2>&1
bootstrap_status=$?
set -e

# v0.2.0 predates the silent controlling-terminal probe. Keep its immutable release
# bytes under test while omitting that known macOS shell diagnostic from CI output.
if [[ "$release_tag" == 'v0.2.0' ]]; then
  sed '/\/dev\/tty: Device not configured$/d' "$output"
else
  cat "$output"
fi

if [[ "$bootstrap_status" -ne 0 ]]; then
  exit "$bootstrap_status"
fi

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
