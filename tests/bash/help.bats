#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-help-tests.XXXXXX")"
  test_home="$test_root/home"
  tool_root="$test_home/dotnet-sdks"
  tool_path="$tool_root/isolated-dotnet-sdk.sh"

  mkdir -p "$tool_root"
  cp "$repo_root/isolated-dotnet-sdk.sh" "$tool_path"
  chmod +x "$tool_path"
}

teardown() {
  rm -rf "$test_root"
}

@test "help describes the supported Bash operational contract" {
  run env HOME="$test_home" "$tool_path" --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"Linux and macOS with Bash"* ]]
  [[ "$output" == *"not added to PATH"* ]]
  [[ "$output" == *"verify <version>"* ]]
  [[ "$output" == *"Read-only health check for one exact installed isolated SDK."* ]]
  [[ "$output" == *"does not choose a missing action or version"* ]]
  [[ "$output" == *"Required interactive input that is unavailable is an operational failure"* ]]
  [[ "$output" == *"Explicit cancellation is a successful no-change result"* ]]
  [[ "$output" == *"Operational failures return a nonzero exit status"* ]]
  [[ "$output" == *"Exact-version installs bypass release-metadata discovery"* ]]
}
