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
  write_legacy_metadata "$payload_hash"
}
teardown() { payload_test_teardown; }

write_legacy_metadata() {
  local hash="$1"
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
            "name": "dotnet-dev-$rid.tar.gz",
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
  ! compgen -G "$tool_root/.install-$version.*" >/dev/null
}

@test "SDK 1.0.4 SHA-256 metadata is rejected without downloading or extracting" {
  version='1.0.4'
  artifact_url="https://builds.dotnet.microsoft.com/dotnet/Sdk/$version/dotnet-dev-$rid.$version.tar.gz"
  write_legacy_metadata "$(printf '%064d' 0)"
  run_payload_install
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid SHA-512 hash for SDK $version and $rid"* ]]
  [ ! -e "$tool_root/$version" ]
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
