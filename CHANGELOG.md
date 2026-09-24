# Changelog

All notable changes to this project will be documented in this file.

The project follows [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-09-23

### Added

- PowerShell support for installing and managing isolated .NET SDKs on Windows.
- Bash support for installing and managing isolated .NET SDKs on Linux and macOS.
- Exact-version SDK installation under `~/dotnet-sdks` without adding the isolated SDK to `PATH`.
- Interactive install, remove, and list workflows.
- Interactive .NET channel and SDK version selection using Microsoft's published release metadata.
- Visibility into supported, development, and end-of-life .NET channels.
- Detection of SDK versions already installed through the normal system `dotnet` host or as isolated copies.
- Confirmation prompts before creating a duplicate isolated copy or removing an SDK, with `-Yes` / `--yes` support for automation.
- Build-server shutdown before removing an isolated SDK.
- Bootstrap behavior that installs or refreshes the helper script under `~/dotnet-sdks`.
- Reproducible file-based bootstrap behavior that preserves the exact invoked script, including tagged copies, while pipe-based quick starts continue to refresh from `main`.
- Nonzero exit behavior for operational failures.
- README documentation covering interactive and automation usage, directory layout, security considerations, and Microsoft references.
- MIT license.
