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

For `dotnet` CLI commands, the .NET SDK muxer searches for `global.json` starting from the current working directory and walking up ancestor directories. During builds, the MSBuild project SDK resolver has its own documented search start based on the solution/project location. In either case, `global.json` constrains SDK resolution; it does not choose the `dotnet` executable for you.

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
- `paths` affects commands that engage SDK resolution, such as `dotnet build`, `dotnet run`, and `dotnet test`; it does not redirect native app hosts or framework-dependent execution such as `dotnet app.dll`.
- Absolute home-directory paths are user- and machine-specific. Avoid committing them to a shared repository unless that is an intentional team convention.
- The path names an SDK installation root, not the `dotnet` executable itself.
- Direct invocation of `~/dotnet-sdks/<version>/dotnet` (or `dotnet.exe` on Windows) remains the most explicit and broadly compatible way to guarantee which isolated host is used.

The special `$host$` entry described by Microsoft refers to the SDK location associated with the running host. It does not mean the `isolated-dotnet-sdk` home-directory root.

## VS Code with C# and C# Dev Kit

Editor behavior is owned by the editor/extensions and can change independently of this repository. The guidance in this section was verified against the current VS Code .NET Install Tool and C# Dev Kit documentation in September 2026.

### Point the .NET extensions at an existing isolated host

The current .NET Install Tool supports `dotnetAcquisitionExtension.existingDotnetPath` for telling a requesting extension which existing `dotnet` executable should run that extension's .NET components.

For the C# extension, the current extension ID is `ms-dotnettools.csharp`. For C# Dev Kit, it is `ms-dotnettools.csdevkit`. Add an entry for each extension you use.

A Windows workspace setting can look like this:

```json
{
  "dotnetAcquisitionExtension.existingDotnetPath": [
    {
      "extensionId": "ms-dotnettools.csharp",
      "path": "C:\\Users\\<user>\\dotnet-sdks\\10.0.401\\dotnet.exe"
    },
    {
      "extensionId": "ms-dotnettools.csdevkit",
      "path": "C:\\Users\\<user>\\dotnet-sdks\\10.0.401\\dotnet.exe"
    }
  ]
}
```

Use the equivalent full executable path on Linux or macOS:

| Platform | `path` value |
| --- | --- |
| Linux | `/home/<user>/dotnet-sdks/10.0.401/dotnet` |
| macOS | `/Users/<user>/dotnet-sdks/10.0.401/dotnet` |

The upstream .NET Install Tool requires the full host executable path, not the `sdk/<version>` directory. Restart VS Code after changing the setting.

For a trusted workspace, placing the setting in `.vscode/settings.json` keeps the selection scoped to that workspace. Because the path contains the local user's home directory, do not commit that file merely to share a machine-specific absolute path. User Settings are another option when a developer intentionally wants the same host preference across workspaces.

Current .NET Install Tool metadata also marks these existing-host settings as restricted in untrusted workspaces: workspace/folder values are ignored until the workspace is trusted. That is editor security behavior, not behavior controlled by `isolated-dotnet-sdk`.

The selected host must satisfy the extension's own .NET runtime requirements. If it does not, the editor extension may reject the path or acquire another compatible runtime. Do not disable that validation merely to force an incompatible isolated SDK to host the extension.

### What `existingDotnetPath` does not guarantee

The .NET Install Tool explicitly distinguishes the host used to run extension code from the .NET runtime/SDK used by your project. Setting `dotnetAcquisitionExtension.existingDotnetPath` therefore does **not** by itself guarantee that a terminal command, build task, test task, or launched application uses the isolated SDK.

Keep project selection explicit:

- use `global.json` to state the project's SDK-version contract;
- invoke `~/dotnet-sdks/<version>/dotnet` directly when a command must use the isolated host;
- optionally use .NET 10+ `sdk.paths` when its host-version and machine-specific-path tradeoffs are acceptable.

### Make VS Code build/test tasks host-explicit

VS Code task configuration supports `${userHome}` and OS-specific command overrides. A project-local `.vscode/tasks.json` can therefore invoke the isolated host without changing `PATH` or hard-coding a username:

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "dotnet: build with isolated SDK",
      "type": "process",
      "command": "${userHome}/dotnet-sdks/10.0.401/dotnet",
      "windows": {
        "command": "${userHome}\\dotnet-sdks\\10.0.401\\dotnet.exe"
      },
      "args": [
        "build"
      ],
      "options": {
        "cwd": "${workspaceFolder}"
      }
    }
  ]
}
```

Use the same pattern with `"test"`, `"run"`, or other normal .NET CLI arguments. Because the task's executable is the isolated host itself, this guarantees the task does not silently fall back to a different `dotnet` from `PATH`.

VS Code Remote, Dev Containers, WSL, and other remote extension-host scenarios have their own filesystem and extension-placement rules. This repository does not add support promises for those editor environments; use paths that exist in the environment where the relevant extension/task actually runs and follow current VS Code documentation.

## Authoritative upstream references

The version-sensitive behavior in this guide is based on current upstream documentation:

- [Microsoft `global.json` overview](https://learn.microsoft.com/en-us/dotnet/core/tools/global-json)
- [Microsoft: test prerelease .NET SDKs locally with `global.json` paths](https://learn.microsoft.com/en-us/dotnet/core/tools/test-prerelease-sdk-locally)
- [VS Code .NET Install Tool README](https://github.com/dotnet/vscode-dotnet-runtime/blob/main/vscode-dotnet-runtime-extension/README.md)
- [VS Code C# Dev Kit FAQ](https://code.visualstudio.com/docs/csharp/cs-dev-kit-faq)
- [VS Code variables reference](https://code.visualstudio.com/docs/reference/variables-reference)
- [VS Code tasks documentation](https://code.visualstudio.com/docs/debugtest/tasks)

## Related repository guidance

- [`../README.md`](../README.md) — installation, listing, verification, and direct host usage
- [`cross-platform-support.md`](cross-platform-support.md) — supported Windows/PowerShell, Linux/Bash, and macOS/Bash mappings
- [`behavioral-parity.md`](behavioral-parity.md) — shared product behavior and no-PATH isolation contract
- [`filesystem-safety.md`](filesystem-safety.md) — isolated-root ownership and filesystem safety
