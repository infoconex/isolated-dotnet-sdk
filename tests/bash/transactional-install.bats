#!/usr/bin/env bats

load './sdk-payload-fixture.bash'

setup() { payload_test_setup; }
teardown() { payload_test_teardown; }

@test "pre-existing non-valid destination fails before acquisition and is preserved" {
  mkdir -p "$install_dir"
  printf '%s\n' keep > "$install_dir/marker.txt"

  run_payload_install

  [ "$status" -ne 0 ]
  [[ "$output" == *"destination already exists and cannot be replaced"* ]]
  [ "$(cat "$install_dir/marker.txt")" = keep ]
  [ ! -e "$test_home/curl.log" ]
}

@test "extraction failure uses staging and cleans the failed attempt" {
  export SDK_TEST_TAR_EXIT=73
  run_payload_install

  [ "$status" -ne 0 ]
  [ ! -e "$install_dir" ]
  ! compgen -G "$tool_root/.install-$version.*" >/dev/null
  ! compgen -G "$tool_root/.sdk-payload-$version.*" >/dev/null
}

@test "missing staged host fails before promotion and cleans staging" {
  build_payload_without_dotnet
  run_payload_install

  [ "$status" -ne 0 ]
  [[ "$output" == *"isolated dotnet executable was not found"* ]]
  [ ! -e "$install_dir" ]
  ! compgen -G "$tool_root/.install-$version.*" >/dev/null
}

@test "staged host failure blocks promotion and cleans staging" {
  export SDK_TEST_DOTNET_EXIT=74
  run_payload_install

  [ "$status" -ne 0 ]
  [[ "$output" == *"Unable to verify isolated SDK $version with exit code 74."* ]]
  [ ! -e "$install_dir" ]
  ! compgen -G "$tool_root/.install-$version.*" >/dev/null
}

@test "staged inventory missing the exact version blocks promotion" {
  export SDK_TEST_DOTNET_VERSION=99.0.101
  run_payload_install

  [ "$status" -ne 0 ]
  [[ "$output" == *"SDK $version was not found after installation."* ]]
  [ ! -e "$install_dir" ]
}

@test "verified staging is promoted to the final destination" {
  run_payload_install

  [ "$status" -eq 0 ]
  [ -x "$install_dir/dotnet" ]
  [[ "$output" == *"Isolated SDK installation completed successfully."* ]]
  ! compgen -G "$tool_root/.install-$version.*" >/dev/null
  ! compgen -G "$tool_root/.sdk-payload-$version.*" >/dev/null
}

@test "retry after failed clean-start installation needs no manual cleanup" {
  export SDK_TEST_TAR_EXIT=73
  run_payload_install
  [ "$status" -ne 0 ]
  [ ! -e "$install_dir" ]

  unset SDK_TEST_TAR_EXIT
  run_payload_install
  [ "$status" -eq 0 ]
  [ -x "$install_dir/dotnet" ]
}
