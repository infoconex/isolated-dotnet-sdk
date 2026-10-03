# Isolated .NET SDK

Install and manage exact .NET SDK versions outside the normal system-wide .NET installation. Isolated SDKs live under your user-owned `dotnet-sdks` directory, are not added to `PATH`, and are selected explicitly when you want to use them.

This project grew out of the need to evaluate newer .NET SDKs without changing the normal development environment. For the reasoning behind the tool, testing lessons, and the role of `global.json`, see [How to Test a New .NET SDK Without Installing It System-Wide](https://coding.infoconex.com/post/2026/09/20/how-to-test-a-new-dotnet-sdk-without-installing-it-system-wide).

## Supported environments

| Platform | Supported interface |
| --- | --- |
| Windows | PowerShell 7 |
| Linux | Bash |
| macOS | Bash |

PowerShell on Linux/macOS and Bash on Windows are not supported product combinations. A system-wide `dotnet` installation is not required.

## Get started

Install or explicitly update to the latest published stable release with the command for your supported platform.

Windows / PowerShell 7:

```powershell
irm https://infoconex.github.io/isolated-dotnet-sdk/install.ps1 | iex
```

Linux or macOS / Bash:

```bash
curl -fsSL https://infoconex.github.io/isolated-dotnet-sdk/install.sh | bash
```

The small Pages-hosted bootstrap resolves the latest published stable GitHub Release, downloads that release's tagged platform script and `SHA256SUMS`, verifies the released script's SHA-256, and executes only the verified released tool. The piped bootstrap itself is trusted through HTTPS delivery from the project Pages site; it cannot verify its own bytes before execution.

For platform requirements, normal usage, pinned installation, and development-source guidance, use the supported guide:

- [Windows with PowerShell 7](docs/getting-started/windows-powershell.md)
- [Linux or macOS with Bash](docs/getting-started/linux-macos-bash.md)

For stable releases published with embedded tool identity, the saved tool shows the exact release tag. Mutable `main` shows `development (main)` in the same location:

```text
Isolated .NET SDK v1.2.3

What would you like to do?

  I. Install an SDK
  R. Remove an isolated SDK
  L. List installed SDKs

  E. Exit

Selection:
```

You can also query the tool identity directly without bootstrap, SDK discovery, network access, prompting, or mutation:

```powershell
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1" -Version
```

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" --version
```

PowerShell `-Version` and Bash `--version` identify the tool itself. For explicit SDK selection, use PowerShell `-SdkVersion <sdk-version>` or Bash `--sdk-version <sdk-version>`; both shells also accept the exact SDK version positionally. See [Tool version](docs/commands/tool-version.md).

Explicit Install, List, Verify, Remove, and exact-version invocations remain one-shot for scripting and automation.

## What the tool does

- **Install** an exact SDK under `~/dotnet-sdks/<version>` using Microsoft release metadata, SHA-512 payload verification, staging, exact-version verification, and promotion.
- **List** recognized Isolated SDKs first, followed by read-only System SDKs visible through the normally resolved `dotnet` host.
- **Verify** one installed isolated SDK with a read-only exact-version health check.
- **Remove** only SDKs managed under the isolated SDK root.
- **Identify** the running tool release/source directly or on Main without checking for updates.
- **Use** an isolated SDK by invoking its version-specific `dotnet` host directly; the tool does not permanently modify normal `PATH`.

See the [command documentation](docs/commands/README.md) for the behavioral contract of each operation.

## Security and isolation at a glance

- Persistent tool and SDK state stays under the current user's `dotnet-sdks` directory rather than system-wide .NET locations.
- Isolation describes SDK installation location; it is not a security sandbox. Tool and SDK code runs with the current user's permissions and may create ordinary per-user state.
- Latest-stable bootstrap trusts the small piped Pages entry point through HTTPS delivery, then verifies the resolved tagged release script against that release's `SHA256SUMS` before the product script executes.
- Explicit pinned stable bootstrap remains available for reproducibility and rollback and performs the same released-script checksum verification.
- SDK installation verifies the Microsoft-published SHA-512 for the exact platform archive before extraction, then separately verifies the staged host reports the requested SDK before promotion.
- GitHub, project Pages delivery, Microsoft distribution infrastructure, TLS, repository administration, and local platform tools remain trust boundaries; same-publisher checksums are integrity controls, not independent publisher signatures.

For the full model, see [Supply-chain integrity](docs/concepts/supply-chain-integrity.md) and [Filesystem safety](docs/concepts/filesystem-safety.md).

## Stable and development sources

The short Pages command selects the latest published stable release at bootstrap time. Rerunning it is the explicit update operation; the saved tool does not silently check for or install updates during normal execution.

Stable releases published with embedded tool identity report their exact tag from the tagged and saved copies. Explicit tag-pinned stable installation remains supported for reproducibility and rollback. See [Stable bootstrap, update, and rollback](docs/releases/stable-bootstrap.md).

Mutable `main` remains available for explicit development testing, but it is not the stable installation channel and does not carry the stable-release checksum guarantee. Current `main` identifies itself as development source rather than claiming the latest stable version.

Historical releases are not rewritten solely to retrofit tool-version metadata.

## Documentation

Start with the [documentation index](docs/README.md), which separates:

- supported platform getting-started guides;
- command behavior;
- project/editor guides;
- technical concepts and behavioral contracts;
- release guidance; and
- maintainer-only development, testing, dependency, issue, and release procedures.

## License

MIT
