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

## Statuses

Audit can report:

- `Current` — the installed SDK equals Microsoft's known latest SDK for an active channel;
- `Update available -> <version>` — Microsoft metadata identifies a newer SDK in the channel;
- `Security update available -> <version>` — a newer release in Microsoft channel metadata is marked as a security release;
- `Maintenance` — the installed SDK is current while its channel is in maintenance;
- `Preview` or `Go Live` — development/release-candidate lifecycle context;
- `End of life` — the channel is end of life; this lifecycle state takes precedence over update wording;
- `Unsupported` — Microsoft metadata exposes a lifecycle phase the tool does not classify as supported;
- `Newer than known metadata` — the installed version sorts newer than Microsoft's current `latest-sdk`; and
- `Unknown channel` — the installed SDK's channel is not present in the current release index.

When an update is available, lifecycle context such as `Maintenance`, `Preview`, or `Go Live` is appended to the servicing result.

## Security wording

`Security update available` is intentionally narrower than a vulnerability claim. It means Microsoft release metadata marks a newer release containing the applicable SDK version as a security release. Audit does **not** claim that the installed SDK is vulnerable, map the installed SDK to a specific CVE, or perform an independent vulnerability scan.

Prerelease movement is not promoted to `Security update available`; preview/release-candidate SDKs can still report an ordinary update plus their lifecycle state.

## Metadata and failures

Audit is the operation that intentionally depends on current online release metadata. For each known installed channel it requires a usable `latest-sdk`, `support-phase`, `releases.json`, and channel release set. Required metadata transport or structural failures terminate Audit nonzero rather than producing partial or fabricated status results.

If neither ownership group contains an installed SDK, Audit reports both groups as `None` without requesting Microsoft release metadata.

List and Verify remain local operations and do not gain Audit's network dependency.

## Related commands

- [List](list.md)
- [Verify](verify.md)
- [Install](install.md)
- [Interactive mode](interactive.md)
- [SDK discovery and release metadata](../concepts/sdk-discovery.md)
