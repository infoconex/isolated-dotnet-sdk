#!/usr/bin/env bats

load './sdk-payload-fixture.bash'

setup() { payload_test_setup; }
teardown() { payload_test_teardown; }

@test "promotion command failure cleans transaction state and reports no success" {
  export SDK_TEST_MV_EXIT=82
  run_payload_install

  [ "$status" -ne 0 ]
  [[ "$output" == *"Unable to promote isolated SDK $version into $install_dir with exit code 82."* ]]
  [[ "$output" != *"installation completed successfully"* ]]
  [ ! -e "$install_dir" ]
  ! compgen -G "$tool_root/.install-$version.*" >/dev/null
}

@test "cleanup failure after promotion fails the operation without false install success" {
  export SDK_TEST_RM_FAIL_PATTERN='.sdk-payload-'
  run_payload_install

  [ "$status" -ne 0 ]
  [ -x "$install_dir/dotnet" ]
  [[ "$output" == *"Unable to clean SDK payload archive:"* ]]
  [[ "$output" == *"installed, but transaction cleanup failed"* ]]
  [[ "$output" != *"installation completed successfully"* ]]
}
