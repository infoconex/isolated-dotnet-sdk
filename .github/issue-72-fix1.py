from pathlib import Path

root = Path(__file__).resolve().parents[1]


def replace(path, old, new):
    p = root / path
    text = p.read_text()
    if old not in text:
        raise SystemExit(f"expected text not found in {path}: {old!r}")
    p.write_text(text.replace(old, new))

# Analyzer naming: this resolves one artifact, not a collection.
replace("isolated-dotnet-sdk.ps1", "Get-SdkArtifactMetadata", "Resolve-SdkArtifact")

# Exact-version installs still bypass the release index/picker; they now load the
# exact channel metadata needed to authenticate the requested payload.
helper_url = "https://raw.githubusercontent.com/dotnet/install-scripts/da3ce11ba63f3dbb0fb835d41bda2665d5c48e84/src/dotnet-install.sh"
replace("tests/bash/metadata.bats", helper_url, "https://builds.dotnet.microsoft.com/dotnet/release-metadata/99.9/releases.json")
replace("tests/bash/public-boundaries.bats", helper_url, "https://builds.dotnet.microsoft.com/dotnet/release-metadata/99.0/releases.json")

fixture = r'''# Shared deterministic fixture for Bash SDK-payload transaction tests.

payload_test_setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-payload-test.XXXXXX")"
  test_home="$test_root/home"
  tool_root="$test_home/dotnet-sdks"
  tool_path="$tool_root/isolated-dotnet-sdk.sh"
  fake_bin="$test_root/fake-bin"
  fixture_root="$test_root/fixture"
  version='99.0.100'
  rid='linux-x64'
  install_dir="$tool_root/$version"
  metadata="$test_root/releases.json"
  payload="$test_root/sdk.tar.gz"
  artifact_url="https://builds.dotnet.microsoft.com/dotnet/Sdk/$version/dotnet-sdk-$version-$rid.tar.gz"
  metadata_url="https://builds.dotnet.microsoft.com/dotnet/release-metadata/99.0/releases.json"

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

  cat > "$fake_bin/dotnet" <<'EOF'
#!/usr/bin/env bash
exit "${SDK_TEST_SYSTEM_DOTNET_EXIT:-0}"
EOF

  cat > "$fixture_root/dotnet" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == '--list-sdks' ]]; then
  if [[ -n "${SDK_TEST_CREATE_DEST_ON_VERIFY:-}" ]]; then
    mkdir -p "$HOME/dotnet-sdks/99.0.100"
    printf '%s\n' external > "$HOME/dotnet-sdks/99.0.100/external.txt"
  fi
  if [[ -n "${SDK_TEST_DOTNET_EXIT:-}" ]]; then
    exit "$SDK_TEST_DOTNET_EXIT"
  fi
  printf '%s [/fixture/sdk]\n' "${SDK_TEST_DOTNET_VERSION:-99.0.100}"
  exit 0
fi
exit 0
EOF
  chmod +x "$fake_bin/uname" "$fake_bin/dotnet" "$fixture_root/dotnet"

  /usr/bin/tar -czf "$payload" -C "$fixture_root" dotnet
  if command -v sha512sum >/dev/null 2>&1; then
    payload_hash="$(sha512sum "$payload" | awk '{print $1}')"
  else
    payload_hash="$(/usr/bin/shasum -a 512 "$payload" | awk '{print $1}')"
  fi
  write_payload_metadata "$payload_hash"

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
  *release-metadata*)
    if [[ -n "${SDK_TEST_METADATA_CURL_EXIT:-}" ]]; then exit "$SDK_TEST_METADATA_CURL_EXIT"; fi
    cp "$SDK_TEST_METADATA" "$out"
    ;;
  */dotnet/Sdk/*)
    if [[ -n "${SDK_TEST_PAYLOAD_CURL_EXIT:-}" ]]; then exit "$SDK_TEST_PAYLOAD_CURL_EXIT"; fi
    cp "$SDK_TEST_PAYLOAD" "$out"
    ;;
  *) exit 22 ;;
esac
EOF

  cat > "$fake_bin/tar" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${SDK_TEST_TAR_EXIT:-}" ]]; then
  exit "$SDK_TEST_TAR_EXIT"
fi
exec /usr/bin/tar "$@"
EOF

  cat > "$fake_bin/mv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${SDK_TEST_MV_EXIT:-}" && "${1:-}" == *'/.install-'* ]]; then
  exit "$SDK_TEST_MV_EXIT"
fi
exec /bin/mv "$@"
EOF

  cat > "$fake_bin/rm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
for arg in "$@"; do
  if [[ -n "${SDK_TEST_RM_FAIL_PATTERN:-}" && "$arg" == *"$SDK_TEST_RM_FAIL_PATTERN"* ]]; then
    printf '%s\n' cleanup-remove-failed >&2
    exit "${SDK_TEST_RM_EXIT:-91}"
  fi
done
exec /bin/rm "$@"
EOF

  chmod +x "$fake_bin/curl" "$fake_bin/tar" "$fake_bin/mv" "$fake_bin/rm"
  export SDK_TEST_METADATA="$metadata"
  export SDK_TEST_PAYLOAD="$payload"
}

write_payload_metadata() {
  local hash="$1"
  cat > "$metadata" <<EOF
{
  "releases": [
    {
      "sdk": {
        "version": "$version",
        "files": [
          { "rid": "$rid", "url": "$artifact_url", "hash": "$hash" }
        ]
      }
    }
  ]
}
EOF
}

build_payload_without_dotnet() {
  local empty="$test_root/empty"
  mkdir -p "$empty"
  printf '%s\n' placeholder > "$empty/README.txt"
  /usr/bin/tar -czf "$payload" -C "$empty" README.txt
  if command -v sha512sum >/dev/null 2>&1; then
    payload_hash="$(sha512sum "$payload" | awk '{print $1}')"
  else
    payload_hash="$(/usr/bin/shasum -a 512 "$payload" | awk '{print $1}')"
  fi
  write_payload_metadata "$payload_hash"
}

payload_test_teardown() {
  /bin/rm -rf "$test_root"
}

run_payload_install() {
  run env HOME="$test_home" PATH="$fake_bin:$PATH" \
    SDK_TEST_METADATA="$metadata" SDK_TEST_PAYLOAD="$payload" \
    SDK_TEST_METADATA_CURL_EXIT="${SDK_TEST_METADATA_CURL_EXIT:-}" \
    SDK_TEST_PAYLOAD_CURL_EXIT="${SDK_TEST_PAYLOAD_CURL_EXIT:-}" \
    SDK_TEST_TAR_EXIT="${SDK_TEST_TAR_EXIT:-}" \
    SDK_TEST_DOTNET_EXIT="${SDK_TEST_DOTNET_EXIT:-}" \
    SDK_TEST_DOTNET_VERSION="${SDK_TEST_DOTNET_VERSION:-}" \
    SDK_TEST_CREATE_DEST_ON_VERIFY="${SDK_TEST_CREATE_DEST_ON_VERIFY:-}" \
    SDK_TEST_MV_EXIT="${SDK_TEST_MV_EXIT:-}" \
    SDK_TEST_RM_FAIL_PATTERN="${SDK_TEST_RM_FAIL_PATTERN:-}" \
    SDK_TEST_RM_EXIT="${SDK_TEST_RM_EXIT:-}" \
    "$tool_path" install "$version" --yes
}
'''
(root / "tests/bash/sdk-payload-fixture.bash").write_text(fixture)

native = r'''#!/usr/bin/env bats

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
'''
(root / "tests/bash/native-failures.bats").write_text(native)

transactional = r'''#!/usr/bin/env bats

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
'''
(root / "tests/bash/transactional-install.bats").write_text(transactional)

promotion = r'''#!/usr/bin/env bats

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
'''
(root / "tests/bash/promotion-conflict.bats").write_text(promotion)

regressions = r'''#!/usr/bin/env bats

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
'''
(root / "tests/bash/transactional-regressions.bats").write_text(regressions)

finalization = r'''#!/usr/bin/env bats

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
'''
(root / "tests/bash/finalization-failures.bats").write_text(finalization)

print('issue 72 fix1 applied')
