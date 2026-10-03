# Filesystem safety

This document records the filesystem-safety contract shared by the PowerShell and Bash implementations.

## Isolated root and path conflicts

The tool owns `~/dotnet-sdks` and creates that directory when needed. If the path cannot be created or is occupied by a non-directory entry, the operation fails. A filesystem failure must not be followed by a misleading success message.

SDK versions are validated before version-scoped destructive work. Removal is limited to the selected version directory directly beneath the isolated SDK root. Failure to remove that directory is an operation failure; sibling SDK directories and unrelated tool-owned files are not cleanup targets.

## Saved-tool replacement

Bootstrap replacement is staged in the isolated SDK root, beside the stable saved-tool path. Staging names are collision-resistant and operation-owned.

The stable saved-tool path is replaced only after the candidate has been fully written and any required executable/unblock step has succeeded. If staging or replacement fails, an existing stable saved-tool file is recovery state and is not deliberately removed. Operation-owned staging files are cleaned where safe and practical, and cleanup failure must not mask the primary failure.

A directory at the stable saved-tool path is treated as a conflict rather than as a destination into which the candidate may be moved.

## Release-metadata temporary files

Interactive release selection uses collision-resistant metadata files beneath the isolated SDK root where filesystem-backed metadata processing is required. Installation of an exact SDK also uses operation-owned release metadata to resolve the exact platform archive and its SHA-512. Those files are transaction state, not persistent product state.

Operation-owned metadata files are removed after normal processing and on failure where cleanup is possible. Similarly named pre-existing files are not considered operation-owned and must not be removed by cleanup.

## Transactional SDK installation

A new SDK installation never targets the final `~/dotnet-sdks/<version>` directory directly. Each attempt owns collision-resistant temporary artifacts beneath the isolated SDK root:

- operation-scoped Microsoft release metadata;
- an operation-scoped downloaded SDK payload archive;
- an operation-scoped SDK staging directory.

The exact SDK artifact URL and SHA-512 are resolved from Microsoft's release metadata for the requested version and supported runtime identifier. The archive is downloaded into operation-owned state and its SHA-512 is verified before extraction. Missing or malformed required metadata, payload download failure, or checksum mismatch fails before extraction. The tool does not fall back to an unverified archive.

Only a verified archive is extracted into the operation-owned staging directory. Extraction failure, a missing staged host, a nonzero staged-host inventory command, or an inventory that omits the requested exact SDK all fail before promotion. The staging directory and transaction files are then removed where cleanup is possible, so an attempt that started without a final destination leaves no partial final version directory.

After staged verification succeeds, the tool checks the final destination again and promotes the staging directory only when that destination is still absent. If a destination appears before promotion, or promotion otherwise fails, the pre-existing/newly appeared final destination is preserved and cleanup remains limited to the operation-owned transaction state.

If the final version destination already exists before an installation attempt:

- a working isolated host that reports the requested exact version retains the existing `already installed` behavior;
- every other existing file or directory state is treated as recovery/user state and causes deterministic destination-conflict failure;
- no payload is downloaded or extracted into that destination;
- the tool does not delete, replace, merge into, or repair that state automatically.

This means a failed clean-start attempt is retryable without manual cleanup because incomplete output is never promoted. A non-valid pre-existing final destination remains a deliberate operator decision: retries continue to fail closed until that state is resolved externally.

Supplying an exact SDK version bypasses interactive release-index/channel discovery, but a new installation still retrieves the exact version's Microsoft release metadata needed to identify the supported platform archive and its checksum. This metadata lookup is part of payload integrity verification, not version selection.

Cleanup is restricted to artifacts created and owned by the current operation. Cleanup failure is reported and must not hide the primary installation failure. Installation success is emitted only after the payload checksum has been verified, the requested exact SDK has been verified in staging, staging has been promoted to the final destination, and normal operation-owned cleanup has completed.

## Platform-specific failure semantics

The portable contract is based on observable filesystem success or failure rather than one operating system's locking model:

- directory/path-type conflicts fail on all supported platforms;
- access, replacement, extraction, or deletion failures propagate and do not produce success output;
- PowerShell removal verifies that the target no longer exists after `Remove-Item`;
- Bash relies on the `rm` exit status and also verifies that the target directory is gone;
- deterministic tests inject filesystem-command failures instead of depending on timing-sensitive lock behavior that differs between Windows, macOS, and Linux.

This means a Windows locked-file failure and a Unix permission/deletion failure may originate differently, but both must satisfy the same external contract: non-success, no false success message, and no broadened destructive scope.

## Roadmap boundaries

This contract defines filesystem ownership, cleanup, transactional SDK-install behavior, and the filesystem side of payload verification. It does not add generic retry/backoff behavior, automatic repair of arbitrary pre-existing SDK destinations, or a generalized transaction framework. Stable release/bootstrap versioning policy remains a separate concern.
