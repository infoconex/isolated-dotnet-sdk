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

## Install or update the stable tool

Install the latest published stable release, or rerun the same command later to explicitly update to the latest stable release:

```bash
curl -fsSL https://infoconex.github.io/isolated-dotnet-sdk/install.sh | bash
```

The Pages-hosted bootstrap resolves the latest published stable GitHub Release, downloads that release's tagged `isolated-dotnet-sdk.sh` and `SHA256SUMS`, verifies the released script's SHA-256, and executes only the verified released script. The piped bootstrap itself is trusted through HTTPS delivery from the project Pages site and cannot verify its own bytes before execution.

The verified released file is saved as:

```text
$HOME/dotnet-sdks/isolated-dotnet-sdk.sh
```

Normal execution of that saved tool does not auto-update. For an explicit pinned version, reproducible installation, or rollback, see [Stable bootstrap, update, and rollback](../releases/stable-bootstrap.md).

## Identify the tool version

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" --version
```

Stable releases published with embedded identity report their exact release tag. Mutable `main` reports `isolated-dotnet-sdk development (main)` instead of claiming a stable version. The query exits without bootstrap, network access, SDK discovery, prompting, or mutation.

This identifies the `isolated-dotnet-sdk` tool itself. `--sdk-version <sdk-version>` explicitly selects a .NET SDK, and a bare value such as `10.0.401` is the equivalent positional selector. See [Tool version](../commands/tool-version.md).

## Start an interactive session

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh"
```

Main displays the same stable/development tool identity near the top. The persistent session uses `I` for Install, `R` for Remove, `L` for List, `V` for Verify, `A` for Audit, and `E` for Exit. See [Interactive mode](../commands/interactive.md) for navigation semantics.

## Install an SDK

Open the interactive install picker once and exit when it completes:

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" install
```

Install a known exact version directly with the explicit SDK selector:

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" install --sdk-version 10.0.401
```

Without an explicit action, `--sdk-version` implies Install:

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" --sdk-version 10.0.401
```

The equivalent positional convenience form is also supported:

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

## Audit installed SDKs

Run the explicit online, read-only servicing and lifecycle assessment:

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" audit
```

Audit reports Isolated SDKs and System SDKs separately and uses current Microsoft release metadata. It does not install, remove, or repair SDKs. See [Audit](../commands/audit.md).

## Verify an isolated SDK

Run Verify directly for a known exact isolated SDK:

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" verify 10.0.401
```

Verify is read-only. The persistent Main menu also exposes `V` so you can choose from installed isolated SDKs; System SDKs are not offered as Verify targets. See [Verify](../commands/verify.md).

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

This is not a stable installation command. It consumes mutable source and does not receive the stable-release checksum guarantee. Once saved, that development copy reports `isolated-dotnet-sdk development (main)` through `--version` and on Main.

## Next steps

- [Commands](../commands/README.md)
- [Project and editor use](../guides/project-editor-usage.md)
- [Stable bootstrap, update, and rollback](../releases/stable-bootstrap.md)
- [Cross-platform support](../concepts/cross-platform-support.md)
- [Supply-chain integrity](../concepts/supply-chain-integrity.md)
