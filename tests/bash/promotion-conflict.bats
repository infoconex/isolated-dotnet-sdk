#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-promotion-tests.XXXXXX")"
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

@test "destination appearing before promotion is preserved and staging is cleaned" {
  fake_bin="$test_root/fake-bin"
  mkdir -p "$fake_bin"

  cat > "$fake_bin/dotnet" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$fake_bin/dotnet"

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
printf '%s\n' "$install_dir" > "$HOME/installer-target.txt"
mkdir -p "$install_dir"
cat > "$install_dir/dotnet" <<DOTNET
#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$HOME/dotnet-sdks/$version"
printf '%s\n' 'preserve-conflict' > "$HOME/dotnet-sdks/$version/sentinel.txt"
printf '%s\n' '$version [/fake]'
exit 0
DOTNET
chmod +x "$install_dir/dotnet"
exit 0
INSTALLER
EOF
  chmod +x "$fake_bin/curl"

  run env HOME="$test_home" PATH="$fake_bin:$PATH" "$tool_path" install "$version" --yes

  [ "$status" -ne 0 ]
  [[ "$output" == *"destination already exists"* ]]
  [[ "$output" != *"installation completed successfully"* ]]
  [ "$(cat "$install_dir/sentinel.txt")" = 'preserve-conflict' ]
  target="$(cat "$test_home/installer-target.txt")"
  [ "$target" != "$install_dir" ]
  [ ! -e "$target" ]
}
