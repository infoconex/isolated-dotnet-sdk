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

The current checksum-policy-compliant stable release is `v0.2.0`.

Choose the guide for your supported platform; each guide contains the verified stable bootstrap command and normal usage examples:

- [Windows with PowerShell 7](docs/getting-started/windows-powershell.md)
- [Linux or macOS with Bash](docs/getting-started/linux-macos-bash.md)

After bootstrap, the saved tool starts a persistent interactive session:

```text
What would you like to do?

  I. Install an SDK
  R. Remove an isolated SDK
  L. List installed SDKs

  E. Exit

Selection:
```

Explicit Install, List, Verify, Remove, and exact-version invocations remain one-shot for scripting and automation.

## What the tool does

- **Install** an exact SDK under `~/dotnet-sdks/<version>` using Microsoft release metadata, SHA-512 payload verification, staging, exact-version verification, and promotion.
- **List** recognized Isolated SDKs first, followed by read-only System SDKs visible through the normally resolved `dotnet` host.
- **Verify** one installed isolated SDK with a read-only exact-version health check.
- **Remove** only SDKs managed under the isolated SDK root.
- **Use** an isolated SDK by invoking its version-specific `dotnet` host directly; the tool does not permanently modify normal `PATH`.

See the [command documentation](docs/commands/README.md) for the behavioral contract of each operation.

## Security and isolation at a glance

- Persistent tool and SDK state stays under the current user's `dotnet-sdks` directory rather than system-wide .NET locations.
- Isolation describes SDK installation location; it is not a security sandbox. Tool and SDK code runs with the current user's permissions and may create ordinary per-user state.
- Stable bootstrap downloads an explicitly tagged script and that release's `SHA256SUMS`, verifies the selected script before execution, and saves those verified bytes.
- SDK installation verifies the Microsoft-published SHA-512 for the exact platform archive before extraction, then separately verifies the staged host reports the requested SDK before promotion.
- GitHub, Microsoft distribution infrastructure, TLS, repository administration, and local platform tools remain trust boundaries; same-publisher checksums are integrity controls, not independent publisher signatures.

For the full model, see [Supply-chain integrity](docs/concepts/supply-chain-integrity.md) and [Filesystem safety](docs/concepts/filesystem-safety.md).

## Stable and development sources

Stable installation, update, and rollback are explicit, version-pinned operations. See [Stable bootstrap, update, and rollback](docs/releases/stable-bootstrap.md).

Mutable `main` remains available for explicit development testing, but it is not the stable installation channel and does not carry the stable-release checksum guarantee.

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
