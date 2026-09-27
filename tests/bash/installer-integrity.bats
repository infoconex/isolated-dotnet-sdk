#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-integrity-tests.XXXXXX")"
  test_home="$test_root/home"
  tool_root="$test_home/dotnet-sdks"
  tool_path="$tool_root/isolated-dotnet-sdk.sh"
  fake_bin="$test_root/fake-bin"
  version='99.0.100'
  install_dir="$tool_root/$version"
  expected_url='https://raw.githubusercontent.com/dotnet/install-scripts/da3ce11ba63f3dbb0fb835d41bda2665d5c48e84/src/dotnet-install.sh'

  mkdir -p "$tool_root" "$fake_bin"
  cp "$repo_root/isolated-dotnet-sdk.sh" "$tool_path"
  chmod +x "$tool_path"

  cat > "$fake_bin/dotnet" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$fake_bin/dotnet"

  cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$HOME/curl.log"
out_file=''
while [[ $# -gt 0 ]]; do
  if [[ "$1" == '-o' ]]; then
    out_file="$2"
    shift 2
  else
    shift
  fi
done
cat > "$out_file" <<'INSTALLER'
#!/usr/bin/env bash
printf '%s\n' executed > "$HOME/helper-executed.txt"
exit 73
INSTALLER
EOF
  chmod +x "$fake_bin/curl"

  cat > "$fake_bin/sha256sum" <<'EOF'
#!/usr/bin/env bash
printf '%064d  %s\n' 0 "$1"
EOF
  chmod +x "$fake_bin/sha256sum"

  cat > "$fake_bin/shasum" <<'EOF'
#!/usr/bin/env bash
path="${@: -1}"
printf '%064d  %s\n' 0 "$path"
EOF
  chmod +x "$fake_bin/shasum"
}

teardown() {
  rm -rf "$test_root"
}

@test "pinned Microsoft installer hash mismatch prevents execution" {
  run env HOME="$test_home" PATH="$fake_bin:$PATH" "$tool_path" install "$version" --yes

  [ "$status" -ne 0 ]
  grep -Fq "$expected_url" "$test_home/curl.log"
  [[ "$output" == *"Integrity verification failed for Microsoft's dotnet-install.sh script."* ]]
  [ ! -e "$test_home/helper-executed.txt" ]
  [ ! -e "$install_dir" ]
  ! compgen -G "$tool_root/dotnet-install.sh.*" >/dev/null
}

@test "repository integrity config records immutable Microsoft provenance" {
  config="$repo_root/.config/remote-artifacts.json"

  [ "$(jq -r '.dotnetInstall.commit' "$config")" = 'da3ce11ba63f3dbb0fb835d41bda2665d5c48e84' ]
  [ "$(jq -r '.dotnetInstall.bash.blob' "$config")" = 'bd13ffa6656fe776c95b561fe4df640918867523' ]
  [ "$(jq -r '.dotnetInstall.bash.sha256' "$config")" = '082f7685e156738a1b2e2ed8381a621870d4ce8e8c59278034556f05c186eb2e' ]
  [ "$(jq -r '.dotnetInstall.bash.url' "$config")" = "$expected_url" ]
}
