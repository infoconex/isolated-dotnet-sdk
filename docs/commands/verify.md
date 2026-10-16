# Verify

Verify is a read-only, detailed single-SDK report for an exact version already installed under the isolated SDK root. **Local proof determines success or failure**; online Microsoft lifecycle/servicing information and installed-component diagnostics are optional enrichment.

For direct-command syntax, see [Windows / PowerShell](../getting-started/windows-powershell.md#verify-an-isolated-sdk) or [Linux and macOS / Bash](../getting-started/linux-macos-bash.md#verify-an-isolated-sdk).

## Invocation modes

Verify is available as a one-shot exact-version command or through `V. Verify an isolated SDK` on the persistent Main menu. The interactive picker lists isolated versions newest to oldest; System SDKs are never targets. Both modes share the same validation and report. Interactive terminal results remain visible until Enter acknowledges them and return to the Verify list. Captured/redirected execution does not pause.

## Detailed report

Verify presents labeled information for one SDK rather than Audit's compact multi-SDK row. It uses Audit's exact classification logic, colors, and release facts (including prerelease labels, Go Live, EOL, release date, EOS date, and available updates). Dates and update fields appear only when available.

Example for a real-style Windows installation of SDK 7.0.410 (the local component values reflect the owner's sample; Microsoft metadata is subject to availability):

```text
Verify isolated .NET SDK

SDK information:
  SDK version         7.0.410
  .NET channel        7.0
  Support type        STS
  Status              EOL
  SDK release date    2024-05-28
  Channel EOS date    2024-05-14

Installed components:
  Host version        7.0.20
  Architecture        x64
  Runtime identifier  win10-x64

  .NET runtimes:
    Microsoft.AspNetCore.App         7.0.20
    Microsoft.NETCore.App            7.0.20
    Microsoft.WindowsDesktop.App     7.0.20

Verification:
  Installation directory  OK  C:\Users\jscot\dotnet-sdks\7.0.410
  .NET host               OK  Host executable found and launched
  SDK inventory           OK  Exact SDK found in isolated installation
  SDK resolution          OK  Correct SDK selected

Isolated SDK 7.0.410 verified successfully.
```

The exact output depends on the installed platform and Microsoft release records. The report intentionally has no standalone `Location:` line; the installation directory appears in the first verification check only. Short successful descriptions avoid repeating the same SDK version/path. Failed checks retain their specific expected/actual/error context.

**SDK information** is Microsoft's online enrichment. It includes SDK version and channel even if Microsoft metadata is unavailable. If the metadata lookup fails, Verify reports `Release/lifecycle   Unavailable (Microsoft metadata could not be loaded).` and continues with local checks. An unknown channel is labeled `Unknown channel`. EOL describes Microsoft support lifecycle, not installation health.

**Installed components** are optional and read-only. For modern hosts, Verify uses the exact isolated `dotnet --info` and `dotnet --list-runtimes` commands in temporary work state with SDK-root and multilevel-lookup isolation controls. It shows the host version, architecture, runtime identifier (RID), and only runtimes whose reported directory matches the isolated `shared/<framework>` root. System runtime entries are excluded. For original **1.x and early 2.x SDK hosts** (2.0.* and 2.1.* before 2.1.300), Verify reads only supported fields from isolated `--info`; it does **not** invoke their unsupported `--list-runtimes` command. Historical `--info` SDK product versions are not treated as host/runtime versions. If a field cannot be established (often host version or runtime inventory for 1.x), the report shows `Unavailable`. Missing optional diagnostics never fail Verify; runtime versions are never derived from SDK versions.

**Verification** reports local checks tailored to the host generation:

- Installation directory — the exact tool-owned version directory exists.
- .NET host — the platform-specific host exists (and is executable on Bash) and successfully launches the necessary local command.
- For modern hosts, **SDK inventory** — `--list-sdks` contains the exact requested SDK **at its actual isolated SDK directory**, not an identical system SDK.
- **SDK resolution** — `--version` resolves the exact requested SDK in a controlled temporary directory with multilevel lookup disabled.
- For original **1.x and early 2.x hosts**, **SDK origin** replaces the unsupported SDK inventory check. Verify requires exactly one valid SDK `Base Path` from the isolated host's successful `--info`, physically resolving to `<isolated-root>/<version>/sdk/<version>`. The exact `--version` result and origin must both agree; a system-installed SDK of the same version cannot substitute for the isolated SDK. Commands execute with a private `global.json` pinned to the requested version, an isolated SDK root, and disabled multilevel lookup; transient work state is removed afterward. Modern host checks and labels are unchanged.

Only `OK` and applicable lifecycle-status tokens are styled in interactive terminals; redirected/captured output is ANSI-free.

## Failures and non-goals

A failed local check is shown as `FAIL` with a precise reason and exits nonzero. Failed Verify in persistent interactive mode terminates the session nonzero so a later Exit cannot conceal the problem. Microsoft metadata and optional diagnostic failure never turn successful local verification into failure.

Verify does not compile applications, repair/reinstall/update/remove SDKs, calculate installation sizes, hash extracted SDK trees, authenticate independent publishers, scan for CVEs, manage System SDKs, change PATH, or alter SDK content. The SHA-512 verification of the Microsoft archive occurs at install time and is a separate integrity boundary.

See [Interactive mode](interactive.md), [Native-command failure boundaries](../contracts/native-command-failures.md), [Supply-chain integrity](../concepts/supply-chain-integrity.md), and [Troubleshooting and safe recovery](../guides/troubleshooting.md).
