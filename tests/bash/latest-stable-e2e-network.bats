#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  driver="$repo_root/tests/e2e/bash/latest-stable-bootstrap.sh"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-latest-e2e-network.XXXXXX")"
  fake_bin="$test_root/bin"
  request_log="$test_root/requests.log"
  sleep_log="$test_root/sleeps.log"
  execution_log="$test_root/executions.log"
  expected_hash='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
  mkdir -p "$fake_bin"
  : > "$request_log"
  : > "$sleep_log"

  cat > "$fake_bin/curl" <<'EOF'
#!/bin/bash
set -euo pipefail

out=''
url=''
write_out=''
while (($#)); do
  case "$1" in
    -o|--output)
      out="$2"
      shift 2
      ;;
    -w|--write-out)
      write_out="$2"
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

emit_http_code() {
  if [[ -n "$write_out" ]]; then
    printf '%s' "$1"
  fi
}

printf '%s\n' "$url" >> "$E2E_REQUEST_LOG"
request_count="$(grep -Fc "$url" "$E2E_REQUEST_LOG" || true)"

case "$url" in
  */releases/latest)
    case "${E2E_SCENARIO:-success}" in
      transient-release-receive)
        if [[ "$request_count" -eq 1 ]]; then
          emit_http_code '000'
          exit 56
        fi
        ;;
      transient-release-receive-http-200)
        if [[ "$request_count" -eq 1 ]]; then
          emit_http_code '200'
          exit 56
        fi
        ;;
      persistent-release-receive)
        emit_http_code '000'
        exit 56
        ;;
      http-release-failure)
        emit_http_code '403'
        exit 22
        ;;
      http-release-failure-exit-56)
        emit_http_code '403'
        exit 56
        ;;
    esac

    release_json='{"tag_name":"v1.0.0","draft":false,"prerelease":false}'
    if [[ -n "$out" ]]; then
      printf '%s\n' "$release_json" > "$out"
    else
      printf '%s\n' "$release_json"
    fi
    emit_http_code '200'
    ;;
  */SHA256SUMS)
    if [[ "${E2E_SCENARIO:-success}" == transient-checksum-receive && "$request_count" -eq 1 ]]; then
      emit_http_code '000'
      exit 56
    fi
    if [[ "${E2E_SCENARIO:-success}" == malformed-checksum ]]; then
      printf '%s\n' 'not-a-checksum  isolated-dotnet-sdk.sh' > "$out"
    else
      printf '%s  isolated-dotnet-sdk.sh\n' "$E2E_EXPECTED_HASH" > "$out"
    fi
    emit_http_code '200'
    ;;
  */isolated-dotnet-sdk.sh)
    case "${E2E_SCENARIO:-success}" in
      transient-bootstrap-tool-receive)
        if [[ "$request_count" -eq 1 ]]; then
          emit_http_code '000'
          exit 56
        fi
        ;;
      persistent-bootstrap-tool-receive)
        emit_http_code '000'
        exit 56
        ;;
    esac

    cat > "$out" <<'PAYLOAD'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' executed >> "$E2E_EXECUTION_LOG"
mkdir -p "$HOME/dotnet-sdks"
cat "$0" > "$HOME/dotnet-sdks/isolated-dotnet-sdk.sh"
printf '%s\n' 'Exiting.'
PAYLOAD
    emit_http_code '200'
    ;;
  *)
    emit_http_code '000'
    exit 23
    ;;
esac
EOF
  chmod +x "$fake_bin/curl"

  cat > "$fake_bin/sha256sum" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s  %s\n' "$E2E_EXPECTED_HASH" "${1:-}"
EOF
  chmod +x "$fake_bin/sha256sum"

  cat > "$fake_bin/sleep" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$E2E_SLEEP_LOG"
EOF
  chmod +x "$fake_bin/sleep"
}

teardown() {
  rm -rf "$test_root"
}

run_driver() {
  run env \
    PATH="$fake_bin:$PATH" \
    E2E_REQUEST_LOG="$request_log" \
    E2E_SLEEP_LOG="$sleep_log" \
    E2E_EXECUTION_LOG="$execution_log" \
    E2E_EXPECTED_HASH="$expected_hash" \
    E2E_SCENARIO="${E2E_SCENARIO:-success}" \
    /bin/bash "$driver"
}

request_count() {
  grep -Fc "$1" "$request_log" || true
}

