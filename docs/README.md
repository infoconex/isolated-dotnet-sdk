# Documentation

Use this index to find the documentation for the task or audience you care about. The root [README](../README.md) is intentionally a project overview; detailed guidance lives here.

## Get started

Choose the supported platform you are using:

- [Windows with PowerShell 7](getting-started/windows-powershell.md)
- [Linux or macOS with Bash](getting-started/linux-macos-bash.md)

The [getting-started index](getting-started/README.md) summarizes the supported platform mappings and prerequisites.

## Commands

The command pages describe shared product behavior without repeating shell-specific syntax:

- [Install](commands/install.md) — install an exact SDK under the isolated SDK root
- [List](commands/list.md) — show Isolated SDKs and read-only System SDKs
- [Verify](commands/verify.md) — health-check one installed isolated SDK
- [Remove](commands/remove.md) — remove an SDK managed under the isolated root
- [Interactive mode](commands/interactive.md) — persistent sessions, navigation, channel selection, and SDK selection

See the [command index](commands/README.md) for the command/documentation boundary.

## Guides

- [Project and editor use](guides/project-editor-usage.md) — `global.json`, direct isolated-host use, VS Code, and project-local workflows

## Concepts

Use these documents to understand the product's deeper technical model:

- [Concepts index](concepts/README.md)
- [Cross-platform support](concepts/cross-platform-support.md)
- [Filesystem safety](concepts/filesystem-safety.md)
- [SDK discovery and release metadata](concepts/sdk-discovery.md)
- [Bootstrap source preservation and reproducibility](concepts/bootstrap-reproducibility.md)
- [Supply-chain integrity and trust boundaries](concepts/supply-chain-integrity.md)

## Behavioral contracts

These documents define detailed implementation-independent behavior and intentional shell-specific differences:

- [Contracts index](contracts/README.md)
- [PowerShell and Bash behavioral parity](contracts/behavioral-parity.md)
- [Native-command failure boundaries](contracts/native-command-failures.md)
- [PowerShell removal contract](contracts/powershell-removal.md)

## Releases

- [Release documentation index](releases/README.md)
- [Stable bootstrap, update, and rollback](releases/stable-bootstrap.md)
- [v0.1.0 historical release notes](releases/history/v0.1.0.md)
- [v0.1.0 historical release checklist](releases/history/v0.1.0-checklist.md)

The current checksum-policy-compliant stable release is `v0.2.0`.

## Maintainer documentation

Repository development and delivery documentation is intentionally separated from user guidance:

- [Maintainer index](maintainers/README.md)
- [Testing and validation](maintainers/testing/README.md)
- [Coding and naming consistency](maintainers/development/coding-consistency.md)
- [Source formatting](maintainers/development/source-formatting.md)
- [Dependency update monitoring](maintainers/dependencies/dependency-update-monitoring.md)
- [Stable release publication and verification](maintainers/releases/release-process.md)
- [Issue execution workflow](maintainers/issues/issue-workflow.md)
- [Issue and pull request conventions](maintainers/issues/issue-conventions.md)

## Documentation authority

When documents overlap, use the most focused document for the question at hand:

- platform getting-started guides own exact shell syntax and copy/paste examples;
- command pages own shared command semantics;
- concept and contract pages own deeper technical guarantees and boundaries;
- release docs own stable bootstrap/update/rollback policy;
- maintainer docs own repository development, testing, issue, and publication procedures.

Compatibility pages may remain at selected historical paths when existing CLI help or published release material points there. Those pages redirect readers to the canonical documents above and are not separate authorities.