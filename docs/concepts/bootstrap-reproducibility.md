# Bootstrap source preservation and reproducibility

This document describes how the product preserves the source identity of the tool script installed under the current user's `dotnet-sdks` directory.

The stable installation, update, and rollback policy is defined in [Stable bootstrap, update, and rollback](../releases/stable-bootstrap.md). Stable users normally use the short latest-stable Pages bootstrap; an explicit pinned release remains available when the exact version must be selected in advance.

## File-based product bootstrap

When either platform product script is executed from a real file, bootstrap preserves that exact file as the saved tool:

1. Resolve the current script path and the platform-specific saved-tool path under `~/dotnet-sdks`.
2. If the script is already running from the saved-tool path, continue normally without replacing it.
3. Otherwise write/copy the current script into an operation-owned staged candidate beside the saved-tool path.
4. Complete the platform-specific preparation required for the candidate, including the Bash executable bit and PowerShell unblock handling where available.
5. Replace the saved-tool file only after staging/preparation succeeds.
6. Re-execute the saved tool with the original arguments.

Both supported stable bootstrap modes arrange for the released product script to reach this path as a verified real file:

- the latest-stable Pages bootstrap resolves a published stable release, downloads the tagged product script and that release's `SHA256SUMS`, verifies the product script, and executes the verified temporary file;
- pinned stable bootstrap downloads the explicitly selected tagged product script and checksum material, verifies it, and executes the verified temporary file.

In both cases, file-based product bootstrap preserves the exact verified tagged bytes under `~/dotnet-sdks`.

File-based execution also preserves an explicitly downloaded repository/tagged copy used for development or troubleshooting; the source identity comes from the file being executed, not from an implicit runtime update lookup.

## Piped latest-stable bootstrap

The short stable command pipes only the small Pages-hosted `install.ps1` or `install.sh` bootstrap. That bootstrap has no opportunity to verify its own bytes before they begin executing and is trusted through HTTPS delivery from the project Pages site.

Its responsibility is limited to release discovery and verified handoff. It downloads the resolved tagged product script to a real temporary file, verifies that file against the same release's `SHA256SUMS`, and only then executes the product script. The saved tool therefore comes from the verified tagged product file, not from the unversioned Pages bootstrap.

Rerunning the short command performs a new explicit latest-stable resolution. An already-saved product tool does not perform that lookup during normal execution.

## Piped development product bootstrap

Piping mutable product source from `main` is a separate development-only path. Piped product execution has no source file path to preserve, so the product's fallback acquisition path downloads the configured mutable `main` source before saving and re-executing the tool.

The documented raw-`main` one-liners are therefore **development-only** commands. Rerunning them may refresh the saved tool from newer `main` content. They are not stable installation/update commands and do not receive the stable-release checksum guarantee.

Normal execution of an already-saved tool does not perform this remote fallback and does not check for or install updates automatically.

## Stable update and rollback

Stable update and rollback are explicit bootstrap operations, not runtime self-update behavior:

- rerun the short Pages bootstrap to resolve and install the latest published stable release;
- or choose an exact checksum-policy-compliant release tag and use pinned stable bootstrap.

Choosing a newer pinned tag performs an explicit version-selected update. Choosing an older policy-compliant tag performs a rollback. See [Stable bootstrap, update, and rollback](../releases/stable-bootstrap.md) for the policy and exact procedures.

## Failure and recovery behavior

Latest-release discovery, released-script acquisition, checksum acquisition, checksum validation, or digest mismatch must fail before the released product script executes. The bootstrap's operation-owned temporary files are cleaned where safe and practical.

Once the verified product script starts, saved-tool replacement is staged under the isolated SDK root. Acquisition, staging, preparation, or final replacement failure must not deliberately remove an existing saved tool that is valid recovery state. Operation-owned candidates are cleaned where safe and practical.

The detailed filesystem ownership and recovery contract is authoritative in [Filesystem safety](filesystem-safety.md). Platform-specific path, executable-bit, and argument-forwarding mechanics are documented in [Cross-platform support](cross-platform-support.md).

## Integrity boundary

Source preservation and source integrity are related but distinct:

- the Pages-hosted latest-stable bootstrap is trusted through its HTTPS delivery path and cannot verify its own piped bytes before execution;
- that bootstrap verifies the resolved tagged product script against the release's `SHA256SUMS` before executing it;
- pinned stable bootstrap performs the same released-product verification for an explicitly selected tag;
- file-based product bootstrap then preserves those exact verified product bytes;
- development `main` product execution intentionally consumes mutable source and does not receive the stable guarantee.

The complete remote-artifact and residual-trust model is documented in [Supply-chain integrity and trust boundaries](supply-chain-integrity.md).

## Historical note

`v0.1.0` predates the current stable checksum policy. Historical release notes and changelog entries may describe the refresh-from-`main` bootstrap experience that applied to that release; they are historical records rather than the current stable bootstrap contract.
