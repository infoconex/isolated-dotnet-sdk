#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  tool="$repo_root/isolated-dotnet-sdk.sh"
  bash_path="$(command -v bash)"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-version.XXXXXX")"
  test_home="$test_root/home"
  mkdir -p "$test_home"
}

teardown() {
  rm -rf "$test_root"
}

@test "development tool version query is side-effect free and needs no operational dependencies" {
  run env \
    HOME="$test_home" \
    PATH='' \
    http_proxy='http://127.0.0.1:1' \
    https_proxy='http://127.0.0.1:1' \
    HTTP_PROXY='http://127.0.0.1:1' \
    HTTPS_PROXY='http://127.0.0.1:1' \
    "$bash_path" "$tool" --version

  [ "$status" -eq 0 ]
  [ "$output" = "isolated-dotnet-sdk development (main)" ]
  [ ! -e "$test_home/dotnet-sdks" ]
}

@test "stable release marker reports the exact release identity without operational dependencies" {
  stable_tool="$test_root/isolated-dotnet-sdk.sh"
  sed 's/^TOOL_RELEASE_IDENTITY="development"$/TOOL_RELEASE_IDENTITY="v9.8.7"/' \
    "$tool" > "$stable_tool"
  chmod +x "$stable_tool"

  run env \
    HOME="$test_home" \
    PATH='' \
    http_proxy='http://127.0.0.1:1' \
    https_proxy='http://127.0.0.1:1' \
    HTTP_PROXY='http://127.0.0.1:1' \
    HTTPS_PROXY='http://127.0.0.1:1' \
    "$bash_path" "$stable_tool" --version

  [ "$status" -eq 0 ]
  [ "$output" = "isolated-dotnet-sdk v9.8.7" ]
  [ ! -e "$test_home/dotnet-sdks" ]
}

@test "persistent Main displays development identity" {
  tool_root="$test_home/dotnet-sdks"
  saved_tool="$tool_root/isolated-dotnet-sdk.sh"
  mkdir -p "$tool_root"
  cp "$tool" "$saved_tool"
  chmod +x "$saved_tool"

  run bash -c 'printf "e\n" | env HOME="$1" "$2"' _ "$test_home" "$saved_tool"

  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -cFx 'Isolated .NET SDK development (main)' || true)" -eq 1 ]
  [[ "$output" == *"What would you like to do?"* ]]
}

@test "bare SDK version remains an install selector" {
  tool_root="$test_home/dotnet-sdks"
  saved_tool="$tool_root/isolated-dotnet-sdk.sh"
  mkdir -p "$tool_root"
  cp "$tool" "$saved_tool"
  chmod +x "$saved_tool"

  run env HOME="$test_home" "$saved_tool" 'bad/version'

  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid SDK version: bad/version"* ]]
  [[ "$output" != *"isolated-dotnet-sdk development (main)"* ]]
}
