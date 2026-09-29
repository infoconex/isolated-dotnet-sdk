#!/usr/bin/env bats

load './sdk-payload-fixture.bash'

setup() { payload_test_setup; }
teardown() { payload_test_teardown; }

@test "cleanup failure remains observable without masking extraction failure" {
  export SDK_TEST_TAR_EXIT=73
  export SDK_TEST_RM_FAIL_PATTERN='.sdk-payload-'
  run_payload_install

  [ "$status" -ne 0 ]
  [[ "$output" == *"Unable to extract the verified .NET SDK $version payload with exit code 73."* ]]
  [[ "$output" == *"Unable to clean SDK payload archive:"* ]]
  [ ! -e "$install_dir" ]
}

@test "valid existing exact SDK keeps already-installed behavior and skips acquisition" {
  mkdir -p "$install_dir"
  cat > "$install_dir/dotnet" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == '--list-sdks' ]]; then
  printf '%s\n' '$version [/existing/sdk]'
fi
exit 0
EOF
  chmod +x "$install_dir/dotnet"

  run_payload_install

  [ "$status" -eq 0 ]
  [[ "$output" == *"Isolated SDK $version is already installed."* ]]
  [ ! -e "$test_home/curl.log" ]
}
