# Interactive mode

The tool has two intentional invocation modes: a persistent interactive session and explicit one-shot commands.

For the exact command that starts the tool on your platform, see [Windows / PowerShell](../getting-started/windows-powershell.md#start-an-interactive-session) or [Linux and macOS / Bash](../getting-started/linux-macos-bash.md#start-an-interactive-session).

## Persistent Main session

Starting the tool without an action or exact version opens Main and identifies the running tool before the action prompt. A stable release uses its exact release tag:

```text
Isolated .NET SDK v1.2.3

What would you like to do?

  I. Install an SDK
  R. Remove an isolated SDK
  L. List installed SDKs
  V. Verify an isolated SDK
  A. Audit installed SDKs

  E. Exit

Selection:
```

Mutable `main` uses the same location but identifies itself as development source instead of claiming a stable release:

```text
Isolated .NET SDK development (main)
```

The identity heading is shown on Main, not repeated throughout nested Install, Remove, or Verify menus. See [Tool version](tool-version.md) for the direct query and stable/development identity contract.

Main commands are case-insensitive. `I`, `R`, `L`, `V`, `A`, and `E` are the product commands; old numeric Main aliases are rejected rather than retained silently.

After a successful Install, List, Audit, Remove, or Verify operation, or after a normal cancellation/no-change result, the persistent session keeps that completed result visible and prompts for Enter before returning to the screen that launched that result.

The prompt names that destination. For example:

```text
Press Enter to return to Main...
Press Enter to return to Verify...
Press Enter to return to Remove...
Press Enter to return to SDK selection...
```

The return hierarchy is deliberate:

- List and Audit return to Main.
- Verify returns to the Verify SDK list.
- Remove returns to the Remove SDK list while isolated SDKs remain; removing the final isolated SDK returns to Main.
- Install from a channel's SDK picker returns to that same channel's SDK list.
- A no-inventory result that never displayed a Verify or Remove picker returns to Main.

Persistent interactive navigation clears the previous screen before the destination menu or completed operation view when the terminal supports clearing. After a completed result, clearing occurs **only after** its Enter acknowledgement and immediately before returning to the indicated parent screen. Back clears on the way to its parent without an acknowledgement. Switching between channel or SDK-picker views also clears when supported. After selecting an SDK to Install, Verify, or Remove, the picker clears before the operation's details or confirmation are displayed, so the operation runs on its own screen. The complete operation output remains visible through its Enter acknowledgement; only then does returning to the parent clear again. Invalid-selection feedback and in-progress output remain visible rather than being erased by automatic redraws. Unsupported terminal capabilities fall back to normal scrolling. On initial persistent-interactive launch, the first Main screen also clears when supported, after startup/bootstrap has succeeded. This may replace successful bootstrap notices such as `Tool installed.` on the active screen; bootstrap errors remain visible because no clear is requested before successful startup. In captured or unsupported terminals, bootstrap output remains in ordinary scrollback.

Screen clearing is strictly a persistent, terminal-backed presentation feature. Explicit one-shot commands, redirected or captured input/output, pipes, CI, and automation do not emit clearing controls.

This acknowledgement is a completed-result boundary, not another decision menu. It is enabled only when both input and output are attached to an interactive terminal. Redirected input, redirected/captured output, pipes, CI, and automation never wait for it; they still follow the same parent-screen navigation without pausing. Back and Exit navigation do not require acknowledgement. A genuine operational failure terminates nonzero rather than navigating to a parent screen where a later successful Exit could mask it.

## One-shot commands

Supplying an explicit action or the supported bare-version Install form keeps execution one-shot. The tool performs that requested operation once and exits after success, normal cancellation/no-change, or failure.

An explicit Install or Remove may still need an interactive picker when no version was supplied. That does not convert the command into a persistent Main session.

Explicit Verify remains a one-shot exact-version command. Interactive Verify is available separately from Main and selects from the installed isolated SDK inventory.

Explicit Audit is a one-shot online assessment of both installed ownership groups. Interactive Audit runs the same read-only assessment from Main with `A`; after success, the result remains visible until Enter acknowledges the return to Main.

The direct tool-version query is also one-shot and exits before bootstrap, network access, SDK discovery, prompting, or mutation. It identifies the tool itself; it does not select a .NET SDK.

## Back, Exit, and Cancel

Persistent selection menus use `E` to exit the whole session directly.

`B` navigates to the meaningful parent selection menu:

```text
Main
├─ Install
│  ├─ Channel selection
│  │  └─ Back → Main
│  └─ SDK version selection
│     └─ Back → Channel selection
├─ Remove
│  └─ SDK selection
│     └─ Back → Main
└─ Verify
   └─ SDK selection
      └─ Back → Main
```

Persistent menus do not add a redundant `Q. Cancel` where Back already provides navigation. Explicit one-shot Install/Remove pickers may use `Q` to cancel that one-shot command successfully.

Ordinary yes/no confirmation prompts are not navigation menus. Declining a confirmation is a normal no-change result; in persistent mode that result waits for Enter acknowledgement before returning to the operation's immediate parent screen, while one-shot execution exits successfully.

## Channel selection

Interactive Install loads Microsoft's published release metadata and initially shows supported/development channels. `S` switches between the supported/development and end-of-life channel views. `M` allows manual exact-version entry. `B` returns to Main in a persistent session, and `E` exits it.

Channel menu numbers are derived from current metadata rather than fixed product constants.

## SDK version selection

The default Install SDK picker is intentionally compact:

- Microsoft's `latest-sdk` is shown first and marked `latest` when that metadata is present and resolves to an SDK in the selected channel;
- the newest SDK from each other available feature band is also shown;
- older servicing releases remain available through **Show all versions**;
- the expanded view is deterministically newest-first;
- Back remains available from compact and expanded views; and
- manual exact-version entry remains available.

Install choices may be marked `latest`, `isolated`, and/or `system` to describe current metadata and ownership state.

The Install picker does not depend on fixed numeric positions for a particular SDK version.

## Verify selection

Interactive Verify lists only recognized isolated SDKs under the isolated SDK root. System SDKs are never offered as Verify targets. Selecting an SDK runs the same read-only health check used by explicit Verify; there is no separate interactive verification implementation.

A healthy result remains visible until Enter acknowledgement, then returns to the Verify SDK list. `B` from that list returns to Main immediately without running verification or requiring acknowledgement, and `E` exits the session. If no isolated SDKs are installed, no Verify picker exists, so the tool reports that state and waits for Enter before returning to Main. If the selected SDK is unhealthy or becomes invalid before verification completes, the operational failure terminates the session nonzero.

## Input failure versus cancellation

Unavailable required interactive input is an operational failure and returns nonzero with repository-owned context. End-of-input is not silently treated as user cancellation.

An explicit user cancellation or default-no confirmation remains a successful no-change result where the prompt contract allows it.

## Related contracts

- [Tool version](tool-version.md)
- [Install](install.md)
- [Remove](remove.md)
- [Verify](verify.md)
- [Audit](audit.md)
- [SDK discovery and release metadata](../concepts/sdk-discovery.md)
- [PowerShell and Bash behavioral parity](../contracts/behavioral-parity.md)
