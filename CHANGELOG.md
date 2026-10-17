# Changelog

All notable changes to this project will be documented in this file.

The project follows [Semantic Versioning](https://semver.org/).

## [0.4.0] - 2026-10-17

Published on October 17, 2026. See the [official v0.4.0 GitHub Release](https://github.com/infoconex/isolated-dotnet-sdk/releases/tag/v0.4.0) for its immutable tagged source, notes, and published checksums.

### Added

- Detailed read-only Verify reports for one exact isolated SDK, combining local host/version/origin proof with optional release/lifecycle metadata and installed-component information. Original 1.x and early 2.x hosts use their exact SDK Base Path when modern inventory commands are unsupported.
- Historical SDK installation compatibility, including legacy archive naming, exact SDK-to-release-channel mappings, and published SHA-256 verification for qualifying .NET 1.x artifacts; modern SDK artifacts still require SHA-512.
- All published prerelease SDK choices displayed by default for Preview/RC channels; stable channels retain their compact SDK picker and expanded Show All option.
- Confirmed removal candidates for incomplete or partially removed isolated SDK version directories, permitting another approved attempt after locks are cleared.

### Changed

- Audit now displays aligned, newest-first Isolated/System SDK inventories with release type, lifecycle/status, optional release/EOS dates, and concise `Update -> <version>` servicing information.
- Interactive Install distinguishes already-installed isolated versus system SDKs, omits successful temporary staging details, and reuses loaded channel metadata when returning to the same picker.
- Terminal-capable interactive sessions clear previous menus at navigation and operation boundaries, start cleared views on the first visible row, and retain results until Enter acknowledgement. Redirected/noninteractive execution continues without clearing or pausing.
- Remove automatically handles narrowly verified historical build-server shutdown incompatibility after normal confirmation, with explicit SDK-local Roslyn shutdown where required. Real supported shutdown failures remain blocking.
- Documentation more precisely describes Install, List, Audit, Verify and Remove boundaries, historical SDK compatibility, troubleshooting, stable-release trust and PowerShell/Bash parity.

### Fixed

- Exact isolated SDK origin proof now also protects Install; an unrelated system SDK or mismatched origin does not count as an existing healthy isolated installation.
- Safer removal staging/rename and recovery: incomplete or locked removals are reported rather than counted as success; remaining confirmed removal state can be retried.
- Consistent .NET channel and SDK version ordering, clearer Verify result spacing, and correct terminal-clearing behavior.
- Hardened release publication failure/cleanup regression tests to preserve fail-closed publication checks.

### Reliability and validation

- Reduced redundant PowerShell behavioral-test setup by 85 child PowerShell launches without dropping required subprocess scenarios; isolated file-bootstrap testing no longer depends on the runner's live SDK inventory.
- Cancel superseded Validate pull-request runs only for the same PR without interrupting unrelated PRs or release/main push validation.
- Expanded Windows/PowerShell and Linux/macOS/Bash coverage of historical SDKs, removals, release publication failures, integrity and end-to-end behavior.
- Experimental timing instrumentation and an unproven parallel test runner remain deferred under issue #181 and are **not** included in v0.4.0.

## [0.3.0] - 2026-10-05

### Added

- Verified latest-stable bootstrap through short Pages-hosted PowerShell and Bash commands that resolve the latest published stable release, acquire the tagged product script and release `SHA256SUMS`, verify the selected script, and execute only the verified tagged bytes.
- Explicit tool release/source identity through PowerShell `-Version` and Bash `--version`, with the same identity displayed in the persistent Main menu. Stable releases report their exact tag while mutable `main` reports development identity.
- Interactive access to the existing read-only Verify operation for exact-version health checks of installed isolated SDKs.
- A read-only Audit operation that assesses both Isolated SDKs and read-only System SDKs against current Microsoft release metadata for servicing and lifecycle state, including current/update status, security-release metadata, maintenance, preview/Go Live, end-of-life, unknown-channel, and newer-than-known-metadata cases.
- Independently rerunnable public-release verification covering the published tag, GitHub Release metadata, checksum asset, supported stable-bootstrap paths, saved-tool byte identity, and embedded stable tool identity.
- A navigable documentation hierarchy with task-focused Getting Started, Commands, Guides, Concepts, Contracts, Releases, and Maintainer sections, plus focused Audit, tool-version, interactive, and stable-bootstrap guidance.

### Changed

- Stable release publication now derives a release-only commit from the already-validated `main` state, stamps one explicit stable tag into both product scripts, generates checksums from those exact release bytes, verifies draft release state before publication, and reads the public release back after publication.
- Latest stable is now the normal documented installation/update path; pinned checksum-verified stable bootstrap remains available for reproducibility, controlled rollout, and rollback.
- Release documentation is version controlled as a coordinated changelog entry, exact GitHub Release body, user-facing history page, Releases overview entry, and Pages navigation entry.
- Documentation and command terminology were reorganized around user tasks and durable product contracts while keeping mutable `main` explicitly separate from stable release identity.

### Fixed

- Removed the GNU awk warning from Bash release-index parsing while preserving portable behavior across Linux and macOS.
- Hardened latest-stable bootstrap and E2E network acquisition against transient curl receive failures with bounded retries.
- Preserved real curl HTTP failures as terminal failures rather than misclassifying them as retryable receive failures.
- Silenced unavailable controlling-terminal probe diagnostics and preserved the selected SDK version in relevant metadata error messages.

### Security

- Latest-stable bootstrap verifies the resolved tagged PowerShell or Bash product script against the selected release's `SHA256SUMS` before the product script executes.
- Stable release verification independently confirms that public tagged source, checksum material, saved bootstrap result, and embedded release identity agree on supported platform paths.
- The checksum and tagged product script remain within the project's GitHub trust domain and are not presented as an independent publisher signature.

## [0.2.0] - 2026-10-02

### Added

- Checksum-verifying stable bootstrap for explicitly selected release tags, with deterministic `SHA256SUMS` covering both platform scripts.
- A read-only `Verify` / `verify` action that checks one exact isolated SDK installation without repairing or modifying it.
- Installed-SDK listing that separates tool-managed **Isolated SDKs** from read-only **System SDKs** reported by the normally resolved `dotnet` host.
- Persistent interactive sessions with Main, Back, global Exit, manual exact-version entry, compact SDK version selection, and access to older servicing versions on demand.
- Cross-platform behavioral, boundary, integrity, static-analysis, and real end-to-end validation using Pester and Bats-core across the supported Windows, Linux, and macOS mappings.
- A manually triggered, fail-closed stable-release workflow that verifies the exact release commit and checksums before creating and publishing a GitHub Release.
- Documentation for project/editor usage, release/bootstrap policy, supply-chain trust boundaries, filesystem safety, behavioral parity, interactive sessions, validation, and operational troubleshooting.

### Changed

- SDK installation now resolves the exact platform archive from Microsoft's release metadata, verifies the published SHA-512 before extraction, stages the installation transactionally, verifies the requested exact SDK version, and only then promotes it into the isolated root.
- The product install path no longer downloads or executes Microsoft's `dotnet-install` helper scripts.
- Interactive presentation and navigation were simplified and polished, including mnemonic Main-menu commands, clearer spacing, target-focused install status, and consistent PowerShell/Bash output.
- Bash SDK version ordering was optimized while preserving cross-shell ordering parity.
- Repository validation was made more deterministic with pinned dependencies, static analysis, reusable setup, caching, dependency-update monitoring, and clearer delivery-stage validation responsibilities.
- Stable and development bootstrap semantics are now explicitly separated: released usage is version-pinned and checksum verified, while mutable `main` remains development-only.

### Fixed

- Hardened filesystem, native-command, release-metadata, bootstrap-child, promotion-conflict, and finalization failure handling so operational failures propagate consistently and fail closed where required.
- Improved PowerShell/Bash behavioral parity across confirmations, metadata boundaries, transaction handling, system-SDK discovery, and failure reporting.
- Normalized interactive menu lifecycle, cancellation, exit behavior, removal presentation, and platform-specific path presentation.

### Security

- Downloaded .NET SDK payloads are verified against Microsoft's published SHA-512 before extraction.
- Stable product scripts are verified against the selected release's `SHA256SUMS` before execution; the checksum and script share the GitHub trust domain and are not presented as an independent publisher signature.
- GitHub Actions and validation dependencies use reviewed immutable or exact-version pins where practical, with repository-owned integrity checks for downloaded validation tooling.

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
