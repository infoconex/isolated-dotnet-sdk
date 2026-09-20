# Isolated .NET SDK

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
$d = Join-Path $HOME 'dotnet-sdks'; New-Item -ItemType Directory -Path $d -Force | Out-Null; Invoke-WebRequest 'https://raw.githubusercontent.com/infoconex/isolated-dotnet-sdk/main/isolated-dotnet-sdk.ps1' -OutFile (Join-Path $d 'isolated-dotnet-sdk.ps1'); & (Join-Path $d 'isolated-dotnet-sdk.ps1')
```

The PowerShell quick-start downloads the script to its permanent location first, then runs that file normally. It intentionally avoids `Invoke-Expression`, so the tool does not add or modify parameter variables in the caller's PowerShell scope.

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

Removal first asks the isolated SDK to shut down its MSBuild and compiler build servers, then removes only that version directory. Removal defaults to no at the confirmation prompt.

For automation, both implementations support a yes option.

PowerShell:

```powershell
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1" `
    -Action Remove `
    -Version '11.0.100-rc.1.26425.128' `
    -Yes
```

Bash:

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" \
    remove \
    11.0.100-rc.1.26425.128 \
    --yes
```

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

## Why This Exists

Installing a preview or release-candidate SDK system-wide is not always necessary when evaluating a .NET upgrade.

This tool provides a repeatable way to install an exact SDK version in a separate directory, invoke it explicitly, and remove it later without changing the SDKs exposed by the normal system `dotnet` installation.

It is isolation of the SDK installation, not a full sandbox. The .NET CLI can still create normal per-user state during first-time use, such as development certificates or telemetry configuration.

## Microsoft Release Metadata

The interactive install picker reads Microsoft's published .NET release metadata from:

```text
https://builds.dotnet.microsoft.com/dotnet/release-metadata/releases-index.json
```

The release index identifies each .NET channel and links to the detailed release metadata used to enumerate exact SDK versions. Explicit-version installs do not require the picker and bypass this metadata lookup.

## Microsoft References

- [.NET install scripts](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-install-script)
- [Test prerelease .NET SDKs locally](https://learn.microsoft.com/en-us/dotnet/core/tools/test-prerelease-sdk-locally)
- [`dotnet build-server`](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-build-server)
- [`global.json` overview](https://learn.microsoft.com/en-us/dotnet/core/tools/global-json)
- [.NET release metadata](https://github.com/dotnet/core/tree/main/release-notes)

## Security Note

The quick-start commands download and execute the current script from this repository's `main` branch. Review the script first if you prefer not to execute remote code directly.

## License

MIT
