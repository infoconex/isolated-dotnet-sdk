# Interactive mode

The tool has two intentional invocation modes: a persistent interactive session and explicit one-shot commands.

For the exact command that starts the tool on your platform, see [Windows / PowerShell](../getting-started/windows-powershell.md#start-an-interactive-session) or [Linux and macOS / Bash](../getting-started/linux-macos-bash.md#start-an-interactive-session).

## Persistent Main session

Starting the tool without an action or exact version opens Main:

```text
What would you like to do?

  I. Install an SDK
  R. Remove an isolated SDK
  L. List installed SDKs

  E. Exit

Selection:
```

Main commands are case-insensitive. `I`, `R`, `L`, and `E` are the product commands; old numeric Main aliases are rejected rather than retained silently.

After a successful Install, List, or Remove operation, or after a normal cancellation/no-change result, the persistent session returns to Main. A genuine operational failure terminates nonzero rather than returning to Main where a later Exit could mask it.

## One-shot commands

Supplying an explicit action or the supported bare-version Install form keeps execution one-shot. The tool performs that requested operation once and exits after success, normal cancellation/no-change, or failure.

An explicit Install or Remove may still need an interactive picker when no version was supplied. That does not convert the command into a persistent Main session.

Verify is always direct-command-only and never appears on Main.

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
└─ Remove
   └─ SDK selection
      └─ Back → Main
```

Persistent menus do not add a redundant `Q. Cancel` where Back already provides navigation. Explicit one-shot Install/Remove pickers may use `Q` to cancel that one-shot command successfully.

Ordinary yes/no confirmation prompts are not navigation menus. Declining a confirmation is a normal no-change result; in persistent mode that returns to Main, while one-shot execution exits successfully.

## Channel selection

Interactive Install loads Microsoft's published release metadata and initially shows supported/development channels. `S` switches between the supported/development and end-of-life channel views. `M` allows manual exact-version entry. `B` returns to Main in a persistent session, and `E` exits it.

Channel menu numbers are derived from current metadata rather than fixed product constants.

## SDK version selection

The default SDK picker is intentionally compact:

- Microsoft's `latest-sdk` is shown first and marked `latest` when that metadata is present and resolves to an SDK in the selected channel;
- the newest SDK from each other available feature band is also shown;
- older servicing releases remain available through **Show all versions**;
- the expanded view is deterministically newest-first;
- Back remains available from compact and expanded views; and
- manual exact-version entry remains available.

SDK choices may be marked `latest`, `isolated`, and/or `system` to describe current metadata and ownership state.

The picker does not depend on fixed numeric positions for a particular SDK version.

## Input failure versus cancellation

Unavailable required interactive input is an operational failure and returns nonzero with repository-owned context. End-of-input is not silently treated as user cancellation.

An explicit user cancellation or default-no confirmation remains a successful no-change result where the prompt contract allows it.

## Related contracts

- [Install](install.md)
- [Remove](remove.md)
- [SDK discovery and release metadata](../concepts/sdk-discovery.md)
- [PowerShell and Bash behavioral parity](../contracts/behavioral-parity.md)
