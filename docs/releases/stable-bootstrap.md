# Stable bootstrap, update, and rollback

Stable use of `isolated-dotnet-sdk` is explicitly version-pinned. The current checksum-policy-compliant stable release is `v0.2.0`.

This document defines the stable-source policy. For the exact copy/paste bootstrap command, use the guide for your supported platform:

- [Windows / PowerShell 7](../getting-started/windows-powershell.md#install-the-stable-tool)
- [Linux or macOS / Bash](../getting-started/linux-macos-bash.md#install-the-stable-tool)

## Stable bootstrap

A stable bootstrap:

1. selects an explicit published release tag;
2. downloads that tag's platform script;
3. downloads the same release's `SHA256SUMS` asset;
4. requires exactly one valid checksum entry for the selected platform script;
5. verifies the downloaded script before execution; and
6. executes the verified temporary file so file-based bootstrap saves those exact verified bytes under `~/dotnet-sdks`.

Stable bootstrap intentionally executes a downloaded file rather than piping released source. Piped execution has no source file path to preserve and belongs to the development `main` path instead.

The checksum and script are both distributed through GitHub. The checksum detects corruption and mismatched acquired bytes within that trust domain; it is not an independent publisher signature.

## `v0.1.0` legacy boundary

`v0.1.0` predates the checksum-verifying stable-release policy and has no `SHA256SUMS` release asset. Its published history is retained rather than rewritten retroactively.

The stable bootstrap contract above applies to `v0.2.0` and later releases published under the current checksum policy.

## Updates

Normal execution of the saved tool does not query GitHub for updates, replace itself, or resolve a moving latest-stable alias.

To update, deliberately choose a newer checksum-policy-compliant published tag and run that tag through the same verified stable bootstrap for your platform. File-based bootstrap stages replacement of the saved tool and preserves the newly verified tagged source.

## Rollback

Rollback is the same explicit operation with an older checksum-policy-compliant published tag. The tool does not distinguish update from rollback by policy; the selected tag is authoritative.

If acquisition, checksum verification, staging, or final saved-tool replacement fails, unverified source is not executed and the existing saved tool remains recovery state where the bootstrap replacement contract can preserve it.

## Development `main`

Mutable `main` is an explicit development source, not a stable channel. The getting-started guides show the corresponding development one-liner for each shell.

Rerunning a development command may refresh the saved tool from newer `main` source. It does not receive the stable-release checksum guarantee and must not be presented as stable installation or update behavior.

## Version discovery

Stable version discovery is intentionally outside the tool runtime. Choose the desired published release and use its exact tag.

The tool does not follow a `latest` release alias or silently select a newer stable version.

## Related documentation

- [Bootstrap source preservation and reproducibility](../concepts/bootstrap-reproducibility.md)
- [Supply-chain integrity and trust boundaries](../concepts/supply-chain-integrity.md)
- [Stable release publication and verification](../maintainers/releases/release-process.md) — maintainer-only publication procedure
