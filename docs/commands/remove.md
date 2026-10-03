# Remove

Remove deletes SDKs managed under the isolated SDK root. It never removes System SDKs.

For exact shell syntax, see [Windows / PowerShell](../getting-started/windows-powershell.md#remove-an-isolated-sdk) or [Linux and macOS / Bash](../getting-started/linux-macos-bash.md#remove-an-isolated-sdk).

## Selecting an SDK

Remove with an exact version targets only that version's directory directly beneath the isolated SDK root.

Remove without a version opens a picker containing recognized Isolated SDKs. System SDKs are not included because they are outside the tool's ownership boundary.

An empty isolated inventory or explicit picker cancellation is a normal no-change result.

## Confirmation

Removal is default-no. Without an approved confirmation path, the selected SDK is preserved.

PowerShell and Bash both provide a tool-owned automatic-confirmation option for intentional automation. PowerShell additionally supports native `ShouldProcess` semantics for Remove, including `-WhatIf`, `-Confirm`, and explicit `-Confirm:$false`; Bash does not emulate those PowerShell facilities.

The authoritative PowerShell-specific rules and precedence are documented in the [PowerShell removal contract](../contracts/powershell-removal.md).

## Build-server shutdown and deletion

After removal is approved, the selected isolated SDK is asked to shut down its .NET build servers before directory deletion.

A nonzero build-server shutdown result is an operational failure. It blocks deletion and suppresses removal success.

After deletion, the tool verifies the selected version directory is gone before reporting success. Filesystem or deletion failure returns nonzero and does not broaden cleanup to sibling SDKs or System SDK locations.

## Interactive versus one-shot

Remove selected from the persistent Main menu returns to Main after normal completion or cancellation. An explicit Remove invocation is one-shot; if it opens a picker, normal cancellation ends that command successfully without entering Main.

See [Interactive mode](interactive.md), [Filesystem safety](../concepts/filesystem-safety.md), and [Native-command failure boundaries](../contracts/native-command-failures.md) for the detailed contracts.
