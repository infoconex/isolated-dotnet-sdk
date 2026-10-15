# Remove

Remove deletes SDKs managed under the isolated SDK root. It never removes System SDKs.

For exact shell syntax, see [Windows / PowerShell](../getting-started/windows-powershell.md#remove-an-isolated-sdk) or [Linux and macOS / Bash](../getting-started/linux-macos-bash.md#remove-an-isolated-sdk).

## Selecting an SDK

Remove with an exact version targets only that version's directory directly beneath the isolated SDK root.

Remove without a version opens a picker containing recognized Isolated SDKs ordered newest to oldest. System SDKs are not included because they are outside the tool's ownership boundary.

An empty isolated inventory or explicit picker cancellation is a normal no-change result.

## Confirmation

Removal is default-no. Without an approved confirmation path, the selected SDK is preserved.

PowerShell and Bash both provide a tool-owned automatic-confirmation option for intentional automation. PowerShell additionally supports native `ShouldProcess` semantics for Remove, including `-WhatIf`, `-Confirm`, and explicit `-Confirm:$false`; Bash does not emulate those PowerShell facilities.

The authoritative PowerShell-specific rules and precedence are documented in the [PowerShell removal contract](../contracts/powershell-removal.md).

## Build-server shutdown and deletion

After removal is approved, the selected isolated SDK is asked to shut down its .NET build servers before directory deletion. The shutdown runs from an operation-owned temporary working directory with the selected SDK as `DOTNET_ROOT`, older Windows multi-level SDK lookup disabled, and first-run CLI state isolated from the caller. The caller's working directory and environment are preserved.

A nonzero build-server shutdown result is an operational failure, including on legacy SDKs. It blocks deletion and suppresses removal success; temporary shutdown state setup or cleanup failure also blocks deletion. The tool does not ignore a shutdown failure based on SDK version or exception text.

After deletion, the tool verifies the selected version directory is gone before reporting success. Filesystem or deletion failure returns nonzero and does not broaden cleanup to sibling SDKs or System SDK locations.

## Interactive versus one-shot

Remove selected from a terminal-backed persistent Main session keeps a normal completed or cancellation/no-change result visible until Enter acknowledgement. A result launched from the Remove SDK picker returns to that picker (`Press Enter to return to Remove...`) while isolated SDKs remain. Removing the final isolated SDK returns directly to Main after acknowledgement because there is no remaining Remove list. If no isolated SDK exists and therefore no picker is displayed, the no-inventory result also returns to Main. Redirected or captured persistent execution skips the pause but follows the same parent navigation. An explicit Remove invocation is one-shot; if it opens a picker, normal cancellation ends that command successfully without entering Main or waiting for persistent-session acknowledgement.

See [Interactive mode](interactive.md), [Filesystem safety](../concepts/filesystem-safety.md), and [Native-command failure boundaries](../contracts/native-command-failures.md) for the detailed contracts.
