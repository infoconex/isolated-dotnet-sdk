#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-release-tests.XXXXXX")"
  test_home="$test_root/home"
  tool_root="$test_home/dotnet-sdks"
  tool_path="$tool_root/isolated-dotnet-sdk.sh"
  release_a="$test_root/release-a.sh"
  release_b="$test_root/release-b.sh"
  mkdir -p "$test_home"

  cp "$repo_root/isolated-dotnet-sdk.sh" "$release_a"
  cp "$repo_root/isolated-dotnet-sdk.sh" "$release_b"
  printf '\n# release-source-marker: v1.0.0\n' >> "$release_a"
  printf '\n# release-source-marker: v2.0.0\n' >> "$release_b"
  chmod +x "$release_a" "$release_b"
}

teardown() {
  rm -rf "$test_root"
}

@test "file-based stable bootstrap installs the exact selected release source" {
  run env HOME="$test_home" "$release_a" list

  [ "$status" -eq 0 ]
  grep -Fq '# release-source-marker: v1.0.0' "$tool_path"
  ! grep -Fq '# release-source-marker: v2.0.0' "$tool_path"
}

@test "explicit stable update replaces the saved tool with the newly selected release" {
  env HOME="$test_home" "$release_a" list >/dev/null

  run env HOME="$test_home" "$release_b" list

  [ "$status" -eq 0 ]
  grep -Fq '# release-source-marker: v2.0.0' "$tool_path"
  ! grep -Fq '# release-source-marker: v1.0.0' "$tool_path"
}

@test "explicit rollback replaces the saved tool with the older selected release" {
  env HOME="$test_home" "$release_a" list >/dev/null
  env HOME="$test_home" "$release_b" list >/dev/null

  run env HOME="$test_home" "$release_a" list

  [ "$status" -eq 0 ]
  grep -Fq '# release-source-marker: v1.0.0' "$tool_path"
  ! grep -Fq '# release-source-marker: v2.0.0' "$tool_path"
}

@test "normal saved-tool execution does not implicitly replace or update itself" {
  env HOME="$test_home" "$release_a" list >/dev/null
  before="$(cksum "$tool_path")"

  run env HOME="$test_home" "$tool_path" list

  [ "$status" -eq 0 ]
  [ "$(cksum "$tool_path")" = "$before" ]
  grep -Fq '# release-source-marker: v1.0.0' "$tool_path"
}
