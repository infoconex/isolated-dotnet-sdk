#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  bootstrap="$repo_root/install.sh"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-latest-bootstrap.XXXXXX")"
  fake_bin="$test_root/bin"
  request_log="$test_root/requests.log"
  execution_log="$test_root/executions.log"
  expected_hash='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
  mkdir -p "$fake_bin"

  for utility in bash awk grep sed mktemp chmod rm cat; do
    ln -s "$(command -v "$utility")" "$fake_bin/$utility"
  done

  cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

out=''
url=''
while (($#)); do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    -H)
      shift 2
      ;;
    -f|-s|-S|-L|-fsSL)
      shift
      ;;
    http://*|https://*)
      url="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

printf '%s\n' "$url" >> "$BOOTSTRAP_REQUEST_LOG"

case "$url" in
  */releases/latest)
    case "${BOOTSTRAP_SCENARIO:-success}" in
      discovery-failure)
        exit 22
        ;;
      malformed-release)
        printf '%s\n' '{"draft":false,"prerelease":false}'
        ;;
      prerelease)
        printf '%s\n' '{"tag_name":"v9.9.9","draft":false,"prerelease":true}'
        ;;
      *)
        printf '{"tag_name":"%s","draft":false,"prerelease":false}\n' "$BOOTSTRAP_LATEST_TAG"
        ;;
    esac
    ;;
  */SHA256SUMS)
    case "${BOOTSTRAP_SCENARIO:-success}" in
      missing-checksum)
        exit 22
        ;;
      missing-platform-entry)
        printf '%s  isolated-dotnet-sdk.ps1\n' "$BOOTSTRAP_EXPECTED_HASH" > "$out"
        ;;
      malformed-checksum)
        printf '%s\n' 'not-a-checksum  isolated-dotnet-sdk.sh' > "$out"
        ;;
      duplicate-checksum)
        printf '%s  isolated-dotnet-sdk.sh\n%s  isolated-dotnet-sdk.sh\n' \
          "$BOOTSTRAP_EXPECTED_HASH" "$BOOTSTRAP_EXPECTED_HASH" > "$out"
        ;;
      *)
        printf '%s  isolated-dotnet-sdk.sh\n' "$BOOTSTRAP_EXPECTED_HASH" > "$out"
        ;;
    esac
    ;;
  */isolated-dotnet-sdk.sh)
    cat > "$out" <<'PAYLOAD'
#!/usr/bin/env bash
printf '%s\n' executed >> "$BOOTSTRAP_EXECUTION_LOG"
exit "${BOOTSTRAP_TOOL_EXIT:-0}"
PAYLOAD
    ;;
  *)
    exit 23
    ;;
esac
EOF
  chmod +x "$fake_bin/curl"

  cat > "$fake_bin/sha256sum" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s  %s\n' "${BOOTSTRAP_ACTUAL_HASH:-$BOOTSTRAP_EXPECTED_HASH}" "${1:-}"
EOF
  chmod +x "$fake_bin/sha256sum"

  cat > "$fake_bin/shasum" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
last=''
for argument in "$@"; do
  last="$argument"
done
printf '%s  %s\n' "${BOOTSTRAP_ACTUAL_HASH:-$BOOTSTRAP_EXPECTED_HASH}" "$last"
EOF
  chmod +x "$fake_bin/shasum"
}

teardown() {
  rm -rf "$test_root"
}

run_bootstrap() {
  run env \
    PATH="$fake_bin" \
    BOOTSTRAP_REQUEST_LOG="$request_log" \
    BOOTSTRAP_EXECUTION_LOG="$execution_log" \
    BOOTSTRAP_EXPECTED_HASH="$expected_hash" \
    BOOTSTRAP_LATEST_TAG="${BOOTSTRAP_LATEST_TAG:-v1.0.0}" \
    BOOTSTRAP_SCENARIO="${BOOTSTRAP_SCENARIO:-success}" \
    BOOTSTRAP_ACTUAL_HASH="${BOOTSTRAP_ACTUAL_HASH:-$expected_hash}" \
    BOOTSTRAP_TOOL_EXIT="${BOOTSTRAP_TOOL_EXIT:-0}" \
    "$bootstrap"
}

@test "latest stable bootstrap verifies and executes the resolved tagged Bash tool" {
  run_bootstrap

  [ "$status" -eq 0 ]
  [ "$(wc -l < "$execution_log" | tr -d ' ')" -eq 1 ]
  grep -Fq '/v1.0.0/isolated-dotnet-sdk.sh' "$request_log"
  ! grep -Fq '/main/isolated-dotnet-sdk.sh' "$request_log"
}

@test "latest stable movement changes tagged acquisition without bootstrap changes" {
  BOOTSTRAP_LATEST_TAG='v1.0.0'
  run_bootstrap
  [ "$status" -eq 0 ]

  BOOTSTRAP_LATEST_TAG='v2.0.0'
  run_bootstrap

  [ "$status" -eq 0 ]
  grep -Fq '/v1.0.0/isolated-dotnet-sdk.sh' "$request_log"
  grep -Fq '/v2.0.0/isolated-dotnet-sdk.sh' "$request_log"
}

@test "release discovery failure stops before released tool execution" {
  BOOTSTRAP_SCENARIO='discovery-failure'
  run_bootstrap

  [ "$status" -ne 0 ]
  [ ! -e "$execution_log" ]
}

@test "malformed or prerelease latest metadata fails closed" {
  BOOTSTRAP_SCENARIO='malformed-release'
  run_bootstrap
  [ "$status" -ne 0 ]
  [ ! -e "$execution_log" ]

  BOOTSTRAP_SCENARIO='prerelease'
  run_bootstrap
  [ "$status" -ne 0 ]
  [ ! -e "$execution_log" ]
}

@test "missing malformed and duplicate checksum data never executes the released tool" {
  for scenario in missing-checksum missing-platform-entry malformed-checksum duplicate-checksum; do
    rm -f "$execution_log"
    BOOTSTRAP_SCENARIO="$scenario"
    run_bootstrap
    [ "$status" -ne 0 ]
    [ ! -e "$execution_log" ]
  done
}

@test "checksum mismatch never executes the released tool" {
  BOOTSTRAP_ACTUAL_HASH='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
  run_bootstrap

  [ "$status" -ne 0 ]
  [ ! -e "$execution_log" ]
}

@test "Bash bootstrap falls back to shasum when sha256sum is unavailable" {
  rm -f "$fake_bin/sha256sum"
  run_bootstrap

  [ "$status" -eq 0 ]
  [ -e "$execution_log" ]
}

@test "Bash bootstrap fails closed when no SHA-256 utility is available" {
  rm -f "$fake_bin/sha256sum" "$fake_bin/shasum"
  run_bootstrap

  [ "$status" -ne 0 ]
  [ ! -e "$execution_log" ]
}

@test "released tool nonzero status is preserved" {
  BOOTSTRAP_TOOL_EXIT=7
  run_bootstrap

  [ "$status" -eq 7 ]
  [ -e "$execution_log" ]
}
