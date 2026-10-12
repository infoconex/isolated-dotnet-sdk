# Audit

Audit is the explicit online, read-only assessment for installed .NET SDK servicing and lifecycle state. It compares both Isolated SDKs and read-only System SDKs with current Microsoft release metadata without installing, removing, repairing, or changing either inventory.

Use Audit when you want to know whether an installed SDK is current for its channel, has a newer servicing release, is in maintenance, or has reached end of life. Use [List](list.md) when you only need local inventory, and use [Verify](verify.md) when you need a local health check of one exact isolated SDK.

## Direct commands

PowerShell:

```powershell
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1" -Action Audit
```

Bash:

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" audit
```

Audit does not accept an SDK-version argument. In a terminal-backed persistent interactive session, `A` runs the same assessment and keeps the completed report visible at `Press Enter to return to Main...` until Enter returns to Main. Redirected or captured persistent execution skips that pause.

## Output groups

Audit preserves ownership boundaries:

1. **Isolated SDKs** are recognized SDKs under the user-owned isolated SDK root.
2. **System SDKs** are SDKs reported by the normally resolved `dotnet --list-sdks` host and remain read-only.

The same exact version may appear in both groups. Audit keeps both entries rather than collapsing ownership.

## Row format

For a recognized channel, Audit uses this compact semantic order:

```text
<version>  <LTS|STS>  <lifecycle/status>  <date facts>  <optional update/detail>
```

Version, release type, and lifecycle/status are aligned across the complete Audit result. Each ownership group is sorted by SDK version newest to oldest.

Date facts remain compact and appear in this order when present:

```text
Release: <date>  Go Live: <date>  EOS: <date>
```

Absent date facts do not reserve blank columns. When Microsoft metadata identifies a newer SDK, Audit appends `Update -> <version>` at the end of the row without reserving width on rows that are already current.

For example:

```text
Isolated SDKs:
  11.0.100-rc.1.26425.128  STS  RC1      Release: 2026-09-08  Go Live: 2026-11-10  Update -> 11.0.100-rc.2.999
  10.0.401                 LTS  Current  Release: 2026-09-08  EOS: 2028-11-14
  10.0.100                 LTS  Active   Release: 2025-11-11  EOS: 2028-11-14  Update -> 10.0.401

System SDKs:
  10.0.401                 LTS  Current      Release: 2026-09-08  EOS: 2028-11-14
  9.0.318                  STS  Maintenance  Release: 2026-09-08  EOS: 2026-11-10
  8.0.425                  LTS  Maintenance  Release: 2026-09-08  EOS: 2026-11-10
```

`Current` is reserved for the exact SDK that matches Microsoft's current `latest-sdk` on an active channel. Other installed SDKs in that active channel use `Active`.

## Statuses

Audit can report:

- `Current` — the installed SDK equals Microsoft's known latest SDK for an active channel;
- `Active` — the channel is active, but the installed SDK is not the current `latest-sdk`;
- `Maintenance` — the channel is in maintenance;
- exact prerelease labels such as `Preview 5`, `RC1`, or `RC2`, derived from the installed SDK version;
- `EOL` — the channel is end of life;
- `Unsupported` — Microsoft metadata exposes a lifecycle phase the tool does not classify as supported;
- `Newer than known metadata` — the installed version sorts newer than Microsoft's current `latest-sdk`; and
- `Unknown channel` — the installed SDK's channel is not present in the current release index.

When a newer SDK is available, Audit appends `Update -> <version>` after the date facts. Audit intentionally uses the same concise presentation whether Microsoft marks that newer release as an ordinary servicing release or a security release. The structured classification retains that distinction for other command logic.

In styled terminal output, only the `Current`, `Maintenance`, or `EOL` status token receives lifecycle color: green, yellow, or red respectively. Captured and redirected output remains ANSI-free.

## Dates

- `Release` is the release date of the exact installed SDK version's matching Microsoft release record.
- `Go Live` is shown for a Go-Live channel only when Microsoft publishes an authoritative future GA date.
- `EOS` is shown whenever the release index publishes `eol-date`, including channels that are already EOL.

Release date and end-of-support date are independent facts. Audit does not assume that an SDK's release date must precede the channel's end-of-support date.

## Update wording

`Update -> <version>` means Microsoft metadata identifies a newer SDK for the channel. Audit does **not** claim that the installed SDK is vulnerable, map it to a specific CVE, or perform an independent vulnerability scan.

## Metadata and failures

Audit is the operation that intentionally depends on current online release metadata. For each known installed channel it requires a usable `latest-sdk`, `support-phase`, `release-type`, `releases.json`, and channel release set. Required release-index or channel-metadata transport/structural failures terminate Audit nonzero rather than producing partial or fabricated status results.

For a channel whose support phase is `go-live`, the normal release JSON does not necessarily publish the future GA date. Audit therefore uses Microsoft's official [`dotnet/core` release-notes table](https://github.com/dotnet/core/blob/main/release-notes/README.md) as a narrow fallback for that date only. If the fallback is unavailable or does not contain a usable row for the channel, Audit omits the optional `Go Live` date and continues; it does not infer or hard-code a date.

If neither ownership group contains an installed SDK, Audit reports both groups as `None` without requesting Microsoft release metadata.

List and Verify remain local operations and do not gain Audit's network dependency.

## Related commands

- [List](list.md)
- [Verify](verify.md)
- [Install](install.md)
- [Interactive mode](interactive.md)
- [SDK discovery and release metadata](../concepts/sdk-discovery.md)
