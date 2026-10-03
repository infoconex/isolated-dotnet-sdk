# Getting started on Linux or macOS with Bash

This guide contains the exact Bash syntax for the supported Linux/Bash and macOS/Bash product mappings. Shared command behavior is documented separately in the [command reference](../commands/README.md).

## Requirements

- Linux or macOS
- Bash
- standard shell utilities used by the tool, including `curl`, `awk`, `grep`, `sed`, `tr`, `mktemp`, `chmod`, `mv`, `rm`, and `tar`
- a SHA-256 utility for stable tool bootstrap: `sha256sum` where available or `shasum -a 256`
- a SHA-512 utility for SDK payload verification: `sha512sum` where available or `shasum -a 512`
- network access when bootstrap or SDK installation downloads remote artifacts

A system-wide `dotnet` installation is not required.

## Install the stable tool

The current checksum-policy-compliant stable release is `v0.2.0`. Stable bootstrap explicitly downloads the tagged Bash source and the release's `SHA256SUMS`, verifies the script's SHA-256, and executes only the verified temporary file.

```bash
release='v0.2.0'
temp="$(mktemp "${TMPDIR:-/tmp}/isolated-dotnet-sdk.XXXXXX.sh")"
checksums="$(mktemp "${TMPDIR:-/tmp}/isolated-dotnet-sdk.XXXXXX.SHA256SUMS")"
trap 'rm -f "$temp" "$checksums"' EXIT

curl -fsSL "https://raw.githubusercontent.com/infoconex/isolated-dotnet-sdk/$release/isolated-dotnet-sdk.sh" -o "$temp"
curl -fsSL "https://github.com/infoconex/isolated-dotnet-sdk/releases/download/$release/SHA256SUMS" -o "$checksums"

expected="$(awk '$2 == "isolated-dotnet-sdk.sh" && $1 ~ /^[0-9a-fA-F]{64}$/ { print tolower($1) }' "$checksums")"
[[ "$expected" =~ ^[0-9a-f]{64}$ ]] || {
    printf '%s\n' 'SHA256SUMS does not contain exactly one valid isolated-dotnet-sdk.sh entry.' >&2
    exit 1
}

if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$temp" | awk '{print tolower($1)}')"
elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$temp" | awk '{print tolower($1)}')"
else
    printf '%s\n' 'SHA-256 verification requires sha256sum or shasum.' >&2
    exit 1
fi

[[ "$actual" == "$expected" ]] || {
    printf 'Checksum verification failed for isolated-dotnet-sdk.sh. Expected %s, got %s.\n' "$expected" "$actual" >&2
    exit 1
}

chmod +x "$temp"
"$temp"
```

The verified file is saved as:

```text
$HOME/dotnet-sdks/isolated-dotnet-sdk.sh
```

Normal execution of that saved tool does not auto-update. See [Stable bootstrap, update, and rollback](../releases/stable-bootstrap.md) before changing release tags.

## Start an interactive session

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh"
```

The persistent session uses `I` for Install, `R` for Remove, `L` for List, and `E` for Exit. See [Interactive mode](../commands/interactive.md) for navigation semantics.

## Install an SDK

Open the interactive install picker once and exit when it completes:

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" install
```

Install a known exact version directly:

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" install 10.0.401
```

A bare version is the Install convenience form:

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" 10.0.401
```

If a matching System SDK already exists, Install normally asks before creating an isolated copy. Use `--yes` only when that confirmation should be approved automatically:

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" install 10.0.401 --yes
```

See [Install](../commands/install.md) for the behavioral and integrity contract.

## List installed SDKs

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" list
```

List shows Isolated SDKs first and read-only System SDKs second. See [List](../commands/list.md).

## Verify an isolated SDK

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" verify 10.0.401
```

Verify is read-only and direct-command-only. See [Verify](../commands/verify.md).

## Use an isolated SDK

Invoke the selected version's host directly:

```bash
"$HOME/dotnet-sdks/10.0.401/dotnet" --version
"$HOME/dotnet-sdks/10.0.401/dotnet" --info
```

Normal .NET CLI arguments such as `restore`, `build`, `test`, and `run` work through that same host path. Nothing in this pattern adds the isolated SDK to `PATH`.

For `global.json`, VS Code, and project-level workflows, see [Project and editor use](../guides/project-editor-usage.md).

## Remove an isolated SDK

Open the removal picker:

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" remove
```

Remove one exact isolated SDK:

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" remove 10.0.401
```

For intentional automation, approve the tool-owned default-no confirmation with `--yes`:

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" remove 10.0.401 --yes
```

Bash does not emulate PowerShell's `-WhatIf` or `-Confirm` facilities. See [Remove](../commands/remove.md) for the shared behavior.

## Development source

For explicit development testing only, mutable `main` can be piped into Bash:

```bash
curl -fsSL https://raw.githubusercontent.com/infoconex/isolated-dotnet-sdk/main/isolated-dotnet-sdk.sh | bash
```

This is not a stable installation command. It consumes mutable source and does not receive the stable-release checksum guarantee.

## Next steps

- [Commands](../commands/README.md)
- [Project and editor use](../guides/project-editor-usage.md)
- [Stable bootstrap, update, and rollback](../releases/stable-bootstrap.md)
- [Cross-platform support](../concepts/cross-platform-support.md)
- [Supply-chain integrity](../concepts/supply-chain-integrity.md)
