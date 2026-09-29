#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-public-boundaries.XXXXXX")"
  test_home="$test_root/home"
  tool_root="$test_home/dotnet-sdks"
  tool_path="$tool_root/isolated-dotnet-sdk.sh"
  source_copy="$test_root/isolated-dotnet-sdk-source.sh"

  mkdir -p "$tool_root"
  cp "$repo_root/isolated-dotnet-sdk.sh" "$tool_path"
  chmod +x "$tool_path"
}

teardown() {
  rm -rf "$test_root"
}

@test "bare exact version resolves to install" {
  fake_bin="$test_root/bare-version-bin"
  curl_log="$test_root/curl.log"
  mkdir -p "$fake_bin"

  cat > "$fake_bin/dotnet" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
printf '%s\n' "$url" >> "$CURL_LOG"
exit 81
EOF
  chmod +x "$fake_bin/dotnet" "$fake_bin/curl"

  run env HOME="$test_home" PATH="$fake_bin:$PATH" CURL_LOG="$curl_log" \
    "$tool_path" 99.0.100 --yes

  [ "$status" -ne 0 ]
  [[ "$output" == *"Target SDK: 99.0.100"* ]]
  grep -Fq 'https://builds.dotnet.microsoft.com/dotnet/release-metadata/99.0/releases.json' "$curl_log"
}

@test "remove with no installed SDKs is a successful no-change result" {
  run env HOME="$test_home" "$tool_path" remove

  [ "$status" -eq 0 ]
  [[ "$output" == *"No isolated SDKs are installed under $tool_root."* ]]
  [[ "$output" == *"Removal cancelled."* ]]
}

@test "explicit removal picker cancellation is successful and preserves the SDK" {
  version='99.0.100'
  install_dir="$tool_root/$version"
  shutdown_marker="$test_root/shutdown-ran"
  mkdir -p "$install_dir"
  cat > "$install_dir/dotnet" <<EOF
#!/usr/bin/env bash
printf '%s\n' shutdown > '$shutdown_marker'
exit 0
EOF
  chmod +x "$install_dir/dotnet"

  run bash -c 'printf "q\n" | env HOME="$1" "$2" remove' _ "$test_home" "$tool_path"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Removal cancelled."* ]]
  [ -d "$install_dir" ]
  [ ! -e "$shutdown_marker" ]
}

@test "unavailable removal picker input fails instead of becoming cancellation" {
  version='99.0.100'
  install_dir="$tool_root/$version"
  mkdir -p "$install_dir"
  cat > "$install_dir/dotnet" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$install_dir/dotnet"

  run bash -c 'exec </dev/null; env HOME="$1" "$2" remove' _ "$test_home" "$tool_path"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Interactive input is unavailable."* ]]
  [[ "$output" != *"Removal cancelled."* ]]
  [ -d "$install_dir" ]
}

@test "list includes SDK directories and ignores non-SDK tool artifacts" {
  version='99.0.100'
  install_dir="$tool_root/$version"
  mkdir -p "$install_dir" "$tool_root/not-an-sdk" "$tool_root/.install-99.0.200.leftover"
  cat > "$install_dir/dotnet" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$install_dir/dotnet"
  printf '%s\n' payload > "$tool_root/.sdk-payload-99.0.200.leftover.tar.gz"

  run env HOME="$test_home" "$tool_path" list

  [ "$status" -eq 0 ]
  [[ "$output" == *"  $version"* ]]
  [[ "$output" != *"not-an-sdk"* ]]
  [[ "$output" != *".sdk-payload-99.0.200.leftover.tar.gz"* ]]
  [[ "$output" != *".install-99.0.200.leftover"* ]]
}

@test "file bootstrap preserves a failing saved child status" {
  cp "$repo_root/isolated-dotnet-sdk.sh" "$source_copy"
  chmod +x "$source_copy"

  run env HOME="$test_home" "$source_copy" install 'invalid/version' --yes

  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid SDK version: invalid/version"* ]]
  [ -x "$tool_path" ]
}