#!/usr/bin/env bats

load './sdk-payload-fixture.bash'

setup() {
  payload_test_setup
  version='1.1.14'
  rid='osx-x64'
  install_dir="$tool_root/$version"
  artifact_url="https://builds.dotnet.microsoft.com/dotnet/Sdk/$version/dotnet-dev-$rid.$version.tar.gz"
  export SDK_TEST_DOTNET_VERSION="$version"
  cat > "$fake_bin/uname" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  -s) printf '%s\n' Darwin ;;
  -m) printf '%s\n' x86_64 ;;
esac
EOF
  chmod +x "$fake_bin/uname"
  cat > "$fixture_root/dotnet" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  --list-sdks)
    printf '%s\n' 'Unknown option: --list-sdks' >&2
    exit 1
    ;;
  --version)
    if [[ -n "${SDK_TEST_LEGACY_CMD_FAILURE:-}" ]]; then exit 74; fi
    printf '%s\n' "${SDK_TEST_DOTNET_VERSION:-1.1.14}"
    ;;
  --info)
    if [[ -n "${SDK_TEST_LEGACY_CMD_FAILURE:-}" ]]; then exit 74; fi
    base_path="${SDK_TEST_FAKE_BASE_PATH:-$(cd "$(dirname "$0")" && pwd -P)/sdk/${SDK_TEST_DOTNET_VERSION:-1.1.14}}"
    printf '.NET Command Line Tools (%s)\n' "${SDK_TEST_DOTNET_VERSION:-1.1.14}"
    printf 'Product Information:\n Version: %s\n' "${SDK_TEST_DOTNET_VERSION:-1.1.14}"
    printf 'Runtime Environment:\n Base Path: %s\n' "$base_path"
    ;;
  *) exit 73 ;;
esac
EOF
  chmod +x "$fixture_root/dotnet"
  mkdir -p "$fixture_root/sdk/$version"
  /usr/bin/tar -czf "$payload" -C "$fixture_root" dotnet sdk
  if command -v sha512sum >/dev/null 2>&1; then
    payload_hash="$(sha512sum "$payload" | awk '{print $1}')"
  else
    payload_hash="$(shasum -a 512 "$payload" | awk '{print $1}')"
  fi
  write_legacy_metadata "$payload_hash"
}
teardown() { payload_test_teardown; }

write_legacy_metadata() {
  local hash="$1"
  local artifact_name="dotnet-dev-$rid.tar.gz"
  if [[ "$version" == 2.* ]]; then
    artifact_name="dotnet-sdk-$rid.tar.gz"
  fi
  cat > "$metadata" <<EOF
{
  "releases": [
    {
      "runtime": {
        "version": "1.1.14",
        "files": [
          {
            "rid": "osx-x64",
            "url": "https://builds.dotnet.microsoft.com/dotnet/Runtime/1.1.14/dotnet-osx-x64.tar.gz",
            "hash": "$hash"
          }
        ]
      },
      "sdk": {
        "version": "$version",
        "files": [
          {
            "name": "$artifact_name",
            "rid": "$rid",
            "url": "$artifact_url",
            "hash": "$hash"
          }
        ]
      }
    }
  ]
}
EOF
}

@test "SDK 1.1.14 macOS tarball is verified and transactionally promoted" {
  run_payload_install
  [ "$status" -eq 0 ]
  [ -x "$install_dir/dotnet" ]
  [[ "$output" == *"Isolated SDK installation completed successfully."* ]]
  grep -Fq "$artifact_url" "$test_home/curl.log"
  [ -d "$install_dir/sdk/$version" ]
  ! compgen -G "$tool_root/.sdk-host-verify-$version.*" >/dev/null
  ! compgen -G "$tool_root/.install-$version.*" >/dev/null
}

prepare_legacy_sha256_payload() {
  version='1.0.4'
  install_dir="$tool_root/$version"
  artifact_url="https://builds.dotnet.microsoft.com/dotnet/Sdk/$version/dotnet-dev-$rid.$version.tar.gz"
  export SDK_TEST_DOTNET_VERSION="$version"
  mkdir -p "$fixture_root/sdk/$version"
  /usr/bin/tar -czf "$payload" -C "$fixture_root" dotnet sdk
  if command -v sha256sum >/dev/null 2>&1; then
    payload_hash256="$(sha256sum "$payload" | awk '{print $1}')"
  else
    payload_hash256="$(shasum -a 256 "$payload" | awk '{print $1}')"
  fi
  write_legacy_metadata "$payload_hash256"
}

