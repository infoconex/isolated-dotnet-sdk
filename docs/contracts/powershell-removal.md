# PowerShell removal contract

This document defines the externally observable behavior of isolated SDK removal in `isolated-dotnet-sdk.ps1`.

## Baseline

Before native `ShouldProcess` support, PowerShell removal:

- resolves or prompts for an isolated SDK version;
- verifies the selected isolated `dotnet.exe` exists;
- displays a removal warning;
- asks `Continue? [y/N]` and treats an empty response as no;
- treats cancellation as a normal user action rather than an operational failure;
- allows `-Yes` to bypass the tool-owned confirmation;
- requests `dotnet build-server shutdown` before deletion;
- moves only the verified selected version directory into same-root removal quarantine and deletes that target;
- reports success only after verifying the directory no longer exists.

The baseline does not expose native `-WhatIf` or `-Confirm`, and it does not explicitly stop deletion when the native build-server shutdown command exits nonzero.

## ShouldProcess contract

PowerShell removal supports native `ShouldProcess` semantics while preserving the established default-no confirmation behavior.

`Remove-IsolatedSdk` uses `SupportsShouldProcess` with medium confirmation impact. The script exposes the corresponding PowerShell risk-mitigation common parameters.

The destructive operation represented by `ShouldProcess` is removal of the selected isolated SDK directory. Build-server shutdown is part of that operation and occurs only after approval.

### Default interactive removal

When neither `-Yes` nor an explicit `-Confirm` value is supplied, ordinary interactive removal retains the tool-owned `Continue? [y/N]` confirmation when PowerShell confirmation preferences have not already required native confirmation.

Pressing Enter therefore continues to mean no removal.

### `-WhatIf`

`-WhatIf` is authoritative. It describes the intended SDK removal but performs neither build-server shutdown nor directory deletion. It does not ask the tool-owned confirmation question.

If `-Yes` and `-WhatIf` are both present, `-WhatIf` wins.

### `-Confirm`

An explicit `-Confirm` uses PowerShell's native confirmation behavior for the SDK removal operation. The tool-owned confirmation is not duplicated.

An explicit `-Confirm:$false` suppresses confirmation and permits intentional automation.

The dedicated automated suite proves native `-Confirm` parameter exposure and proves that `-Confirm:$false` bypasses the tool-owned prompt. Positive interactive `-Confirm` prompting is owned by the PowerShell host; duplicate-prompt prevention is enforced by the implementation condition that the tool-owned prompt runs only when `Confirm` was not explicitly bound.

### `-Yes`

`-Yes` remains supported for compatibility and automation. It bypasses the tool-owned confirmation but does not bypass `-WhatIf`.

If `-Yes` and an explicit `-Confirm` value are both supplied, the explicit PowerShell confirmation choice is authoritative.

### Unsupported actions

`-WhatIf` and explicit `-Confirm` are currently specified only for the PowerShell `Remove` action.

If either parameter is explicitly supplied and the resolved action is `Install` or `List`, execution fails before that product action runs. The tool does not silently imply risk-mitigation semantics for actions that do not yet have a defined `ShouldProcess` contract.

The self-bootstrap step may create or refresh the saved tool copy before product-action dispatch. Those bootstrap file mutations are not the selected SDK removal operation, so they explicitly suppress inherited `WhatIf` / `Confirm` preferences while preserving the user's explicitly supplied risk parameters for the re-executed removal action.

## Non-interactive execution

Non-interactive execution is fail-safe:

- `-WhatIf` succeeds without prompting or changing SDK state;
- ordinary removal without `-Yes` or explicit confirmation suppression must not shut down build servers or delete the SDK;
- `-Yes` and `-Confirm:$false` are supported automation paths when removal is intentionally approved.

## Removal transaction

After removal is approved, operations occur in this order:

1. Validate the **SDK-version-shaped directory name**, its direct-child relationship to the isolated root, and the absence of an unsafe path type such as a junction or directory symlink. A directory without a dotnet host remains an eligible cleanup candidate, **not** a verified SDK.
2. When a usable isolated host is present, require successful build-server shutdown with the selected host in neutral temporary working state (`DOTNET_ROOT` scoped, Windows multilevel lookup disabled), or the strict verified historical compatibility path. Restore the caller's environment and clean up temporary shutdown state. When the host is absent or unsafe to execute, warn before deletion that shutdown cannot be performed and processes/files may remain in use.
3. Record ordinary confirmation in operation-owned recovery state, and rename the selected version directory into a unique same-root quarantine before recursive deletion. A subsequent user-initiated Remove with fresh ordinary confirmation can finish that **same verified staged deletion**, even if the SDK host is gone.
4. Verify the quarantined directory is absent and recovery records are cleaned up.
5. Report success only after full cleanup.

