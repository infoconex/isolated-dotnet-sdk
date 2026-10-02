#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-removal-presentation.XXXXXX")"
  test_home="$test_root/home"
  tool_root="$test_home/dotnet-sdks"
  tool_path="$tool_root/isolated-dotnet-sdk.sh"
  mkdir -p "$tool_root"
  cp "$repo_root/isolated-dotnet-sdk.sh" "$tool_path"
  chmod +x "$tool_path"
}

teardown() {
  rm -rf "$test_root"
}

@test "removal shutdown suppresses successful child chatter and scopes first-run controls" {
  version='99.0.100'
  install_dir="$tool_root/$version"
  mkdir -p "$install_dir"
  cat > "$install_dir/dotnet" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${DOTNET_NOLOGO:-}" == "true" ]] || exit 81
[[ "${DOTNET_GENERATE_ASPNET_CERTIFICATE:-}" == "false" ]] || exit 82
[[ "${DOTNET_ADD_GLOBAL_TOOLS_TO_PATH:-}" == "false" ]] || exit 83
printf '%s\n' 'child shutdown chatter'
EOF
  chmod +x "$install_dir/dotnet"

  run env HOME="$test_home" "$tool_path" remove "$version" --yes

  [ "$status" -eq 0 ]
  [[ "$output" != *"child shutdown chatter"* ]]
  [[ "$output" == *"Shutting down build servers for SDK $version..."* ]]
  [[ "$output" == *"Isolated SDK $version was removed."* ]]
}

@test "destructive warning has explicit blank boundaries in source" {
  warning_line="$(grep -n 'tool_warn "Isolated SDK \$VERSION will be removed from \$install_dir"' "$repo_root/isolated-dotnet-sdk.sh" | cut -d: -f1)"
  [ -n "$warning_line" ]

  previous_line="$(sed -n "$((warning_line - 1))p" "$repo_root/isolated-dotnet-sdk.sh")"
  next_line="$(sed -n "$((warning_line + 1))p" "$repo_root/isolated-dotnet-sdk.sh")"

  [[ "$previous_line" =~ ^[[:space:]]*echo[[:space:]]*$ ]]
  [[ "$next_line" =~ ^[[:space:]]*echo[[:space:]]*$ ]]
}