@test "SDK 1.0.4 with Microsoft SHA-256 is verified and transactionally promoted" {
  prepare_legacy_sha256_payload
  run_payload_install
  [ "$status" -eq 0 ]
  [ -x "$install_dir/dotnet" ]
  [ -d "$install_dir/sdk/$version" ]
  [[ "$output" == *"Isolated SDK installation completed successfully."* ]]
  grep -Fq "$artifact_url" "$test_home/curl.log"
  ! compgen -G "$tool_root/.sdk-host-verify-$version.*" >/dev/null
  ! compgen -G "$tool_root/.install-$version.*" >/dev/null
}

@test "SDK 1.0.4 incorrect SHA-256 fails before extraction and cleans download" {
  prepare_legacy_sha256_payload
  write_legacy_metadata "$(printf '%064d' 0)"
  run_payload_install
  [ "$status" -ne 0 ]
  [[ "$output" == *"Integrity verification failed"* ]]
  [ ! -e "$install_dir" ]
  ! compgen -G "$tool_root/.sdk-payload-$version.*" >/dev/null
  ! compgen -G "$tool_root/.install-$version.*" >/dev/null
}

@test "malformed legacy checksum is rejected before download" {
  prepare_legacy_sha256_payload
  write_legacy_metadata 'not-a-digest'
  run_payload_install
  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported or malformed checksum"* ]]
  [ ! -e "$install_dir" ]
  ! grep -Fq "$artifact_url" "$test_home/curl.log"
}

@test "modern SDK cannot fall back to SHA-256 metadata" {
  version='10.0.401'
  install_dir="$tool_root/$version"
  artifact_url="https://builds.dotnet.microsoft.com/dotnet/Sdk/$version/dotnet-sdk-$version-$rid.tar.gz"
  write_legacy_metadata "$(printf '%064d' 0)"
  sed -i.bak 's/"name": "dotnet-dev-osx-x64.tar.gz"/"name": "dotnet-sdk-osx-x64.tar.gz"/' "$metadata"
  rm -f "$metadata.bak"
  run_payload_install
  [ "$status" -ne 0 ]
  [[ "$output" == *"SHA-256 is supported only for historical"* ]]
  [ ! -e "$install_dir" ]
  ! grep -Fq "$artifact_url" "$test_home/curl.log"
}

@test "an SDK version mismatch cannot select the archive" {
  write_legacy_metadata "$payload_hash"
  sed -i.bak 's/"version": "1.1.14"/"version": "1.0.4"/g' "$metadata"
  rm -f "$metadata.bak"
  run_payload_install
  [ "$status" -ne 0 ]
  [[ "$output" == *"did not contain exactly one SDK archive"* ]]
}

@test "modern generic Linux RID cannot silently select an old distro-specific or macOS archive" {
  cat > "$fake_bin/uname" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  -s) printf '%s\n' Linux ;;
  -m) printf '%s\n' x86_64 ;;
esac
EOF
  chmod +x "$fake_bin/uname"
  run_payload_install
  [ "$status" -ne 0 ]
  [[ "$output" == *"did not contain exactly one SDK archive for $version and linux-x64"* ]]
}

@test "metadata name inconsistent with legacy URL fails closed" {
  write_legacy_metadata "$payload_hash"
  sed -i.bak 's/"name": "dotnet-dev-osx-x64.tar.gz"/"name": "dotnet-dev-win-x64.tar.gz"/' "$metadata"
  rm -f "$metadata.bak"
  run_payload_install
  [ "$status" -ne 0 ]
  [[ "$output" == *"did not contain exactly one SDK archive"* ]]
}

