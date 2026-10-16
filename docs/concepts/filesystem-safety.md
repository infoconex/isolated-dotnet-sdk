# Filesystem safety

This document records the filesystem-safety contract shared by the PowerShell and Bash implementations.

## Isolated root and path conflicts

The tool owns `~/dotnet-sdks` and creates that directory when needed. If the path cannot be created or is occupied by a non-directory entry, the operation fails. A filesystem failure must not be followed by a misleading success message.

SDK-version-shaped names and direct-child path types are checked before version-scoped destructive work. A Remove candidate **need not have a usable dotnet host or pass Verify**: the owner explicitly authorizes confirmed cleanup of damaged SDK directories under the isolated root. Removal targets only that chosen eligible version directory and, after an authorized same-root rename, its operation-owned quarantine. An incomplete deletion is an operational failure; sibling SDK directories, unrelated tool-owned files, and System SDKs are not cleanup targets.

After Remove confirmation, build-server shutdown uses a fresh operation-owned temporary directory for its working directory and CLI home. That directory is separate from the selected SDK directory and is cleaned before deletion is attempted; a failure to create or clean it prevents SDK deletion. The original working directory and environment are preserved. An available shutdown command must still succeed, even on legacy SDKs. Only bounded, stable pre-2.1.300 historical servicing windows can use the verified missing-command compatibility path after both historical shutdown spellings are positively identified as unsupported; no separate permission is required beyond normal removal confirmation. SDKs in the pre-unified 2.1.1xx and 2.1.2xx bands must successfully execute their own SDK-local Roslyn compiler-server shutdown. An unknown failure, ambiguous classification, or temporary-state cleanup failure never permits SDK deletion.

## Incomplete Remove recovery

After normal confirmation and successful supported shutdown/preflight **when a usable host exists**, or an informative no-host warning for a confirmed damaged directory, Remove creates a recovery record outside the selected SDK directory and a matching operation-owned proof inside it, then renames the direct-child directory into a unique same-root `.removing-*` quarantine. A failed move leaves the original directory in place. Deletion preserves the internal proof until the other contents have been removed. After a failed deletion, only a new user-initiated Remove may continue removing the verified quarantined contents without a now-missing SDK host.

The recovery record and proof must match the exact SDK version and unique removal operation ID. The original version path must remain absent and the quarantine must be an actual directory, not a symlink/junction. Missing or inconsistent proof with remaining files, path replacement and unexpected state all fail closed. Recovery records are not general permission to remove arbitrary directories. No background retry, process killing, or rollback is implied. Full success requires directory absence and recovery-state cleanup; lingering files cause nonzero failure with retry guidance. Install refuses that version until recovery is complete, and normal SDK inventory excludes quarantined directories.

## Saved-tool replacement

Bootstrap replacement is staged in the isolated SDK root, beside the stable saved-tool path. Staging names are collision-resistant and operation-owned.

The stable saved-tool path is replaced only after the candidate has been fully written and any required executable/unblock step has succeeded. If staging or replacement fails, an existing stable saved-tool file is recovery state and is not deliberately removed. Operation-owned staging files are cleaned where safe and practical, and cleanup failure must not mask the primary failure.

A directory at the stable saved-tool path is treated as a conflict rather than as a destination into which the candidate may be moved.

## Release-metadata temporary files

Interactive release selection uses collision-resistant metadata files beneath the isolated SDK root where filesystem-backed metadata processing is required. Installation of an exact SDK also uses operation-owned release metadata to resolve the exact platform archive and supported Microsoft-published checksum (SHA-512 for 2.x+ and modern SDKs; SHA-256 only for eligible historical .NET 1.x SDKs). Those files are transaction state, not persistent product state.

Operation-owned metadata files are removed after normal processing and on failure where cleanup is possible. Similarly named pre-existing files are not considered operation-owned and must not be removed by cleanup.

## Transactional SDK installation

A new SDK installation never targets the final `~/dotnet-sdks/<version>` directory directly. Each attempt owns collision-resistant temporary artifacts beneath the isolated SDK root:

- operation-scoped Microsoft release metadata;
- an operation-scoped downloaded SDK payload archive;
- an operation-scoped SDK staging directory.

The exact SDK artifact URL and supported checksum are resolved from Microsoft's release metadata for the requested version and platform identifier. The downloaded archive is verified **before extraction** using Microsoft's published SHA-512 (2.x and newer) or, only for eligible historical .NET 1.x archives, its published SHA-256. Missing, malformed, mismatched, or unsupported checksums and failed downloads stop installation before extraction; unverified archives are never accepted.

Only a verified archive is extracted into operation-owned staging. Modern hosts must pass exact `--list-sdks` version/origin and controlled `--version` proof. Original 1.x and early 2.x hosts (before 2.1.300) instead require exact pinned `--version` and SDK `Base Path` from `--info` inside staging because `--list-sdks` is unsupported. Extraction failure, missing host, failed proof, wrong version, or wrong origin blocks promotion. The tool attempts to remove operation-owned staging and transaction files on failure; cleanup itself may fail and must not conceal the primary error.

After staged verification succeeds, the tool checks the final destination again and promotes the staging directory only when that destination is still absent. If a destination appears before promotion, or promotion otherwise fails, the pre-existing/newly appeared final destination is preserved and cleanup remains limited to the operation-owned transaction state.

If the final version destination already exists before an installation attempt:

- an existing installation that passes the generation-appropriate exact version **and isolated origin** proof retains the existing `already installed` behavior;
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
- PowerShell removal verifies its quarantined target no longer exists after child deletion;
- Bash relies on `rm` errors and also verifies that the quarantined target is gone;
- deterministic tests inject filesystem-command failures instead of depending on timing-sensitive lock behavior that differs between Windows, macOS, and Linux.

This means a Windows locked-file failure and a Unix permission/deletion failure may originate differently, but both must satisfy the same external contract: non-success, no false success message, and no broadened destructive scope.

## Roadmap boundaries

This contract defines filesystem ownership, cleanup, transactional SDK-install behavior, and the filesystem side of payload verification. It does not add generic retry/backoff behavior, automatic repair of arbitrary pre-existing SDK destinations, or a generalized transaction framework. Stable release/bootstrap versioning policy remains a separate concern.
