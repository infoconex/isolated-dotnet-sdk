#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-transaction-tests.XXXXXX")"
  test_home="$test_root/home"
  tool_root="$test_home/dotnet-sdks"
  tool_path="$tool_root/isolated-dotnet-sdk.sh"
  version='99.0.100'
  install_dir="$tool_root/$version"

  mkdir -p "$tool_root"
  cp "$repo_root/isolated-dotnet-sdk.sh" "$tool_path"
  chmod +x "$tool_path"
}

teardown() {
  rm -rf "$test_root"
}

make_successful_system_dotnet() {
  local fake_bin="$1"
  cat > "$fake_bin/dotnet" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$fake_bin/dotnet"
}

write_fake_curl_with_installer() {
  local fake_bin="$1"
  local installer_body="$2"

  cat > "$fake_bin/curl" <<EOF
#!/usr/bin/env bash
set -euo pipefail
out_file=''
while [[ \$# -gt 0 ]]; do
  if [[ "\$1" == '-o' ]]; then
    out_file="\$2"
    shift 2
  else
    shift
  fi
done
cat > "\$out_file" <<'INSTALLER'
#!/usr/bin/env bash
set -euo pipefail
$installer_body
INSTALLER
EOF
  chmod +x "$fake_bin/curl"
}

@test "pre-existing non-valid destination fails before download and is preserved" {
  fake_bin="$test_root/conflict-fake-bin"
  mkdir -p "$fake_bin" "$install_dir"
  make_successful_system_dotnet "$fake_bin"
  printf '%s\n' 'preserve-me' > "$install_dir/sentinel.txt"

  cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'download-ran' > "$HOME/download-ran.txt"
exit 88
EOF
  chmod +x "$fake_bin/curl"

  run env HOME="$test_home" PATH="$fake_bin:$PATH" "$tool_path" install "$version" --yes

  [ "$status" -ne 0 ]
  [[ "$output" == *"destination already exists"* ]]
  [ "$(cat "$install_dir/sentinel.txt")" = 'preserve-me' ]
  [ ! -e "$test_home/download-ran.txt" ]
}

@test "installer failure uses staging and cleans the failed attempt" {
  fake_bin="$test_root/installer-failure-fake-bin"
  mkdir -p "$fake_bin"
  make_successful_system_dotnet "$fake_bin"

  write_fake_curl_with_installer "$fake_bin" '
install_dir=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-dir) install_dir="$2"; shift 2 ;;
    *) shift ;;
  esac
done
printf "%s\n" "$install_dir" > "$HOME/installer-target.txt"
mkdir -p "$install_dir"
printf "%s\n" partial > "$install_dir/partial.txt"
exit 73'

  run env HOME="$test_home" PATH="$fake_bin:$PATH" "$tool_path" install "$version" --yes

  [ "$status" -ne 0 ]
  [[ "$output" == *"dotnet-install failed for SDK $version with exit code 73."* ]]
  target="$(cat "$test_home/installer-target.txt")"
  [ "$target" != "$install_dir" ]
  [[ "$target" == "$tool_root/.install-$version."* ]]
  [ ! -e "$target" ]
  [ ! -e "$install_dir" ]
}

@test "missing staged host fails before promotion and cleans staging" {
  fake_bin="$test_root/missing-host-fake-bin"
  mkdir -p "$fake_bin"
  make_successful_system_dotnet "$fake_bin"

  write_fake_curl_with_installer "$fake_bin" '
install_dir=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-dir) install_dir="$2"; shift 2 ;;
    *) shift ;;
  esac
done
printf "%s\n" "$install_dir" > "$HOME/installer-target.txt"
mkdir -p "$install_dir"
exit 0'

  run env HOME="$test_home" PATH="$fake_bin:$PATH" "$tool_path" install "$version" --yes

  [ "$status" -ne 0 ]
  [[ "$output" == *"isolated dotnet executable was not found"* ]]
  target="$(cat "$test_home/installer-target.txt")"
  [ ! -e "$target" ]
  [ ! -e "$install_dir" ]
}

@test "staged host failure blocks promotion and cleans staging" {
  fake_bin="$test_root/host-failure-fake-bin"
  mkdir -p "$fake_bin"
  make_successful_system_dotnet "$fake_bin"

  write_fake_curl_with_installer "$fake_bin" '
install_dir=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-dir) install_dir="$2"; shift 2 ;;
    *) shift ;;
  esac
done
printf "%s\n" "$install_dir" > "$HOME/installer-target.txt"
mkdir -p "$install_dir"
cat > "$install_dir/dotnet" <<"DOTNET"
#!/usr/bin/env bash
exit 74
DOTNET
chmod +x "$install_dir/dotnet"
exit 0'

  run env HOME="$test_home" PATH="$fake_bin:$PATH" "$tool_path" install "$version" --yes

  [ "$status" -ne 0 ]
  [[ "$output" == *"Unable to verify isolated SDK $version with exit code 74."* ]]
  target="$(cat "$test_home/installer-target.txt")"
  [ ! -e "$target" ]
  [ ! -e "$install_dir" ]
}

