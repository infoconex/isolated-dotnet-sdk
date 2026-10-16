# Remove

Remove deletes SDKs managed under the isolated SDK root. It never removes System SDKs.

For exact shell syntax, see [Windows / PowerShell](../getting-started/windows-powershell.md#remove-an-isolated-sdk) or [Linux and macOS / Bash](../getting-started/linux-macos-bash.md#remove-an-isolated-sdk).

## Selecting an SDK

Remove with an exact version targets only that version's directory directly beneath the isolated SDK root.

Remove without a version lists **direct-child SDK-version-named directories**, ordered newest to oldest, whether or not their SDK host is usable. A missing or unusable host is labeled `(incomplete)`; a prior confirmed staged deletion needing another attempt is labeled `(incomplete removal)`. These are **removal candidates**, not a statement that their SDK is healthy or fully installed. Only exact SDK-version-shaped names qualify; links, mounts, non-directories, unrelated root entries and System SDKs are not removal targets.

An empty isolated inventory or explicit picker cancellation is a normal no-change result.

## Confirmation

Removal is default-no. Without an approved confirmation path, the selected SDK is preserved.

PowerShell and Bash both provide a tool-owned automatic-confirmation option for intentional automation. PowerShell additionally supports native `ShouldProcess` semantics for Remove, including `-WhatIf`, `-Confirm`, and explicit `-Confirm:$false`; Bash does not emulate those PowerShell facilities.

The authoritative PowerShell-specific rules and precedence are documented in the [PowerShell removal contract](../contracts/powershell-removal.md).

## Build-server shutdown and deletion

After removal is approved, the selected isolated SDK is asked to shut down its .NET build servers before directory deletion. The shutdown runs from an operation-owned temporary working directory with the selected SDK as `DOTNET_ROOT`, older Windows multi-level SDK lookup disabled, and first-run CLI state isolated from the caller. The caller's working directory and environment are preserved.

A failed *supported* build-server shutdown blocks deletion and suppresses removal success. Temporary shutdown-state setup or cleanup failure also blocks deletion. The tool never treats an arbitrary native failure, including a `hostfxr` exception, as proof that shutdown is unsupported.

### Automatic verified historical SDK removal

For strictly verified historical SDKs without unified shutdown, the tool uses the compatible removal path **automatically after the ordinary Remove confirmation**. There is no additional authorization flag or second prompt. The old PowerShell `-AllowUnsupportedShutdown` and Bash `--allow-unsupported-shutdown` switches remain accepted with Remove for existing scripts but are not required or used to bypass a real shutdown failure; they are rejected with other actions.

Only these **exact SDK versions**, verified by historical Windows testing, qualify for the exception: `1.0.4`, `1.1.5`, `1.1.14`, `2.0.3`, and `2.1.105`. Other SDK versions, including nearby servicing versions, retain mandatory build-server shutdown unless separately verified and added in future work.

For a qualifying SDK, the tool checks the SDK's installed payload and probes both historical command spellings (`build-server --help` and `buildserver --help`) from the controlled environment. Both must return the exact observed missing-command result before any fallback applies. If either command is available, the tool instead requires that command's actual shutdown to succeed. An ambiguous probe, unexpected error, missing payload, or failed shutdown blocks deletion.

For `2.1.105`, the fallback requires its SDK-local `Roslyn/bincore/VBCSCompiler.dll -shutdown` operation to return zero. For the four earlier sampled SDKs, the tool checks that their payload has no `VBCSCompiler` component. The user is warned **before deletion** that other build processes may remain and locked files may prevent complete cleanup. An exit-zero Roslyn request cannot guarantee all process classes have stopped, and the historical Roslyn path is an SDK-internal compatibility mechanism, not a general public shutdown API.

This exception never broadens the deletion scope or relaxes the rules for real shutdown errors. For example, `isolated-dotnet-sdk.sh remove 1.0.4 --yes` or `./isolated-dotnet-sdk.ps1 -Action Remove -SdkVersion 1.0.4 -Yes` use the verified fallback when applicable; `--yes` / `-Yes` still only skips the ordinary confirmation.

After ordinary confirmation, a **usable** SDK host requires successful build-server shutdown under the existing rules. When the SDK host is absent, non-executable (Bash), or an unsafe link, the tool warns that shutdown **cannot** run and that build processes/files may remain in use; it may remove the owner-selected strictly scoped damaged SDK directory without a separate opt-in. An actual attempted shutdown that fails still blocks deletion. Remove never requires a successful Verify check to clean a version-named incomplete directory.

After that required shutdown or the missing-host warning, the tool records removal authorization and **renames** the selected directory to a uniquely named operation-owned quarantine beneath the same isolated root, before deleting SDK files. If rename fails (for example, because a process holds a Windows lock or permissions disallow it), the installation remains at its original path; free the blocking process and invoke Remove again. Rename success is not proof that all contents are unlocked, particularly on Unix. While quarantined, the target is no longer a usable installed SDK.

If deletion then fails, the tool reports an **incomplete removal** with a nonzero exit code; some SDK files may already be gone. A later user-initiated Remove finds the incomplete entry even when its SDK host was deleted, requires the ordinary confirmation, checks matching persistent recovery proof, and deletes only the remaining files in that previously approved quarantine. It does **not** rerun a missing SDK executable or make another shutdown exception. No automatic retries or process termination occur. The tool refuses inconsistent, missing or replaced recovery state; do not manually alter its hidden recovery files.

Success is reported only after the quarantined directory is absent and recovery state is cleaned up. Install of the same version is blocked while removal is pending. List, Verify and Audit do not treat a quarantined SDK as installed. Sibling SDKs and System SDKs remain out of scope.

## Interactive versus one-shot

Remove selected from a terminal-backed persistent Main session keeps a normal completed or cancellation/no-change result visible until Enter acknowledgement. A result launched from the Remove SDK picker returns to that picker (`Press Enter to return to Remove...`) while isolated SDKs remain. Removing the final isolated SDK returns directly to Main after acknowledgement because there is no remaining Remove list. If no isolated SDK exists and therefore no picker is displayed, the no-inventory result also returns to Main. Redirected or captured persistent execution skips the pause but follows the same parent navigation. An explicit Remove invocation is one-shot; if it opens a picker, normal cancellation ends that command successfully without entering Main or waiting for persistent-session acknowledgement.

See [Interactive mode](interactive.md), [Filesystem safety](../concepts/filesystem-safety.md), and [Native-command failure boundaries](../contracts/native-command-failures.md) for the detailed contracts. For blocked shutdown and safe recovery, see [Troubleshooting and safe recovery](../guides/troubleshooting.md).
