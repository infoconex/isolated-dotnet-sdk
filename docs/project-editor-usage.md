# Project and editor use of isolated SDKs

`isolated-dotnet-sdk` deliberately leaves the normal machine `PATH` unchanged. Installing an SDK under `~/dotnet-sdks/<version>` therefore does not make terminals, editors, or other tools automatically use it.

The reliable model is to keep two decisions separate:

1. **Which `dotnet` host is executed?** Use the version-specific isolated host when you need to guarantee isolation.
2. **Which SDK may that host select?** Use `global.json` when the project should require a particular SDK version or roll-forward policy.

A `global.json` version by itself answers the second question. It does not redirect a different system or editor-launched `dotnet` executable to the isolated host.

The examples below use `10.0.401`. Replace it with the exact SDK version installed for your project.

## Run a project with the isolated host

The version-specific host paths are:

| Platform | Isolated host |
| --- | --- |
| Windows | `C:\Users\<user>\dotnet-sdks\10.0.401\dotnet.exe` |
| Linux | `/home/<user>/dotnet-sdks/10.0.401/dotnet` |
| macOS | `/Users/<user>/dotnet-sdks/10.0.401/dotnet` |

From the project or repository directory, invoke that host directly and pass normal .NET CLI arguments.

PowerShell on Windows:

```powershell
& "$HOME\dotnet-sdks\10.0.401\dotnet.exe" --version
& "$HOME\dotnet-sdks\10.0.401\dotnet.exe" restore
& "$HOME\dotnet-sdks\10.0.401\dotnet.exe" build
& "$HOME\dotnet-sdks\10.0.401\dotnet.exe" test
```

Bash on Linux or macOS:

```bash
"$HOME/dotnet-sdks/10.0.401/dotnet" --version
"$HOME/dotnet-sdks/10.0.401/dotnet" restore
"$HOME/dotnet-sdks/10.0.401/dotnet" build
"$HOME/dotnet-sdks/10.0.401/dotnet" test
```

This does not modify `PATH`. Scripts and automation can use the same explicit-host pattern.

## Pin the project SDK with `global.json`

Place `global.json` at the repository or solution root when the project should require an exact SDK. For an exact `10.0.401` requirement:

```json
{
  "sdk": {
    "version": "10.0.401",
    "rollForward": "disable"
  }
}
```

Microsoft's current `global.json` contract requires a full SDK version. `"rollForward": "disable"` prevents SDK roll-forward, so the requested version must be available to the host that is executing the command.

With the isolated host selected explicitly, run from the project tree as usual:

PowerShell on Windows:

```powershell
& "$HOME\dotnet-sdks\10.0.401\dotnet.exe" build
```

Bash on Linux or macOS:

```bash
"$HOME/dotnet-sdks/10.0.401/dotnet" build
```

The .NET SDK muxer searches for `global.json` starting from the current working directory and walking up ancestor directories. The file constrains SDK resolution for the host that was launched; it does not choose that executable for you.

### Repositories that already contain `global.json`

Do not overwrite an existing repository-level `global.json` merely to use an isolated SDK. Treat the existing file as part of the project's SDK contract first.

- If it already requires the isolated version you installed, invoke that version's isolated host directly.
- If it requires a different exact version, install that version in isolation and invoke its host, or intentionally change the project's `global.json` as a separate project decision.
- If it allows roll-forward, remember that SDK selection still occurs among SDKs discoverable to the host that was actually launched.

A mismatch should be allowed to fail visibly rather than being hidden by a permanent machine-wide `PATH` change.

## Optional: .NET 10+ `sdk.paths`

Starting with the .NET 10 SDK/host, `global.json` can explicitly add SDK search locations with `sdk.paths`. This can make a custom SDK root discoverable to a .NET 10+ system or editor-launched host without changing machine-wide `PATH`.

For example, a Windows-only local configuration could be:

```json
{
  "sdk": {
    "version": "10.0.401",
    "rollForward": "disable",
    "paths": [
      "C:\\Users\\<user>\\dotnet-sdks\\10.0.401"
    ]
  }
}
```

Linux:

```json
{
  "sdk": {
    "version": "10.0.401",
    "rollForward": "disable",
    "paths": [
      "/home/<user>/dotnet-sdks/10.0.401"
    ]
  }
}
```

macOS:

```json
{
  "sdk": {
    "version": "10.0.401",
    "rollForward": "disable",
    "paths": [
      "/Users/<user>/dotnet-sdks/10.0.401"
    ]
  }
}
```

Use this deliberately:

- `paths` requires a .NET 10 or later host. Older hosts ignore the property and fall back to their normal SDK discovery behavior.
- Absolute home-directory paths are user- and machine-specific. Avoid committing them to a shared repository unless that is an intentional team convention.
- The path names an SDK installation root, not the `dotnet` executable itself.
- Direct invocation of `~/dotnet-sdks/<version>/dotnet` (or `dotnet.exe` on Windows) remains the most explicit and broadly compatible way to guarantee which isolated host is used.

The special `$host$` entry described by Microsoft refers to the SDK location associated with the running host. It does not mean the `isolated-dotnet-sdk` home-directory root.

## Authoritative .NET references

The `global.json` behavior in this guide is based on current Microsoft documentation:

- [`global.json` overview](https://learn.microsoft.com/en-us/dotnet/core/tools/global-json)
- [Test prerelease .NET SDKs locally with `global.json` paths](https://learn.microsoft.com/en-us/dotnet/core/tools/test-prerelease-sdk-locally)

Editor-specific configuration is version-sensitive and is covered separately below as it is added to this guide.

## Related repository guidance

- [`../README.md`](../README.md) — installation, listing, verification, and direct host usage
- [`cross-platform-support.md`](cross-platform-support.md) — supported Windows/PowerShell, Linux/Bash, and macOS/Bash mappings
- [`behavioral-parity.md`](behavioral-parity.md) — shared product behavior and no-PATH isolation contract
- [`filesystem-safety.md`](filesystem-safety.md) — isolated-root ownership and filesystem safety