@test "conflicting SHA-512 values for matching archives fail as ambiguous" {
  write_legacy_metadata "$payload_hash"
  awk -v url="$artifact_url" -v hash="$(printf '%0128d' 0)" '
    /"files": \[/ { file_arrays++ }
    { print }
    file_arrays == 2 && /"files": \[/ && !inserted++ {
      print "          {\"name\": \"dotnet-dev-osx-x64.tar.gz\", \"rid\": \"osx-x64\", \"url\": \"" url "\", \"hash\": \"" hash "\"},"
    }
  ' "$metadata" > "$metadata.tmp"
  mv "$metadata.tmp" "$metadata"
  jq -e . "$metadata" >/dev/null
  run_payload_install
  [ "$status" -ne 0 ]
  [[ "$output" == *"did not contain exactly one SDK archive"* ]]
}

@test "legacy host --version must report exact SDK version before promotion" {
  export SDK_TEST_DOTNET_VERSION='1.1.13'
  run_payload_install
  [ "$status" -ne 0 ]
  [[ "$output" == *"legacy --version did not resolve the exact requested SDK"* ]]
  [ ! -e "$install_dir" ]
  ! compgen -G "$tool_root/.sdk-host-verify-$version.*" >/dev/null
  ! compgen -G "$tool_root/.install-$version.*" >/dev/null
}

@test "legacy host Base Path must point to the isolated SDK directory" {
  export SDK_TEST_FAKE_BASE_PATH="$test_root"
  run_payload_install
  [ "$status" -ne 0 ]
  [[ "$output" == *"legacy SDK Base Path does not match the isolated directory"* ]]
  [ ! -e "$install_dir" ]
  ! compgen -G "$tool_root/.sdk-host-verify-$version.*" >/dev/null
  ! compgen -G "$tool_root/.install-$version.*" >/dev/null
}

@test "legacy host --info failure blocks promotion" {
  export SDK_TEST_LEGACY_CMD_FAILURE=1
  run_payload_install
  [ "$status" -ne 0 ]
  [[ "$output" == *"--version exited with code"* ]]
  [ ! -e "$install_dir" ]
  ! compgen -G "$tool_root/.sdk-host-verify-$version.*" >/dev/null
}

@test "verified existing legacy installation is recognized without a re-download" {
  run_payload_install
  [ "$status" -eq 0 ]
  run_payload_install
  [ "$status" -eq 0 ]
  [[ "$output" == *"Isolated SDK: Already installed"* ]]
  [ "$(grep -Fc "$artifact_url" "$test_home/curl.log")" -eq 1 ]
}


prepare_early2_payload() {
  version="$1"
  install_dir="$tool_root/$version"
  artifact_url="https://builds.dotnet.microsoft.com/dotnet/Sdk/$version/dotnet-sdk-$version-$rid.tar.gz"
  export SDK_TEST_DOTNET_VERSION="$version"
  mkdir -p "$fixture_root/sdk/$version"
  /usr/bin/tar -czf "$payload" -C "$fixture_root" dotnet sdk
  if command -v sha512sum >/dev/null 2>&1; then
    payload_hash="$(sha512sum "$payload" | awk '{print $1}')"
  else
    payload_hash="$(shasum -a 512 "$payload" | awk '{print $1}')"
  fi
  write_legacy_metadata "$payload_hash"
}

@test "early 2.1 SDK builds use Microsoft 2.0 metadata and exact isolated legacy-host proof" {
  local current=""
  for current in 2.1.4 2.1.105 2.1.202; do
    prepare_early2_payload "$current"
    run_payload_install
    [ "$status" -eq 0 ]
    [[ "$output" == *"Isolated SDK installation completed successfully."* ]]
    grep -Fq "/release-metadata/2.0/releases.json" "$test_home/curl.log"
    [ -x "$install_dir/dotnet" ]
    [ -d "$install_dir/sdk/$version" ]
    ! compgen -G "$tool_root/.sdk-host-verify-$version.*" >/dev/null
    ! compgen -G "$tool_root/.install-$version.*" >/dev/null
  done
}

@test "SDK 2.0.3 uses legacy host proof, not unsupported --list-sdks" {
  prepare_early2_payload '2.0.3'
  run_payload_install
  [ "$status" -eq 0 ]
  [ -d "$install_dir/sdk/$version" ]
  [[ "$output" == *"Isolated SDK installation completed successfully."* ]]
  ! compgen -G "$tool_root/.sdk-host-verify-$version.*" >/dev/null
}

@test "SDK 2.1.300 continues to use release channel 2.1 and modern host inventory" {
  prepare_early2_payload '2.1.300'
  run_payload_install
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unable to verify isolated SDK $version with exit code"* ]]
  grep -Fq '/release-metadata/2.1/releases.json' "$test_home/curl.log"
  [ ! -e "$install_dir" ]
}

@test "SDK 2.0.3 never accepts a system SDK in place of its exact staged SDK" {
  prepare_early2_payload '2.0.3'
  export SDK_TEST_DOTNET_VERSION='10.0.402'
  run_payload_install
  [ "$status" -ne 0 ]
  [[ "$output" == *"legacy --version did not resolve the exact requested SDK"* ]]
  [ ! -e "$install_dir" ]
  ! compgen -G "$tool_root/.sdk-host-verify-$version.*" >/dev/null
  ! compgen -G "$tool_root/.install-$version.*" >/dev/null
}

@test "SDK 2.1.105 refuses a host resolving an external Base Path" {
  prepare_early2_payload '2.1.105'
  export SDK_TEST_FAKE_BASE_PATH="$test_root"
  run_payload_install
  [ "$status" -ne 0 ]
  [[ "$output" == *"legacy SDK Base Path does not match the isolated directory"* ]]
  [ ! -e "$install_dir" ]
  ! compgen -G "$tool_root/.sdk-host-verify-$version.*" >/dev/null
}

@test "SHA-256 is still rejected for every 2.0-era SDK" {
  prepare_early2_payload '2.1.105'
  write_legacy_metadata "$(printf '%064d' 0)"
  run_payload_install
  [ "$status" -ne 0 ]
  [[ "$output" == *"SHA-256 is supported only for historical"* ]]
  [ ! -e "$install_dir" ]
  ! grep -Fq "$artifact_url" "$test_home/curl.log"
}
