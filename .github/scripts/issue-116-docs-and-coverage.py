from pathlib import Path


def replace_exact(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    if old not in text:
        raise SystemExit(f"expected anchor not found in {path}: {old[:120]!r}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")


# Expand deterministic Audit lifecycle/failure coverage in PowerShell.
path = Path("tests/powershell/audit.Tests.ps1")
text = path.read_text(encoding="utf-8")
text = text.replace(
    '{ "channel-version": "11.0", "latest-sdk": "11.0.100-rc.2.999", "support-phase": "preview", "release-type": "sts", "releases.json": "https://example.invalid/11.0.json" },',
    '{ "channel-version": "12.0", "latest-sdk": "12.0.100-preview.2.999", "support-phase": "preview", "release-type": "sts", "releases.json": "https://example.invalid/12.0.json" },\n'
    '    { "channel-version": "11.0", "latest-sdk": "11.0.100-rc.2.999", "support-phase": "go-live", "release-type": "sts", "releases.json": "https://example.invalid/11.0.json" },',
    1,
)
text = text.replace(
    '{ "channel-version": "7.0", "latest-sdk": "7.0.410", "support-phase": "eol", "release-type": "sts", "releases.json": "https://example.invalid/7.0.json" }',
    '{ "channel-version": "7.0", "latest-sdk": "7.0.410", "support-phase": "eol", "release-type": "sts", "releases.json": "https://example.invalid/7.0.json" },\n'
    '    { "channel-version": "6.0", "latest-sdk": "6.0.428", "support-phase": "unsupported", "release-type": "lts", "releases.json": "https://example.invalid/6.0.json" }',
    1,
)
replace_marker = "'@ | Set-Content -LiteralPath (Join-Path $script:MetadataRoot '11.0.json')\n        }"
replace_value = """'@ | Set-Content -LiteralPath (Join-Path $script:MetadataRoot '11.0.json')
            @'
{"releases":[
  {"release-date":"2026-09-01","security":false,"sdk":{"version":"12.0.100-preview.1.111"}},
  {"release-date":"2026-10-01","security":true,"sdk":{"version":"12.0.100-preview.2.999"}}
]}
'@ | Set-Content -LiteralPath (Join-Path $script:MetadataRoot '12.0.json')
            @'
{"releases":[
  {"release-date":"2024-11-01","security":false,"sdk":{"version":"6.0.428"}}
]}
'@ | Set-Content -LiteralPath (Join-Path $script:MetadataRoot '6.0.json')
        }"""
if replace_marker not in text:
    raise SystemExit("PowerShell channel fixture anchor missing")
text = text.replace(replace_marker, replace_value, 1)
text = text.replace(
    "@('10.0.401', '9.0.306', '8.0.303', '7.0.410', '11.0.100-rc.1.111')",
    "@('12.0.100-preview.1.111', '11.0.100-rc.1.111', '10.0.401', '9.0.306', '8.0.303', '7.0.410', '6.0.428')",
    1,
)
text = text.replace(
    "$result.Text | Should -Match '11\\.0\\.100-rc\\.1\\.111  Update available -> 11\\.0\\.100-rc\\.2\\.999  Preview'",
    "$result.Text | Should -Match '12\\.0\\.100-preview\\.1\\.111  Update available -> 12\\.0\\.100-preview\\.2\\.999  Preview'\n"
    "        $result.Text | Should -Match '11\\.0\\.100-rc\\.1\\.111  Update available -> 11\\.0\\.100-rc\\.2\\.999  Go Live'\n"
    "        $result.Text | Should -Match '6\\.0\\.428  Unsupported'",
    1,
)
text = text.replace("Add-IsolatedSdk -Version '12.0.100'", "Add-IsolatedSdk -Version '13.0.100'", 1)
text = text.replace("12\\.0\\.100  Unknown channel", "13\\.0\\.100  Unknown channel", 1)
marker = "\n    It 'fails clearly when required channel metadata is malformed' {"
addition = """

    It 'fails clearly when required channel metadata cannot be obtained' {
        Add-IsolatedSdk -Version '10.0.401'
        $env:AUDIT_FAIL_CHANNEL = '10.0'

        $result = Invoke-TestAudit

        $result.ExitCode | Should -Not -Be 0
        $result.Text | Should -Match 'Unable to load release metadata for \.NET 10\.0\.'
        $result.Text | Should -Not -Match '10\.0\.401  Current'
    }
"""
if marker not in text:
    raise SystemExit("PowerShell channel failure test anchor missing")
text = text.replace(marker, addition + marker, 1)
path.write_text(text, encoding="utf-8")


# Expand the same contract coverage in Bash.
path = Path("tests/bash/audit.bats")
text = path.read_text(encoding="utf-8")
text = text.replace(
    '{ "channel-version": "11.0", "latest-sdk": "11.0.100-rc.2.999", "support-phase": "preview", "release-type": "sts", "releases.json": "https://example.invalid/11.0.json" },',
    '{ "channel-version": "12.0", "latest-sdk": "12.0.100-preview.2.999", "support-phase": "preview", "release-type": "sts", "releases.json": "https://example.invalid/12.0.json" },\n'
    '    { "channel-version": "11.0", "latest-sdk": "11.0.100-rc.2.999", "support-phase": "go-live", "release-type": "sts", "releases.json": "https://example.invalid/11.0.json" },',
    1,
)
text = text.replace(
    '{ "channel-version": "7.0", "latest-sdk": "7.0.410", "support-phase": "eol", "release-type": "sts", "releases.json": "https://example.invalid/7.0.json" }',
    '{ "channel-version": "7.0", "latest-sdk": "7.0.410", "support-phase": "eol", "release-type": "sts", "releases.json": "https://example.invalid/7.0.json" },\n'
    '    { "channel-version": "6.0", "latest-sdk": "6.0.428", "support-phase": "unsupported", "release-type": "lts", "releases.json": "https://example.invalid/6.0.json" }',
    1,
)
old = """  cat > "$metadata_root/11.0.json" <<'JSON'
{"releases":[
  {"release-date":"2026-09-01","security":false,"sdk":{"version":"11.0.100-rc.1.111","files":[{"url":"https://builds.dotnet.microsoft.com/dotnet/Sdk/11.0.100-rc.1.111/archive.tgz"}]}},
  {"release-date":"2026-10-01","security":true,"sdk":{"version":"11.0.100-rc.2.999","files":[{"url":"https://builds.dotnet.microsoft.com/dotnet/Sdk/11.0.100-rc.2.999/archive.tgz"}]}}
]}
JSON
}"""
new = old[:-1] + """  cat > "$metadata_root/12.0.json" <<'JSON'
{"releases":[
  {"release-date":"2026-09-01","security":false,"sdk":{"version":"12.0.100-preview.1.111","files":[{"url":"https://builds.dotnet.microsoft.com/dotnet/Sdk/12.0.100-preview.1.111/archive.tgz"}]}},
  {"release-date":"2026-10-01","security":true,"sdk":{"version":"12.0.100-preview.2.999","files":[{"url":"https://builds.dotnet.microsoft.com/dotnet/Sdk/12.0.100-preview.2.999/archive.tgz"}]}}
]}
JSON
  cat > "$metadata_root/6.0.json" <<'JSON'
{"releases":[
  {"release-date":"2024-11-01","security":false,"sdk":{"version":"6.0.428","files":[{"url":"https://builds.dotnet.microsoft.com/dotnet/Sdk/6.0.428/archive.tgz"}]}}
]}
JSON
}"""
if old not in text:
    raise SystemExit("Bash channel fixture anchor missing")
text = text.replace(old, new, 1)
old_versions = """  add_isolated_sdk '10.0.401'
  add_isolated_sdk '9.0.306'
  add_isolated_sdk '8.0.303'
  add_isolated_sdk '7.0.410'
  add_isolated_sdk '11.0.100-rc.1.111'"""
new_versions = """  add_isolated_sdk '12.0.100-preview.1.111'
  add_isolated_sdk '11.0.100-rc.1.111'
  add_isolated_sdk '10.0.401'
  add_isolated_sdk '9.0.306'
  add_isolated_sdk '8.0.303'
  add_isolated_sdk '7.0.410'
  add_isolated_sdk '6.0.428'"""
if old_versions not in text:
    raise SystemExit("Bash installed fixture anchor missing")
text = text.replace(old_versions, new_versions, 1)
text = text.replace(
    '  [[ "$output" == *"11.0.100-rc.1.111  Update available -> 11.0.100-rc.2.999  Preview"* ]]',
    '  [[ "$output" == *"12.0.100-preview.1.111  Update available -> 12.0.100-preview.2.999  Preview"* ]]\n'
    '  [[ "$output" == *"11.0.100-rc.1.111  Update available -> 11.0.100-rc.2.999  Go Live"* ]]\n'
    '  [[ "$output" == *"6.0.428  Unsupported"* ]]',
    1,
)
text = text.replace("add_isolated_sdk '12.0.100'", "add_isolated_sdk '13.0.100'", 1)
text = text.replace('12.0.100  Unknown channel', '13.0.100  Unknown channel', 1)
marker = '@test "audit fails clearly when required channel metadata is malformed" {'
addition = """@test "audit fails clearly when required channel metadata cannot be obtained" {
  add_isolated_sdk '10.0.401'
  export AUDIT_FAIL_CHANNEL='10.0'

  run_audit

  [ "$status" -ne 0 ]
  [[ "$output" == *"Unable to load release metadata for .NET 10.0."* ]]
  [[ "$output" != *"10.0.401  Current"* ]]
}

"""
if marker not in text:
    raise SystemExit("Bash channel failure test anchor missing")
text = text.replace(marker, addition + marker, 1)
path.write_text(text, encoding="utf-8")


# Real direct-command E2E covers the online Audit path without pinning moving status text.
replace_exact(
    "tests/e2e/bash/direct.sh",
    """if ! grep -Fq "$sdk_version" <<<"$list_output"; then
  printf 'List output did not contain installed SDK %s.\\n' "$sdk_version" >&2
  exit 1
fi

echo "E2E direct: removing .NET SDK $sdk_version"""",
    """if ! grep -Fq "$sdk_version" <<<"$list_output"; then
  printf 'List output did not contain installed SDK %s.\\n' "$sdk_version" >&2
  exit 1
fi

audit_output="$(bash "$saved_tool" audit)"
printf '%s\\n' "$audit_output"
if ! grep -Fq '.NET SDK audit' <<<"$audit_output" || ! grep -Fq "$sdk_version" <<<"$audit_output"; then
  printf 'Audit output did not assess installed SDK %s.\\n' "$sdk_version" >&2
  exit 1
fi

echo "E2E direct: removing .NET SDK $sdk_version"""",
)
replace_exact(
    "tests/e2e/powershell/direct.ps1",
    """    if ($list.Output -notmatch [regex]::Escape($sdkVersion)) {
        throw "List output did not contain installed SDK $sdkVersion."
    }

    Write-Host "E2E direct: removing .NET SDK $sdkVersion"""",
    """    if ($list.Output -notmatch [regex]::Escape($sdkVersion)) {
        throw "List output did not contain installed SDK $sdkVersion."
    }

    $audit = Invoke-E2EProcess `
        -FilePath 'pwsh' `
        -Arguments @('-NoProfile', '-File', $savedTool, '-Action', 'Audit')
    Assert-Success -Result $audit -Operation 'Direct audit'
    Write-Host $audit.Output
    if ($audit.Output -notmatch [regex]::Escape('.NET SDK audit') -or
        $audit.Output -notmatch [regex]::Escape($sdkVersion)) {
        throw "Audit output did not assess installed SDK $sdkVersion."
    }

    Write-Host "E2E direct: removing .NET SDK $sdkVersion"""",
)


audit_doc = r'''# Audit

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
'''
Path("docs/commands/audit.md").write_text(audit_doc, encoding="utf-8")


replace_exact(
    "docs/commands/README.md",
    "- [List](list.md) — show Isolated SDKs and read-only System SDKs\n- [Verify](verify.md) — perform a read-only health check of one isolated SDK",
    "- [List](list.md) — show Isolated SDKs and read-only System SDKs\n- [Audit](audit.md) — assess installed SDK servicing and lifecycle state against current Microsoft metadata\n- [Verify](verify.md) — perform a read-only health check of one isolated SDK",
)
replace_exact(
    "docs/commands/README.md",
    "The tool owns SDKs only under the current user's `dotnet-sdks` directory. System SDKs are supplemental read-only inventory and never become removable merely because the tool can see them.",
    "The tool owns SDKs only under the current user's `dotnet-sdks` directory. System SDKs are supplemental read-only inventory and never become removable merely because the tool can see them. List and Verify stay local; Audit is the explicit online read-only operation for servicing and lifecycle assessment.",
)

replace_exact(
    "docs/commands/interactive.md",
    "  L. List installed SDKs\n  V. Verify an isolated SDK\n\n  E. Exit",
    "  L. List installed SDKs\n  V. Verify an isolated SDK\n  A. Audit installed SDKs\n\n  E. Exit",
)
replace_exact(
    "docs/commands/interactive.md",
    "Main commands are case-insensitive. `I`, `R`, `L`, `V`, and `E` are the product commands;",
    "Main commands are case-insensitive. `I`, `R`, `L`, `V`, `A`, and `E` are the product commands;",
)
replace_exact(
    "docs/commands/interactive.md",
    "After a successful Install, List, Remove, or Verify operation,",
    "After a successful Install, List, Audit, Remove, or Verify operation,",
)
replace_exact(
    "docs/commands/interactive.md",
    "Explicit Verify remains a one-shot exact-version command. Interactive Verify is available separately from Main and selects from the installed isolated SDK inventory.\n",
    "Explicit Verify remains a one-shot exact-version command. Interactive Verify is available separately from Main and selects from the installed isolated SDK inventory.\n\nExplicit Audit is a one-shot online assessment of both installed ownership groups. Interactive Audit runs the same read-only assessment from Main with `A` and returns to Main after success.\n",
)
replace_exact(
    "docs/commands/interactive.md",
    "- [Verify](verify.md)\n- [SDK discovery and release metadata]",
    "- [Verify](verify.md)\n- [Audit](audit.md)\n- [SDK discovery and release metadata]",
)

for guide, language, command in (
    ("docs/getting-started/windows-powershell.md", "powershell", '& "$HOME\\dotnet-sdks\\isolated-dotnet-sdk.ps1" -Action Audit'),
    ("docs/getting-started/linux-macos-bash.md", "bash", '"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" audit'),
):
    replace_exact(
        guide,
        "The persistent session uses `I` for Install, `R` for Remove, `L` for List, `V` for Verify, and `E` for Exit.",
        "The persistent session uses `I` for Install, `R` for Remove, `L` for List, `V` for Verify, `A` for Audit, and `E` for Exit.",
    )
    p = Path(guide)
    text = p.read_text(encoding="utf-8")
    marker = "## Verify an isolated SDK\n"
    if marker not in text:
        raise SystemExit(f"Verify section anchor missing in {guide}")
    block = (
        "## Audit installed SDKs\n\n"
        "Run the explicit online, read-only servicing and lifecycle assessment:\n\n"
        f"```{language}\n{command}\n```\n\n"
        "Audit reports Isolated SDKs and System SDKs separately and uses current Microsoft release metadata. It does not install, remove, or repair SDKs. See [Audit](../commands/audit.md).\n\n"
    )
    p.write_text(text.replace(marker, block + marker, 1), encoding="utf-8")

replace_exact(
    "README.md",
    "  L. List installed SDKs\n\n  E. Exit",
    "  L. List installed SDKs\n  V. Verify an isolated SDK\n  A. Audit installed SDKs\n\n  E. Exit",
)
replace_exact(
    "README.md",
    "Explicit Install, List, Verify, Remove, and exact-version invocations remain one-shot for scripting and automation.",
    "Explicit Install, List, Audit, Verify, Remove, and exact-version invocations remain one-shot for scripting and automation.",
)
replace_exact(
    "README.md",
    "- **List** recognized Isolated SDKs first, followed by read-only System SDKs visible through the normally resolved `dotnet` host.\n- **Verify** one installed isolated SDK",
    "- **List** recognized Isolated SDKs first, followed by read-only System SDKs visible through the normally resolved `dotnet` host.\n- **Audit** installed Isolated and System SDKs against current Microsoft servicing and lifecycle metadata without mutating either inventory.\n- **Verify** one installed isolated SDK",
)

replace_exact(
    "_data/navigation.yml",
    "    - title: List\n      path: docs/commands/list.md\n    - title: Verify",
    "    - title: List\n      path: docs/commands/list.md\n    - title: Audit\n      path: docs/commands/audit.md\n    - title: Verify",
)

replace_exact(
    "docs/contracts/behavioral-parity.md",
    "| Persistent Main menu | Use case-insensitive `I` / `R` / `L` / `V` / `E` for Install / Remove / List / Verify / Exit.",
    "| Persistent Main menu | Use case-insensitive `I` / `R` / `L` / `V` / `A` / `E` for Install / Remove / List / Verify / Audit / Exit.",
)
replace_exact(
    "docs/contracts/behavioral-parity.md",
    "| Explicit List plus Version | Reject the version instead of silently ignoring it. |\n| Explicit Verify with an exact version |",
    "| Explicit List plus Version | Reject the version instead of silently ignoring it. |\n| Audit | Perform an online, read-only assessment of both ownership groups against current Microsoft release metadata. Preserve duplicate versions across Isolated and System groups; report servicing and lifecycle without mutating either inventory or labeling an installed SDK `Vulnerable`. |\n| Audit metadata failure | Fail nonzero when required release-index or known-channel metadata is unavailable or structurally unusable rather than emitting fabricated results. Unknown installed channels remain explicit per-SDK results. |\n| Explicit Audit plus Version | Reject the version instead of silently ignoring it. |\n| Explicit Verify with an exact version |",
)
replace_exact(
    "docs/contracts/behavioral-parity.md",
    "- Main provides mnemonic `I. Install`, `R. Remove`, `L. List`, `V. Verify`, and `E. Exit` commands;",
    "- Main provides mnemonic `I. Install`, `R. Remove`, `L. List`, `V. Verify`, `A. Audit`, and `E. Exit` commands;",
)

replace_exact(
    "docs/concepts/sdk-discovery.md",
    "Once an exact SDK version has been resolved, installation separately retrieves Microsoft's exact-version release metadata to identify the supported platform archive and its published SHA-512.",
    "Audit is the other intentional online consumer of release metadata. It uses the release index plus each known installed channel's release data to compare both Isolated and System SDKs with current servicing and lifecycle state. List and Verify do not use this online path.\n\nOnce an exact SDK version has been resolved, installation separately retrieves Microsoft's exact-version release metadata to identify the supported platform archive and its published SHA-512.",
)
replace_exact(
    "docs/concepts/sdk-discovery.md",
    "Display-only metadata such as `latest-sdk` and `release-type` may be absent without invalidating an otherwise selectable channel.",
    "For Install discovery, display-only metadata such as `latest-sdk` and `release-type` may be absent without invalidating an otherwise selectable channel. Audit requires `latest-sdk` for a known installed channel because update state cannot be assessed safely without it.",
)
replace_exact(
    "docs/concepts/sdk-discovery.md",
    "- exact-version installation remains independent from release-index/channel discovery while still using exact-version release metadata for payload integrity.",
    "- exact-version installation remains independent from release-index/channel discovery while still using exact-version release metadata for payload integrity;\n- Audit is the explicit online inventory-assessment boundary, while List and Verify remain independent of release metadata.",
)

replace_exact(
    "docs/maintainers/testing/testing.md",
    "- release-metadata transport/shape failures, required selection fields, no-SDK channel data, first-seen duplicate ordering, and exact-version metadata independence;",
    "- release-metadata transport/shape failures, required selection fields, no-SDK channel data, first-seen duplicate ordering, and exact-version metadata independence;\n- Audit servicing/lifecycle states, security precedence, preview and Go Live behavior, unsupported/EOL channels, ownership overlap, metadata failures, interactive navigation, and List/Verify network independence;",
)
replace_exact(
    "docs/maintainers/testing/testing.md",
    "- release-metadata transport/shape behavior, required selection fields, no-SDK channel data, duplicate normalization, and exact-version metadata independence;",
    "- release-metadata transport/shape behavior, required selection fields, no-SDK channel data, duplicate normalization, and exact-version metadata independence;\n- Audit servicing/lifecycle states, security precedence, preview and Go Live behavior, unsupported/EOL channels, ownership overlap, metadata failures, interactive navigation, and List/Verify network independence;",
)

replace_exact(
    "docs/maintainers/testing/e2e-testing.md",
    "5. run List and require the configured isolated version to appear in the installed-SDK output;\n6. remove the configured SDK;\n7. require the isolated SDK directory to be absent afterward.",
    "5. run List and require the configured isolated version to appear in the installed-SDK output;\n6. run Audit against live Microsoft metadata and require the configured isolated version to be assessed, without pinning a transient servicing status;\n7. remove the configured SDK;\n8. require the isolated SDK directory to be absent afterward.",
)
replace_exact(
    "docs/maintainers/testing/e2e-testing.md",
    "The live suite is deliberately small. It does not replace deterministic tests for metadata failures, network failures, filesystem boundaries, transactional install behavior, native-command propagation, cleanup, invalid input, or other exhaustive edge cases.",
    "The live suite is deliberately small. Its Audit assertion proves the real online metadata path and installed-version reporting, but deliberately does not pin a moving Current/Update/Security/Maintenance result. It does not replace deterministic tests for metadata failures, network failures, lifecycle/security classification, filesystem boundaries, transactional install behavior, native-command propagation, cleanup, invalid input, or other exhaustive edge cases.",
)