@test "latest-stable E2E retries a transient release metadata receive failure" {
  E2E_SCENARIO='transient-release-receive'
  run_driver

  [ "$status" -eq 0 ]
  [ "$(request_count '/releases/latest')" -eq 3 ]
  [ "$(wc -l < "$sleep_log" | tr -d ' ')" -eq 1 ]
  [[ "$output" == *"release metadata"* ]]
  [[ "$output" == *"curl exit 56"* ]]
}

@test "latest-stable E2E retries a receive failure after a non-error HTTP response" {
  E2E_SCENARIO='transient-release-receive-http-200'
  run_driver

  [ "$status" -eq 0 ]
  [ "$(request_count '/releases/latest')" -eq 3 ]
  [ "$(wc -l < "$sleep_log" | tr -d ' ')" -eq 1 ]
  [[ "$output" == *"release metadata"* ]]
  [[ "$output" == *"curl exit 56"* ]]
}

@test "latest-stable E2E retries a transient checksum receive failure" {
  E2E_SCENARIO='transient-checksum-receive'
  run_driver

  [ "$status" -eq 0 ]
  [ "$(request_count '/SHA256SUMS')" -eq 3 ]
  [ "$(wc -l < "$sleep_log" | tr -d ' ')" -eq 1 ]
  [[ "$output" == *"release checksums"* ]]
  [[ "$output" == *"curl exit 56"* ]]
}

@test "latest-stable E2E retries a transient released-tool receive failure inside the bootstrap" {
  E2E_SCENARIO='transient-bootstrap-tool-receive'
  run_driver

  [ "$status" -eq 0 ]
  [ "$(request_count '/v1.0.0/isolated-dotnet-sdk.sh')" -eq 2 ]
  [ "$(wc -l < "$sleep_log" | tr -d ' ')" -eq 1 ]
  [[ "$output" == *"released Bash tool"* ]]
  [[ "$output" == *"curl exit 56"* ]]
  [ -e "$execution_log" ]
}

@test "latest-stable E2E stops after the bounded receive retry attempts" {
  E2E_SCENARIO='persistent-release-receive'
  run_driver

  [ "$status" -eq 56 ]
  [ "$(request_count '/releases/latest')" -eq 3 ]
  [ "$(wc -l < "$sleep_log" | tr -d ' ')" -eq 2 ]
  [[ "$output" == *"release metadata"* ]]
  [[ "$output" == *"after 3 attempts"* ]]
  [ ! -e "$execution_log" ]
}

@test "latest-stable E2E surfaces persistent released-tool failure inside the bootstrap" {
  E2E_SCENARIO='persistent-bootstrap-tool-receive'
  run_driver

  [ "$status" -eq 56 ]
  [ "$(request_count '/v1.0.0/isolated-dotnet-sdk.sh')" -eq 3 ]
  [ "$(wc -l < "$sleep_log" | tr -d ' ')" -eq 2 ]
  [[ "$output" == *"released Bash tool"* ]]
  [[ "$output" == *"after 3 attempts"* ]]
  [ ! -e "$execution_log" ]
}

@test "latest-stable E2E contextualizes HTTP failure without retrying it" {
  E2E_SCENARIO='http-release-failure'
  run_driver

  [ "$status" -eq 22 ]
  [ "$(request_count '/releases/latest')" -eq 1 ]
  [ ! -s "$sleep_log" ]
  [[ "$output" == *"release metadata"* ]]
  [[ "$output" == *"curl exit 22"* ]]
  [ ! -e "$execution_log" ]
}

@test "latest-stable E2E does not retry an HTTP failure surfaced as curl exit 56" {
  E2E_SCENARIO='http-release-failure-exit-56'
  run_driver

  [ "$status" -eq 56 ]
  [ "$(request_count '/releases/latest')" -eq 1 ]
  [ ! -s "$sleep_log" ]
  [[ "$output" == *"release metadata"* ]]
  [[ "$output" == *"HTTP 403"* ]]
  [[ "$output" == *"curl exit 56"* ]]
  [ ! -e "$execution_log" ]
}

@test "latest-stable E2E still fails closed on malformed checksum data" {
  E2E_SCENARIO='malformed-checksum'
  run_driver

  [ "$status" -ne 0 ]
  [ "$(request_count '/SHA256SUMS')" -eq 1 ]
  [ ! -s "$sleep_log" ]
  [ ! -e "$execution_log" ]
}
