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

Audit does not accept an SDK-version argument. In a persistent interactive session, `A` runs the same assessment and returns to Main after success.

## Output groups

Audit preserves ownership boundaries:

1. **Isolated SDKs** are recognized SDKs under the user-owned isolated SDK root.
2. **System SDKs** are SDKs reported by the normally resolved `dotnet --list-sdks` host and remain read-only.

The same exact version may appear in both groups. Audit keeps both entries rather than collapsing ownership.

## Row format

For a recognized channel, Audit reports the installed SDK as:

```text
<version>  <LTS|STS>  <status>  <date fields>
```

For example:

```text
11.0.100-rc.1.26425.128  STS  RC1          Release date: 2026-09-08  Go Live: 2026-11-10
10.0.401                 LTS  Current      Release date: 2026-09-08  End of support: 2028-11-14
9.0.318                  STS  Maintenance  Release date: 2026-09-08  End of support: 2026-11-10
7.0.410                  STS  EOL          Release date: 2024-05-28  End of support: 2024-05-14
```

All date-bearing fields remain at the end of the row.

## Statuses

Audit can report:

- `Current` — the installed SDK equals Microsoft's known latest SDK for an active channel;
- `Update available -> <version>` — Microsoft metadata identifies a newer SDK in the channel;
- `Security update available -> <version>` — a newer release in Microsoft channel metadata is marked as a security release;
- `Maintenance` — the channel is in maintenance; when an older SDK also has an update, the servicing result appears before this token;
- exact prerelease labels such as `Preview 5`, `RC1`, or `RC2`, derived from the installed SDK version;
- `EOL` — the channel is end of life; this lifecycle state takes precedence over update wording;
- `Unsupported` — Microsoft metadata exposes a lifecycle phase the tool does not classify as supported;
- `Newer than known metadata` — the installed version sorts newer than Microsoft's current `latest-sdk`; and
- `Unknown channel` — the installed SDK's channel is not present in the current release index.

In styled terminal output, only the `Current`, `Maintenance`, or `EOL` status token receives lifecycle color: green, yellow, or red respectively. Captured and redirected output remains ANSI-free.

## Dates

- `Release date` is the release date of the exact installed SDK version's matching Microsoft release record.
- `Go Live` is shown for a Go-Live channel only when Microsoft publishes an authoritative future GA date.
- `End of support` is shown whenever the release index publishes `eol-date`, including channels that are already EOL.

Release date and end-of-support date are independent facts. Audit does not assume that an SDK's release date must precede the channel's end-of-support date.

## Security wording

`Security update available` is intentionally narrower than a vulnerability claim. It means Microsoft release metadata marks a newer release containing the applicable SDK version as a security release. Audit does **not** claim that the installed SDK is vulnerable, map the installed SDK to a specific CVE, or perform an independent vulnerability scan.

Prerelease movement is not promoted to `Security update available`; preview/release-candidate SDKs can still report an ordinary update plus their lifecycle state.

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
