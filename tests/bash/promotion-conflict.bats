#!/usr/bin/env bats

load './sdk-payload-fixture.bash'

setup() { payload_test_setup; }
teardown() { payload_test_teardown; }

@test "destination appearing before promotion is preserved and staging is cleaned" {
  export SDK_TEST_CREATE_DEST_ON_VERIFY=1
  run_payload_install

  [ "$status" -ne 0 ]
  [[ "$output" == *"destination already exists and cannot be replaced"* ]]
  [ "$(cat "$install_dir/external.txt")" = external ]
  ! compgen -G "$tool_root/.install-$version.*" >/dev/null
}
