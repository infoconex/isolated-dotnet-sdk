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
irm https://raw.githubusercontent.com/infoconex/isolated-dotnet-sdk/main/isolated-dotnet-sdk.ps1 | iex
```

The first run:

1. Creates `$HOME\dotnet-sdks` if needed.
2. Saves `isolated-dotnet-sdk.ps1` there for future use.
3. Prompts for the .NET SDK version to install.
4. Downloads Microsoft's `dotnet-install.ps1` script.
5. Installs the exact SDK version without adding it to `PATH`.
6. Verifies the isolated installation.

### Linux / macOS

Run:

```bash
curl -fsSL https://raw.githubusercontent.com/infoconex/isolated-dotnet-sdk/main/isolated-dotnet-sdk.sh | bash
```

The first run:

1. Creates `~/dotnet-sdks` if needed.
2. Saves `isolated-dotnet-sdk.sh` there for future use.
3. Makes the saved script executable.
4. Prompts for the .NET SDK version to install.
5. Downloads Microsoft's `dotnet-install.sh` script.
6. Installs the exact SDK version without adding it to `PATH`.
7. Verifies the isolated installation.

## Install an SDK

After the tool is installed, you can run it directly.

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

Removal first asks the isolated SDK to shut down its MSBuild and compiler build servers, then removes only that version directory.

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

Removal defaults to no at the confirmation prompt. For automation, both implementations support a yes option.

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

## Microsoft References

- [.NET install scripts](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-install-script)
- [Test prerelease .NET SDKs locally](https://learn.microsoft.com/en-us/dotnet/core/tools/test-prerelease-sdk-locally)
- [`dotnet build-server`](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-build-server)
- [`global.json` overview](https://learn.microsoft.com/en-us/dotnet/core/tools/global-json)

## Security Note

The quick-start commands download and execute the current script from this repository's `main` branch. Review the script first if you prefer not to execute remote code directly.

## License

MIT
