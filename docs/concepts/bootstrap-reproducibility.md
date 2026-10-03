# Bootstrap source preservation and reproducibility

This document describes how the product preserves the source identity of the tool script that is being installed under the current user's `dotnet-sdks` directory.

The stable installation, update, and rollback policy is defined in [Stable bootstrap, update, and rollback](../releases/stable-bootstrap.md). Stable users should follow that document's explicit-tag, checksum-verifying bootstrap policy and the platform getting-started guide rather than execute mutable `main` as a stable installation source.

## File-based bootstrap

When either platform script is executed from a real file, bootstrap preserves that exact file as the saved tool:

1. Resolve the current script path and the platform-specific saved-tool path under `~/dotnet-sdks`.
2. If the script is already running from the saved-tool path, continue normally without replacing it.
3. Otherwise write/copy the current script into an operation-owned staged candidate beside the saved-tool path.
4. Complete the platform-specific preparation required for the candidate, including the Bash executable bit and PowerShell unblock handling where available.
5. Replace the saved-tool file only after staging/preparation succeeds.
6. Re-execute the saved tool with the original arguments.

This means a verified stable bootstrap can download a script for an explicit release tag, verify those bytes against that release's `SHA256SUMS`, execute the verified temporary file, and rely on file-based bootstrap to preserve those same verified bytes under `~/dotnet-sdks`.

File-based execution also preserves an explicitly downloaded repository/tagged copy used for development or troubleshooting; the source identity comes from the file being executed, not from an implicit "latest" lookup.

## Piped development bootstrap

Piped execution has no source file path to preserve. In that case the product's fallback acquisition path downloads the configured mutable `main` source before saving and re-executing the tool.

The documented `main` one-liners are therefore **development-only** commands. Rerunning them may refresh the saved tool from newer `main` content. They are not the stable installation/update path and do not receive the stable-release checksum guarantee.

Normal execution of an already-saved tool does not perform this remote fallback and does not check for or install updates automatically.

## Stable update and rollback

Stable update and rollback are explicit bootstrap operations, not runtime self-update behavior:

- choose the desired published release tag;
- download the platform script and that release's checksum material;
- verify the selected script before execution; and
- execute the verified file so file-based bootstrap replaces the saved copy with exactly that selected source.

Choosing a newer tag performs an update. Choosing an older policy-compliant tag performs a rollback. See [Stable bootstrap, update, and rollback](../releases/stable-bootstrap.md) for the policy and the supported platform guides for copy/paste commands.

## Failure and recovery behavior

Saved-tool replacement is staged under the isolated SDK root. Acquisition, staging, preparation, or final replacement failure must not deliberately remove an existing saved tool that is valid recovery state. Operation-owned candidates are cleaned where safe and practical.

The detailed filesystem ownership and recovery contract is authoritative in [Filesystem safety](filesystem-safety.md). Platform-specific path, executable-bit, and argument-forwarding mechanics are documented in [Cross-platform support](cross-platform-support.md).

## Integrity boundary

Source preservation and source integrity are related but distinct:

- file-based bootstrap preserves the exact script file being executed;
- stable bootstrap verifies the explicitly tagged script against the release's `SHA256SUMS` before execution;
- development `main` execution intentionally consumes mutable source and does not receive that stable guarantee.

The complete remote-artifact and residual-trust model is documented in [Supply-chain integrity and trust boundaries](supply-chain-integrity.md).

## Historical note

`v0.1.0` predates the current stable checksum policy. Historical release notes and changelog entries may describe the refresh-from-`main` bootstrap experience that applied to that release; they are historical records rather than the current stable bootstrap contract.
