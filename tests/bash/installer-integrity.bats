#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-payload-integrity.XXXXXX")"
  test_home="$test_root/home"
  tool_root="$test_home/dotnet-sdks"
  tool_path="$tool_root/isolated-dotnet-sdk.sh"
  fake_bin="$test_root/fake-bin"
  fixture_root="$test_root/fixture"
  version='99.0.100'
  rid='linux-x64'
  artifact_url="https://builds.dotnet.microsoft.com/dotnet/Sdk/$version/dotnet-sdk-$version-$rid.tar.gz"
  metadata_url="https://builds.dotnet.microsoft.com/dotnet/release-metadata/99.0/releases.json"
  payload="$test_root/sdk.tar.gz"
  metadata="$test_root/releases.json"

  mkdir -p "$tool_root" "$fake_bin" "$fixture_root"
  cp "$repo_root/isolated-dotnet-sdk.sh" "$tool_path"
  chmod +x "$tool_path"

  cat > "$fake_bin/uname" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  -s) printf '%s\n' Linux ;;
  -m) printf '%s\n' x86_64 ;;
  *) printf '%s\n' Linux ;;
esac
EOF
  chmod +x "$fake_bin/uname"

  cat > "$fake_bin/dotnet" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$fake_bin/dotnet"

  cat > "$fixture_root/dotnet" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == '--list-sdks' ]]; then
  printf '%s\n' '99.0.100 [/fixture/sdk]'
  exit 0
fi
exit 0
EOF
  chmod +x "$fixture_root/dotnet"
  tar -czf "$payload" -C "$fixture_root" dotnet

  if command -v sha512sum >/dev/null 2>&1; then
    payload_hash="$(sha512sum "$payload" | awk '{print $1}')"
  else
    payload_hash="$(shasum -a 512 "$payload" | awk '{print $1}')"
  fi

  write_metadata "$payload_hash"

  cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url=''
out=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
printf '%s\n' "$url" >> "$HOME/curl.log"
case "$url" in
  *release-metadata*) cp "$TEST_METADATA" "$out" ;;
  */dotnet/Sdk/*) cp "$TEST_PAYLOAD" "$out" ;;
  *) exit 22 ;;
esac
EOF
  chmod +x "$fake_bin/curl"
}

write_metadata() {
  local hash="$1"
  cat > "$metadata" <<EOF
{
  "releases": [
    {
      "sdk": {
        "version": "$version",
        "files": [
          {
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

teardown() {
  rm -rf "$test_root"
}

run_install() {
  run env HOME="$test_home" TEST_METADATA="$metadata" TEST_PAYLOAD="$payload" PATH="$fake_bin:$PATH" \
    "$tool_path" install "$version" --yes
}

@test "verified SDK payload is extracted and promoted" {
  run_install

  [ "$status" -eq 0 ]
  [ -x "$tool_root/$version/dotnet" ]
  [[ "$output" == *"Extracting verified .NET SDK $version payload..."* ]]
  [[ "$output" == *"Isolated SDK installation completed successfully."* ]]
  grep -Fq "$metadata_url" "$test_home/curl.log"
  grep -Fq "$artifact_url" "$test_home/curl.log"
  ! compgen -G "$tool_root/.release-metadata-$version.*" >/dev/null
  ! compgen -G "$tool_root/.sdk-payload-$version.*" >/dev/null
  ! compgen -G "$tool_root/.install-$version.*" >/dev/null
}

@test "SDK payload checksum mismatch prevents extraction and promotion" {
  write_metadata "$(printf '%0128d' 0)"
  cat > "$fake_bin/tar" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' called > "$HOME/tar-called.txt"
exit 91
EOF
  chmod +x "$fake_bin/tar"

  run_install

  [ "$status" -ne 0 ]
  [[ "$output" == *"Integrity verification failed for the .NET SDK $version payload."* ]]
  [ ! -e "$test_home/tar-called.txt" ]
  [ ! -e "$tool_root/$version" ]
  ! compgen -G "$tool_root/.release-metadata-$version.*" >/dev/null
  ! compgen -G "$tool_root/.sdk-payload-$version.*" >/dev/null
}

@test "missing matching SDK artifact metadata fails closed" {
  write_metadata "$payload_hash"
  sed -i.bak "s/$rid/linux-arm64/" "$metadata"
  rm -f "$metadata.bak"

  run_install

  [ "$status" -ne 0 ]
  [[ "$output" == *"did not contain exactly one SDK archive for $version and $rid"* ]]
  [ ! -e "$tool_root/$version" ]
}

@test "malformed SDK payload checksum metadata fails closed" {
  write_metadata deadbeef

  run_install

  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid SHA-512 hash for SDK $version and $rid"* ]]
  [ ! -e "$tool_root/$version" ]
}
