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
- removes only the selected version directory;
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

1. request build-server shutdown with the selected isolated `dotnet` host;
2. require a zero shutdown exit code;
3. remove only the selected SDK version directory;
4. verify the directory no longer exists;
5. report success.

A shutdown failure prevents deletion. A deletion failure or remaining directory prevents success reporting.

`-WhatIf` and cancellation occur before shutdown.

## Behavioral scenarios

### Default cancellation

Given an installed isolated SDK, when the user declines the default tool-owned confirmation, shutdown is not invoked, the SDK directory remains, and cancellation is not an operational failure.

### Default approval

Given an installed isolated SDK, when the user approves the default tool-owned confirmation, shutdown occurs before deletion and success is reported only after deletion is verified.

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

## Traceability

- GitHub issue: #11
- TDD RED evidence: Validate run #56 on test-only head `332844d`
- implementation GREEN evidence: Validate run #61 on head `e61749b`
- automated suite: `tests/powershell/run-removal-tests.ps1`
