# Getting started on Windows with PowerShell

This guide contains the exact PowerShell syntax for the supported Windows / PowerShell 7 product mapping. Shared command behavior is documented separately in the [command reference](../commands/README.md).

## Requirements

- Windows
- PowerShell 7
- network access when bootstrap or SDK installation downloads remote artifacts

A system-wide `dotnet` installation is not required.

## Install or update the stable tool

Install the latest published stable release, or rerun the same command later to explicitly update to the latest stable release:

```powershell
irm https://infoconex.github.io/isolated-dotnet-sdk/install.ps1 | iex
```

The Pages-hosted bootstrap resolves the latest published stable GitHub Release, downloads that release's tagged `isolated-dotnet-sdk.ps1` and `SHA256SUMS`, verifies the released script's SHA-256, and executes only the verified released script. The piped bootstrap itself is trusted through HTTPS delivery from the project Pages site and cannot verify its own bytes before execution.

The verified released file is saved as:

```text
$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1
```

Normal execution of that saved tool does not auto-update. For an explicit pinned version, reproducible installation, or rollback, see [Stable bootstrap, update, and rollback](../releases/stable-bootstrap.md).

## Identify the tool version

```powershell
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1" -Version
```

Stable releases published with embedded identity report their exact release tag. Mutable `main` reports `isolated-dotnet-sdk development (main)` instead of claiming a stable version. The query exits without bootstrap, network access, SDK discovery, prompting, or mutation.

`-Version` identifies the `isolated-dotnet-sdk` tool. `-SdkVersion <sdk-version>` explicitly selects the .NET SDK used by Install, Verify, and Remove, and the same exact SDK version can be supplied positionally. See [Tool version](../commands/tool-version.md).

## Start an interactive session

```powershell
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1"
```

Main displays the same stable/development tool identity near the top. The persistent session uses `I` for Install, `R` for Remove, `L` for List, `V` for Verify, and `E` for Exit. See [Interactive mode](../commands/interactive.md) for navigation semantics.

## Install an SDK

Open the interactive install picker once and exit when it completes:

```powershell
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1" -Action Install
```

Install a known exact version directly:

```powershell
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1" `
    -Action Install `
    -SdkVersion '10.0.401'
```

Without `-Action`, the explicit SDK selector implies Install:

```powershell
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1" -SdkVersion '10.0.401'
```

The equivalent positional convenience form is also supported:

```powershell
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1" '10.0.401'
```

If a matching System SDK already exists, Install normally asks before creating an isolated copy. Use `-Yes` only when that confirmation should be approved automatically:

```powershell
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1" `
    -Action Install `
    -SdkVersion '10.0.401' `
    -Yes
```

See [Install](../commands/install.md) for the behavioral and integrity contract.

## List installed SDKs

```powershell
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1" -Action List
```

List shows Isolated SDKs first and read-only System SDKs second. See [List](../commands/list.md).

## Verify an isolated SDK

Run Verify directly for a known exact isolated SDK:

```powershell
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1" `
    -Action Verify `
    -SdkVersion '10.0.401'
```

Verify is read-only. The persistent Main menu also exposes `V` so you can choose from installed isolated SDKs; System SDKs are not offered as Verify targets. See [Verify](../commands/verify.md).

## Use an isolated SDK

Invoke the selected version's host directly:

```powershell
& "$HOME\dotnet-sdks\10.0.401\dotnet.exe" --version
& "$HOME\dotnet-sdks\10.0.401\dotnet.exe" --info
```

Normal .NET CLI arguments such as `restore`, `build`, `test`, and `run` work through that same host path. Nothing in this pattern adds the isolated SDK to `PATH`.

For `global.json`, VS Code, and project-level workflows, see [Project and editor use](../guides/project-editor-usage.md).

## Remove an isolated SDK

Open the removal picker:

```powershell
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1" -Action Remove
```

Remove one exact isolated SDK:

```powershell
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1" `
    -Action Remove `
    -SdkVersion '10.0.401'
```

Preview the PowerShell removal operation without shutting down build servers or deleting the SDK:

```powershell
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1" `
    -Action Remove `
    -SdkVersion '10.0.401' `
    -WhatIf
```

PowerShell also supports native `-Confirm`, explicit `-Confirm:$false`, and the tool's `-Yes` automation switch for Remove. See [Remove](../commands/remove.md) for shared behavior and the [PowerShell removal contract](../contracts/powershell-removal.md) for the native `ShouldProcess` rules.

## Development source

For explicit development testing only, mutable `main` can be piped into PowerShell:

```powershell
irm https://raw.githubusercontent.com/infoconex/isolated-dotnet-sdk/main/isolated-dotnet-sdk.ps1 | iex
```

This is not a stable installation command. It consumes mutable source and does not receive the stable-release checksum guarantee. Once saved, that development copy reports `isolated-dotnet-sdk development (main)` through `-Version` and on Main.

## Next steps

- [Commands](../commands/README.md)
- [Project and editor use](../guides/project-editor-usage.md)
- [Stable bootstrap, update, and rollback](../releases/stable-bootstrap.md)
- [Cross-platform support](../concepts/cross-platform-support.md)
- [Supply-chain integrity](../concepts/supply-chain-integrity.md)
