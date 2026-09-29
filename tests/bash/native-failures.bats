#!/usr/bin/env bats

load './sdk-payload-fixture.bash'

setup() { payload_test_setup; }
teardown() { payload_test_teardown; }

@test "release metadata download failure uses operation-scoped temporary state" {
  export SDK_TEST_METADATA_CURL_EXIT=77
  run_payload_install

  [ "$status" -ne 0 ]
  [[ "$output" == *"Unable to load Microsoft release metadata for SDK $version"* ]]
  [ ! -e "$install_dir" ]
  ! compgen -G "$tool_root/.release-metadata-$version.*" >/dev/null
  ! compgen -G "$tool_root/.sdk-payload-$version.*" >/dev/null
}

@test "existing isolated host failure stops installation before acquisition" {
  mkdir -p "$install_dir"
  cat > "$install_dir/dotnet" <<'EOF'
#!/usr/bin/env bash
exit 72
EOF
  chmod +x "$install_dir/dotnet"

  run_payload_install

  [ "$status" -ne 0 ]
  [[ "$output" == *"Unable to inspect existing isolated SDK $version with exit code 72."* ]]
  [ ! -e "$test_home/curl.log" ]
}

@test "payload extraction failure stops before verification and success" {
  export SDK_TEST_TAR_EXIT=73
  run_payload_install

  [ "$status" -ne 0 ]
  [[ "$output" == *"Unable to extract the verified .NET SDK $version payload with exit code 73."* ]]
  [[ "$output" != *"Verifying the isolated SDK"* ]]
  [[ "$output" != *"installation completed successfully"* ]]
  [ ! -e "$install_dir" ]
  ! compgen -G "$tool_root/.install-$version.*" >/dev/null
}

@test "post-extraction host failure is reported as verification failure" {
  export SDK_TEST_DOTNET_EXIT=74
  run_payload_install

  [ "$status" -ne 0 ]
  [[ "$output" == *"Unable to verify isolated SDK $version with exit code 74."* ]]
  [ ! -e "$install_dir" ]
  ! compgen -G "$tool_root/.install-$version.*" >/dev/null
}
