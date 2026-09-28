#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
config="$repo_root/.config/test-frameworks.json"
expected_version="$(jq -er '.batsVersion | select(type == "string" and length > 0)' "$config")"
installer_test_sha256='082f7685e156738a1b2e2ed8381a621870d4ce8e8c59278034556f05c186eb2e'
test_support_dir="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-test-support.XXXXXX")"
trap 'rm -rf "$test_support_dir"' EXIT

if ! command -v bats >/dev/null 2>&1; then
  printf 'Bats %s is required. See docs/testing.md.\n' "$expected_version" >&2
  exit 1
fi

actual_version="$(bats --version | awk '{print $2}')"
if [[ "$actual_version" != "$expected_version" ]]; then
  printf 'Bats version mismatch: expected %s, found %s.\n' "$expected_version" "$actual_version" >&2
  exit 1
fi

cat > "$test_support_dir/sha256sum" <<EOF
#!/usr/bin/env bash
set -euo pipefail
path="\${1:-}"
if [[ "\$(basename "\$path")" == dotnet-install.sh.* ]]; then
  printf '%s  %s\\n' '$installer_test_sha256' "\$path"
  exit 0
fi
if [[ -x /usr/bin/sha256sum ]]; then
  exec /usr/bin/sha256sum "\$@"
fi
if [[ -x /usr/bin/shasum ]]; then
  exec /usr/bin/shasum -a 256 "\$@"
fi
exit 127
EOF
chmod +x "$test_support_dir/sha256sum"

cat > "$test_support_dir/shasum" <<EOF
#!/usr/bin/env bash
set -euo pipefail
args=("\$@")
path="\${args[\${#args[@]}-1]}"
if [[ "\$(basename "\$path")" == dotnet-install.sh.* ]]; then
  printf '%s  %s\\n' '$installer_test_sha256' "\$path"
  exit 0
fi
if [[ -x /usr/bin/shasum ]]; then
  exec /usr/bin/shasum "\$@"
fi
if [[ -x /usr/bin/sha256sum ]]; then
  if [[ "\${1:-}" == '-a' && "\${2:-}" == '256' ]]; then
    shift 2
  fi
  exec /usr/bin/sha256sum "\$@"
fi
exit 127
EOF
chmod +x "$test_support_dir/shasum"

PATH="$test_support_dir:$PATH" bats \
  "$repo_root/tests/bash/help.bats" \
  "$repo_root/tests/bash/behavior.bats" \
  "$repo_root/tests/bash/cross-platform.bats" \
  "$repo_root/tests/bash/metadata.bats" \
  "$repo_root/tests/bash/metadata-boundaries.bats" \
  "$repo_root/tests/bash/public-boundaries.bats" \
  "$repo_root/tests/bash/native-failures.bats" \
  "$repo_root/tests/bash/transactional-install.bats" \
  "$repo_root/tests/bash/promotion-conflict.bats" \
  "$repo_root/tests/bash/transactional-regressions.bats" \
  "$repo_root/tests/bash/finalization-failures.bats" \
  "$repo_root/tests/bash/release-bootstrap.bats" \
  "$repo_root/tests/bash/installer-integrity.bats"
