# Verify

Verify is the read-only, detailed single-SDK report for one exact SDK already installed under the isolated SDK root. The local validation outcome is authoritative; online Microsoft lifecycle/servicing metadata is best-effort enrichment.

For exact direct-command syntax, see [Windows / PowerShell](../getting-started/windows-powershell.md#verify-an-isolated-sdk) or [Linux and macOS / Bash](../getting-started/linux-macos-bash.md#verify-an-isolated-sdk).

## Invocation modes

Verify is available as a one-shot exact-version command or through `V. Verify an isolated SDK` on the persistent Main menu. The interactive picker lists isolated versions newest to oldest; System SDKs are never targets. Both modes call the same local proof and reporting logic. Terminal-backed interactive results remain visible until Enter acknowledges them and then return to the Verify list. Captured and redirected sessions do not wait for acknowledgement.

## Detailed report and successful verification

Verify presents the same structured release type, prerelease/lifecycle state, servicing/update indication, exact SDK release date (`Release:`), future authoritative Go Live date, and end-of-support date (`EOS:`) as Audit. It uses Audit's classification rules and lifecycle styling, not a separately inferred status.

A report also includes the isolated location and individual local results:

```text
Verify isolated .NET SDK

  10.0.100  LTS  Active  Release: 2025-11-11  EOS: 2028-11-14  Update -> 10.0.401

Location: <isolated version directory>

Verification:
  Installation directory  OK  <isolated version directory>
  .NET host               OK  <isolated dotnet host>
  SDK inventory           OK  10.0.100 from <isolated version directory>/sdk
  SDK resolution          OK  10.0.100

Isolated SDK 10.0.100 verified successfully.
```

The example uses illustrative metadata. Actual labels/dates reflect Microsoft's live records. Only `OK` and supported lifecycle-status tokens are styled in interactive terminals; redirected output is ANSI-free.

Local proof requires:

- the exact tool-owned version directory and platform `dotnet` host to exist (Bash also requires executable permission);
- the isolated host to launch and `--list-sdks` to succeed;
- the same inventory entry to contain both the exact requested SDK version and the **expected isolated `sdk` origin directory**; another System SDK with the same version cannot satisfy this;
- the same host's `--version` to succeed and resolve the exact requested SDK version in a fresh, controlled working directory outside a caller's `global.json`, with older Windows multi-level lookup disabled.

A locally valid SDK exits 0 even when Microsoft lifecycle metadata is unavailable. In that case, Verify explicitly reports `Release/lifecycle information: Unavailable (Microsoft metadata could not be loaded).` rather than inventing release or lifecycle facts. When available, an unknown Microsoft channel is reported as `Unknown channel`.

## Failed verification

The report marks the failed local check `FAIL` with a specific reason and exits nonzero. Failure cases include missing directory/host, non-executable or unlaunchable host, failed SDK inventory, exact version missing, exact version from another root, and `--version` execution or version mismatch. A failed Verify in persistent interactive mode terminates the session nonzero so a subsequent Exit cannot conceal it.

Metadata unavailability is **not** local failure. Audit remains the explicit online fleet assessment and may use stricter required-metadata failure semantics.

## What Verify does not do

Verify does not build projects; repair, reinstall, update, remove, or hash installed SDK trees; verify independent publisher identity; manage System SDKs; or alter the normal PATH. It creates and removes only a temporary verification working directory, never changes the isolated installation. Install-time archive SHA-512 verification remains a separate integrity boundary.

See [Interactive mode](interactive.md), [Native-command failure boundaries](../contracts/native-command-failures.md), and [Supply-chain integrity](../concepts/supply-chain-integrity.md).