**An actually attempted supported shutdown failure**, temporary shutdown-state setup failure or temporary-state cleanup failure blocks deletion. By contrast, the absence of an SDK host is not an available shutdown that failed; normally confirmed cleanup of that damaged directory is allowed. An incomplete deletion returns nonzero, preserving recovery proof. The initial directory rename may fail when Windows processes hold incompatible handles; a successful rename does not guarantee files are unlocked.

`-WhatIf` and cancellation occur before shutdown.

## Automatic historical unsupported-shutdown compatibility

`-AllowUnsupportedShutdown` is retained as a deprecated Remove-only option for backwards compatibility; a *verified* historical unsupported shutdown is automatically handled after ordinary removal confirmation. This flag does not grant permission to ignore a supported shutdown failure, is not required in interactive or direct Remove, and is rejected for other actions. `-WhatIf` remains authoritative.

This exception is limited to the exact observed installed SDK versions `1.0.4`, `1.1.5`, `1.1.14`, `2.0.3`, and `2.1.105`, not all SDK versions matching a numeric prefix. The SDK-local `sdk/<version>` payload must exist. Both historical command spellings are probed in the isolated environment; a supported command must instead complete its real build-server shutdown successfully. An expected missing-command exit and message for **both** spellings establishes the unsupported case; any unexpected probe result is a blocking failure.

For SDK `2.1.105`, unsupported unified shutdown requires executing the selected SDK's `Roslyn/bincore/VBCSCompiler.dll -shutdown` through its own host with successful native exit. For the four older enumerated SDK versions, the absence of a `VBCSCompiler` component in their payload is additionally required. This is deliberately not a general guarantee that all build-related processes have stopped; warn explicitly that other processes may remain. An available shutdown failure, a failed Roslyn shutdown, or any ambiguous/missing payload condition prevents deletion even if the legacy option is supplied.

Neither the compatibility fallback, `-AllowUnsupportedShutdown`, nor `-Yes` bypasses `-WhatIf`, an unapproved confirmation, cleanup failure, selected-SDK ownership/scope checks, or directory deletion verification. If files remain in a verified quarantine, another ordinary Remove can retry without the now-missing SDK host; replacement/untrusted recovery state cannot be removed automatically.

## Behavioral scenarios

### Default cancellation

Given an installed isolated SDK, when the user declines the default tool-owned confirmation, shutdown is not invoked, the SDK directory remains, and cancellation is not an operational failure.

### Default approval

Given an SDK with an available host, when the user approves the default tool-owned confirmation, shutdown occurs before deletion and success is reported only after deletion is verified. For a missing-host folder, the ordinary confirmation authorizes cleanup after a warning rather than attempting shutdown.

### Preview

Given an installed isolated SDK, when removal is invoked with `-WhatIf`, PowerShell describes the intended removal, no tool-owned confirmation is requested, shutdown is not invoked, and the SDK directory remains.

### Native confirmation

Given an installed isolated SDK, when removal is invoked with `-Confirm`, PowerShell's native confirmation is authoritative and the tool-owned confirmation is not duplicated.

### Explicit confirmation suppression

Given an installed isolated SDK, when removal is invoked with `-Confirm:$false`, no confirmation prompt is required and approved removal proceeds.

### Yes bypass

Given an installed isolated SDK, when removal is invoked with `-Yes`, the tool-owned confirmation is bypassed and approved removal proceeds.

### WhatIf precedence

Given an installed isolated SDK, when removal is invoked with both `-Yes` and `-WhatIf`, shutdown and deletion do not occur.

### Unsupported action

Given an explicit `-WhatIf` or `-Confirm`, when the resolved action is `Install` or `List`, the command fails before that action executes.

### Non-interactive fail-safe

Given an installed isolated SDK, when removal is invoked in a non-interactive host without `-Yes` or explicit `-Confirm:$false`, shutdown is not invoked, the directory remains, and the command does not silently approve removal.

### Shutdown failure

Given approved removal, when build-server shutdown exits nonzero, removal fails and directory deletion is not attempted.

### Deletion failure

Given approved removal and successful shutdown, when directory deletion fails or the directory remains, removal fails and success is not reported.

### Damaged SDK and incomplete-removal recovery

Given a directory named like a full SDK version under the isolated root but without a usable SDK host, Remove can offer it as `(incomplete)`. After the normal confirmation it warns that shutdown is unavailable, stages that exact directory and attempts deletion. A rename or deletion failure never reports success. Any previously authorized, partially deleted stage remains selectable as `(incomplete removal)` and uses journal/proof checks plus a fresh ordinary confirmation to retry; it does not execute a deleted host or delete another directory. `-WhatIf` remains non-mutating in both paths.