@test "staged inventory missing the exact version blocks promotion" {
  fake_bin="$test_root/missing-version-fake-bin"
  mkdir -p "$fake_bin"
  make_successful_system_dotnet "$fake_bin"

  write_fake_curl_with_installer "$fake_bin" '
install_dir=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-dir) install_dir="$2"; shift 2 ;;
    *) shift ;;
  esac
done
printf "%s\n" "$install_dir" > "$HOME/installer-target.txt"
mkdir -p "$install_dir"
cat > "$install_dir/dotnet" <<"DOTNET"
#!/usr/bin/env bash
printf "%s\n" "98.0.100 [/fake]"
exit 0
DOTNET
chmod +x "$install_dir/dotnet"
exit 0'

  run env HOME="$test_home" PATH="$fake_bin:$PATH" "$tool_path" install "$version" --yes

  [ "$status" -ne 0 ]
  [[ "$output" == *"SDK $version was not found after installation."* ]]
  target="$(cat "$test_home/installer-target.txt")"
  [ ! -e "$target" ]
  [ ! -e "$install_dir" ]
}

@test "verified staging is promoted to the final destination" {
  fake_bin="$test_root/success-fake-bin"
  mkdir -p "$fake_bin"
  make_successful_system_dotnet "$fake_bin"

  write_fake_curl_with_installer "$fake_bin" '
install_dir=""
version=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-dir) install_dir="$2"; shift 2 ;;
    --version) version="$2"; shift 2 ;;
    *) shift ;;
  esac
done
printf "%s\n" "$install_dir" > "$HOME/installer-target.txt"
mkdir -p "$install_dir"
cat > "$install_dir/dotnet" <<DOTNET
#!/usr/bin/env bash
printf "%s\\n" "$version [/fake]"
exit 0
DOTNET
chmod +x "$install_dir/dotnet"
exit 0'

  run env HOME="$test_home" PATH="$fake_bin:$PATH" "$tool_path" install "$version" --yes

  [ "$status" -eq 0 ]
  [[ "$output" == *"Isolated SDK installation completed successfully."* ]]
  [[ "$output" == *"Location: $install_dir"* ]]
  target="$(cat "$test_home/installer-target.txt")"
  [ "$target" != "$install_dir" ]
  [[ "$target" == "$tool_root/.install-$version."* ]]
  [ ! -e "$target" ]
  [ -x "$install_dir/dotnet" ]
  ! compgen -G "$tool_root/dotnet-install.sh.*" >/dev/null
}

@test "retry after failed clean-start installation needs no manual cleanup" {
  fake_bin="$test_root/retry-fake-bin"
  mkdir -p "$fake_bin"
  make_successful_system_dotnet "$fake_bin"

  cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
out_file=''
while [[ $# -gt 0 ]]; do
  if [[ "$1" == '-o' ]]; then
    out_file="$2"
    shift 2
  else
    shift
  fi
done
attempt_file="$HOME/install-attempt.txt"
attempt=0
[[ ! -f "$attempt_file" ]] || attempt="$(cat "$attempt_file")"
attempt=$((attempt + 1))
printf '%s\n' "$attempt" > "$attempt_file"
if [[ "$attempt" -eq 1 ]]; then
  cat > "$out_file" <<'INSTALLER'
#!/usr/bin/env bash
set -euo pipefail
install_dir=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-dir) install_dir="$2"; shift 2 ;;
    *) shift ;;
  esac
done
mkdir -p "$install_dir"
printf '%s\n' partial > "$install_dir/partial.txt"
exit 73
INSTALLER
else
  cat > "$out_file" <<'INSTALLER'
#!/usr/bin/env bash
set -euo pipefail
install_dir=''
version=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-dir) install_dir="$2"; shift 2 ;;
    --version) version="$2"; shift 2 ;;
    *) shift ;;
  esac
done
mkdir -p "$install_dir"
cat > "$install_dir/dotnet" <<DOTNET
#!/usr/bin/env bash
printf '%s\n' "$version [/fake]"
exit 0
DOTNET
chmod +x "$install_dir/dotnet"
exit 0
INSTALLER
fi
EOF
  chmod +x "$fake_bin/curl"

  run env HOME="$test_home" PATH="$fake_bin:$PATH" "$tool_path" install "$version" --yes
  [ "$status" -ne 0 ]
  [ ! -e "$install_dir" ]

  run env HOME="$test_home" PATH="$fake_bin:$PATH" "$tool_path" install "$version" --yes
  [ "$status" -eq 0 ]
  [ -x "$install_dir/dotnet" ]
}
