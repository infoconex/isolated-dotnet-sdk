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

The Bash interactive release picker writes channel metadata to a collision-resistant temporary file under the isolated SDK root. The file is removed after normal processing, on metadata-download failure, and on EXIT, TERM, INT, or HUP while the temporary file is active. Signal cleanup removes only the exact file created by the current operation, restores the signal's default action, and re-raises the signal so interruption is still observable as interruption/failure.

Similarly named pre-existing files are not considered operation-owned and must not be removed by cleanup.

## Platform-specific failure semantics

The portable contract is based on observable filesystem success or failure rather than one operating system's locking model:

- directory/path-type conflicts fail on all supported platforms;
- access, replacement, or deletion failures propagate and do not produce success output;
- PowerShell removal verifies that the target no longer exists after `Remove-Item`;
- Bash relies on the `rm` exit status and also verifies that the target directory is gone;
- deterministic tests inject filesystem-command failures instead of depending on timing-sensitive lock behavior that differs between Windows, macOS, and Linux.

This means a Windows locked-file failure and a Unix permission/deletion failure may originate differently, but both must satisfy the same external contract: non-success, no false success message, and no broadened destructive scope.

## Boundaries with later roadmap work

This contract does not define network error policy for release metadata or bootstrap sources; that belongs to the network-failure roadmap work. It also does not make SDK installation fully transactional or define rollback of a partially populated SDK version directory; that belongs to the transactional-install roadmap work.
