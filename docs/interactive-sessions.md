# Interactive sessions and menu navigation

The tool has two intentionally different invocation modes.

## Persistent interactive session

Run the saved tool without an action or exact SDK version when you want to work interactively:

```powershell
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1"
```

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh"
```

A no-action invocation stays in one interactive session. After a successful Install, List, or Remove operation, the tool returns to Main. Normal cancellation or a no-change result also returns to Main. `E`/`e` is the global persistent-session Exit command and is available from Main and each persistent selection menu, so you do not need to navigate back to Main before exiting. Main no longer exposes a numeric `4. Exit` action, and `4` is not retained as an undocumented Exit alias.

A genuine operational failure is different from navigation or cancellation. Metadata, filesystem, payload acquisition/checksum/extraction, native-command, verification, cleanup, and other correctness-significant failures terminate the process nonzero immediately. The session does not return to Main after such a failure, so a later Exit cannot hide it.

## One-shot commands

Explicit commands remain automation-friendly and do not enter the persistent Main loop:

```powershell
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1" -Action List
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1" -Action Install -Version '10.0.401'
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1" -Action Remove -Version '10.0.401' -Yes
```

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" list
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" install 10.0.401
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" remove 10.0.401 --yes
```

The bare-version Install convenience form is also one-shot. Exact-version installation bypasses Microsoft release-index/channel discovery but still retrieves the exact version's release metadata to resolve and verify the platform SDK archive.

## Back, Exit, and cancellation

Back is available only on selection menus where there is a meaningful parent menu:

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

Ordinary yes/no confirmation prompts are not navigation menus. Declining a confirmation remains a normal cancellation/no-change result. In a persistent session, that result returns to Main; in a one-shot invocation, the command exits successfully without making the declined change.

Persistent selection menus use `E`/`e` for Exit and do not expose a redundant menu-level Cancel choice where Back already provides the navigation path. `B`/`b` moves to the documented parent selection menu. Explicit one-shot Install/Remove selection may still use `Q`/`q` to cancel that one-shot command successfully, because there is no persistent session to exit.

## SDK version picker

After selecting a .NET channel, the default picker keeps the list short:

- Microsoft's `latest-sdk` is shown first and marked `latest` when that metadata is present and the SDK appears in the selected channel data;
- the newest SDK from every other available feature band is also shown;
- older servicing releases are available through **Show all versions**;
- the expanded list is ordered deterministically from newest to oldest;
- **Back to .NET channels** remains available in either view;
- manual exact-version entry remains available;
- `E. Exit` leaves a persistent interactive session directly from either compact or expanded picker views, while explicit one-shot pickers retain `Q. Cancel`.

For example, if a channel contains multiple `10.0.4xx`, `10.0.3xx`, and `10.0.2xx` servicing releases, the compact view shows the newest SDK from each of those feature bands rather than every servicing release at once.

The picker does not depend on fixed numeric positions for particular SDK versions. Menu numbers are presentation details derived from the currently displayed data.

Microsoft's `latest-sdk` field is optional display metadata. If it is absent, the tool still presents the channel's SDKs in deterministic order but does not invent a `latest` marker.

## Related contracts

See [`behavioral-parity.md`](behavioral-parity.md) for the authoritative cross-shell behavioral contract, [`release-metadata.md`](release-metadata.md) for metadata failure and discovery boundaries, and [`testing.md`](testing.md) for repository validation guidance.
