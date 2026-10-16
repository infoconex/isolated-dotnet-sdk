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

A failed build-server shutdown blocks deletion and suppresses removal success, even when the user supplies legacy opt-in. Temporary shutdown-state setup or cleanup failure also blocks deletion. The tool never treats a native failure, including a `hostfxr` exception, as proof that shutdown is unsupported.

### Explicitly authorized historical SDK removal

The supported exception is **off by default**. PowerShell uses `-AllowUnsupportedShutdown` with `-Action Remove`; Bash uses `--allow-unsupported-shutdown` with `remove`. This is **separate from** the ordinary confirmation controls (`-Yes` / `--yes`, and PowerShell `-Confirm`). Passing automatic confirmation alone never permits a shutdown bypass. The option is rejected for other actions.

Only these **exact SDK versions**, verified by historical Windows testing, qualify for the exception: `1.0.4`, `1.1.5`, `1.1.14`, `2.0.3`, and `2.1.105`. Other SDK versions, including nearby servicing versions, retain mandatory build-server shutdown unless separately verified and added in future work.

For a qualifying SDK, the tool checks the SDK's installed payload and probes both historical command spellings (`build-server --help` and `buildserver --help`) from the controlled environment. Both must return the exact observed missing-command result before any fallback applies. If either command is available, the tool instead requires that command's actual shutdown to succeed. An ambiguous probe, unexpected error, missing payload, or failed shutdown blocks deletion.

For `2.1.105`, the fallback requires its SDK-local `Roslyn/bincore/VBCSCompiler.dll -shutdown` operation to return zero. For the four earlier sampled SDKs, the tool checks that their payload has no `VBCSCompiler` component before explicitly bypassing shutdown. The user is warned that other build processes may remain. An exit-zero Roslyn request cannot guarantee all process classes have stopped, and the historical Roslyn path is an SDK-internal compatibility mechanism, not a general public shutdown API.

This exception never broadens the deletion scope or relaxes the rules for real shutdown errors. For example, an intentionally authorized Bash invocation is `isolated-dotnet-sdk.sh remove 1.0.4 --allow-unsupported-shutdown --yes`; the equivalent PowerShell command is `./isolated-dotnet-sdk.ps1 -Action Remove -SdkVersion 1.0.4 -AllowUnsupportedShutdown -Yes`.

After deletion, the tool verifies the selected version directory is gone before reporting success. Filesystem or deletion failure returns nonzero and does not broaden cleanup to sibling SDKs or System SDK locations.

## Interactive versus one-shot

Remove selected from a terminal-backed persistent Main session keeps a normal completed or cancellation/no-change result visible until Enter acknowledgement. A result launched from the Remove SDK picker returns to that picker (`Press Enter to return to Remove...`) while isolated SDKs remain. Removing the final isolated SDK returns directly to Main after acknowledgement because there is no remaining Remove list. If no isolated SDK exists and therefore no picker is displayed, the no-inventory result also returns to Main. Redirected or captured persistent execution skips the pause but follows the same parent navigation. An explicit Remove invocation is one-shot; if it opens a picker, normal cancellation ends that command successfully without entering Main or waiting for persistent-session acknowledgement.

See [Interactive mode](interactive.md), [Filesystem safety](../concepts/filesystem-safety.md), and [Native-command failure boundaries](../contracts/native-command-failures.md) for the detailed contracts. For blocked shutdown and safe recovery, see [Troubleshooting and safe recovery](../guides/troubleshooting.md).
