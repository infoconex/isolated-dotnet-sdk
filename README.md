# Isolated .NET SDK

This repository grew out of the article [How to Test a New .NET SDK Without Installing It System-Wide](https://coding.infoconex.com/post/2026/09/20/how-to-test-a-new-dotnet-sdk-without-installing-it-system-wide).

While working through how to evaluate a newer .NET SDK without changing the normal development environment, I wanted the process to be repeatable on Windows, Linux, and macOS. What started as a few install commands turned into a small reusable tool for installing, inspecting, and removing exact SDK versions in isolation.

If you want the reasoning behind the tool, the problems we ran into while testing it, and the role `global.json` plays, start with the article.

Install and manage exact .NET SDK versions outside the normal system-wide .NET installation.

The tool keeps isolated SDKs under:

```text
Windows
C:\Users\<user>\dotnet-sdks\

Linux
/home/<user>/dotnet-sdks/

macOS
/Users/<user>/dotnet-sdks/
```

Each SDK is stored in its own version-specific directory and is not added to `PATH`.

The scripts also run from `dotnet-sdks` rather than from the repository where you invoked them. This prevents a repository-level `global.json` from unexpectedly influencing SDK operations performed by the tool.

## Quick Start

### Windows / PowerShell

Run:

```powershell
irm https://raw.githubusercontent.com/infoconex/isolated-dotnet-sdk/main/isolated-dotnet-sdk.ps1 | iex
```

### Linux / macOS

Run:

```bash
curl -fsSL https://raw.githubusercontent.com/infoconex/isolated-dotnet-sdk/main/isolated-dotnet-sdk.sh | bash
```

The first run creates `~/dotnet-sdks` if needed, saves the platform-specific tool there for future use, and then opens the interactive menu.

```text
isolated-dotnet-sdk: What would you like to do?

  1. Install an SDK
  2. Remove an isolated SDK
  3. List isolated SDKs
  4. Exit

Selection:
```

Rerunning either quick-start command refreshes the saved copy of the tool from this repository before running it.

## Interactive Install

Choosing **Install an SDK**, or explicitly running the `install` action without a version, loads Microsoft's official .NET release metadata and shows the currently supported or development channels.

A channel menu looks similar to:

```text
isolated-dotnet-sdk: Select a supported or development .NET channel:

  1. .NET 11.0  STS  Go Live      latest SDK 11.0.100-rc.1.26425.128
  2. .NET 10.0  LTS  Active       latest SDK 10.0.401
  3. .NET 9.0   STS  Maintenance  latest SDK 9.0.318
  4. .NET 8.0   LTS  Maintenance  latest SDK 8.0.425

  A. Show end-of-life channels
  M. Enter an exact SDK version manually
  Q. Cancel
```

After selecting a channel, the tool lists the SDK versions published for that channel. Versions already present on the machine are marked so you can see where they are installed.

```text
  1. 11.0.100-rc.1.26425.128 (latest, isolated)
  2. 11.0.100-preview.7.26381.103
  3. 11.0.100-preview.6.26359.118
```

The possible markers are:

- `latest` - the latest SDK identified by Microsoft's release metadata;
- `system` - already installed through the normal system `dotnet` host;
- `isolated` - already installed under `~/dotnet-sdks`.

If you select an SDK that is already installed normally, the existing confirmation still applies before creating an isolated copy.

You can also choose manual entry at either picker when you already know the exact SDK version you want.

### Start the install picker directly

PowerShell:

```powershell
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1" -Action Install
```

Bash:

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" install
```

## Install a Specific SDK

Supplying an exact SDK version bypasses the picker and goes directly to installation.

PowerShell:

```powershell
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1" `
    -Action Install `
    -Version '11.0.100-rc.1.26425.128'
```

Bash:

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" \
    install \
    11.0.100-rc.1.26425.128
```

For convenience, both tools also treat a version supplied without an action as an install request.

PowerShell:

```powershell
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1" `
    -Version '11.0.100-rc.1.26425.128'
```

Bash:

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" \
    11.0.100-rc.1.26425.128
```

If the exact SDK is already installed through the normal system `dotnet` host, the tool asks before creating a second isolated copy.

To intentionally create the isolated copy without a confirmation prompt, use the yes option.

PowerShell:

```powershell
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1" `
    -Action Install `
    -Version '10.0.401' `
    -Yes
```

Bash:

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" \
    install \
    10.0.401 \
    --yes
```

## List Isolated SDKs

PowerShell:

```powershell
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1" -Action List
```

Bash:

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" list
```

## Remove an Isolated SDK

Running `remove` without a version opens a picker containing only SDKs installed under `~/dotnet-sdks`.

PowerShell:

```powershell
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1" -Action Remove
```

Bash:

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" remove
```

You can still remove a specific version directly.

PowerShell:

```powershell
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1" `
    -Action Remove `
    -Version '11.0.100-rc.1.26425.128'
```

Bash:

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" \
    remove \
    11.0.100-rc.1.26425.128
```

PowerShell removal supports native `ShouldProcess` controls. Ordinary removal keeps the tool's existing default-no `[y/N]` confirmation. Use `-WhatIf` to preview the removal without shutting down build servers or deleting the SDK directory:

```powershell
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1" `
    -Action Remove `
    -Version '11.0.100-rc.1.26425.128' `
    -WhatIf
```

Use `-Confirm` when you want PowerShell's native confirmation prompt to be authoritative. The tool does not add its own duplicate confirmation in that case.

```powershell
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1" `
    -Action Remove `
    -Version '11.0.100-rc.1.26425.128' `
    -Confirm
```

For intentional automation, PowerShell accepts either the existing `-Yes` switch or explicit native confirmation suppression with `-Confirm:$false`:

```powershell
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1" `
    -Action Remove `
    -Version '11.0.100-rc.1.26425.128' `
    -Yes

& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1" `
    -Action Remove `
    -Version '11.0.100-rc.1.26425.128' `
    -Confirm:$false
```

`-WhatIf` always takes precedence over `-Yes`. Explicit `-WhatIf` and `-Confirm` are currently supported only for the PowerShell `Remove` action; using them with `Install` or `List` fails rather than implying unsupported risk-mitigation semantics.

After removal is approved, the PowerShell tool asks the selected isolated SDK to shut down its build servers. A nonzero shutdown result stops the operation before directory deletion. Success is reported only after the selected version directory has been removed and verified absent.

The Bash implementation keeps its existing default-no confirmation and `--yes` automation behavior.

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" \
    remove \
    11.0.100-rc.1.26425.128 \
    --yes
```

## Automation

For scripts and CI jobs, provide the action and version explicitly rather than using the interactive picker. For PowerShell removal, use `-Yes` or `-Confirm:$false` only when you intentionally approve deletion; use `-WhatIf` for a no-change preview. For Bash, use `--yes` when you intentionally want to bypass the confirmation prompt.

Operational failures return a nonzero exit status. Choosing to cancel an interactive install or removal is treated as a normal user action rather than an error.

## Directory Layout

After installing an SDK, the directory looks similar to:

```text
dotnet-sdks/
├── isolated-dotnet-sdk.ps1   # Windows
├── isolated-dotnet-sdk.sh    # Linux/macOS
├── dotnet-install.ps1        # Windows, downloaded from Microsoft
├── dotnet-install.sh         # Linux/macOS, downloaded from Microsoft
└── 11.0.100-rc.1.26425.128/
```

Only the files appropriate to the current platform will normally be present.
