from pathlib import Path


def replace(path, old, new, count=1):
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    if old not in text:
        raise SystemExit(f"missing anchor in {path}: {old[:100]!r}")
    p.write_text(text.replace(old, new, count), encoding="utf-8")


def append_before_last(path, marker, addition):
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    index = text.rfind(marker)
    if index < 0:
        raise SystemExit(f"missing final marker in {path}: {marker!r}")
    p.write_text(text[:index] + addition + text[index:], encoding="utf-8")


# Deterministic Bash Audit boundaries.
replace(
    "tests/bash/audit.bats",
    '  "releases-index": [\n    { "channel-version": "11.0",',
    '  "releases-index": [\n    { "channel-version": "14.0", "latest-sdk": "14.0.100", "support-phase": "unsupported", "release-type": "sts", "releases.json": "https://example.invalid/14.0.json" },\n    { "channel-version": "13.0", "latest-sdk": "13.0.100-rc.2.222", "support-phase": "go-live", "release-type": "sts", "releases.json": "https://example.invalid/13.0.json" },\n    { "channel-version": "11.0",'
)
replace(
    "tests/bash/audit.bats",
    "  cat > \"$metadata_root/11.0.json\" <<'JSON'\n{\"releases\":[",
    "  cat > \"$metadata_root/14.0.json\" <<'JSON'\n{\"releases\":[\n  {\"release-date\":\"2026-10-01\",\"security\":false,\"sdk\":{\"version\":\"14.0.100\",\"files\":[{\"url\":\"https://builds.dotnet.microsoft.com/dotnet/Sdk/14.0.100/archive.tgz\"}]}}\n]}\nJSON\n  cat > \"$metadata_root/13.0.json\" <<'JSON'\n{\"releases\":[\n  {\"release-date\":\"2026-09-01\",\"security\":false,\"sdk\":{\"version\":\"13.0.100-rc.1.111\",\"files\":[{\"url\":\"https://builds.dotnet.microsoft.com/dotnet/Sdk/13.0.100-rc.1.111/archive.tgz\"}]}},\n  {\"release-date\":\"2026-10-01\",\"security\":true,\"sdk\":{\"version\":\"13.0.100-rc.2.222\",\"files\":[{\"url\":\"https://builds.dotnet.microsoft.com/dotnet/Sdk/13.0.100-rc.2.222/archive.tgz\"}]}}\n]}\nJSON\n  cat > \"$metadata_root/11.0.json\" <<'JSON'\n{\"releases\":["
)
Path("tests/bash/audit.bats").write_text(
    Path("tests/bash/audit.bats").read_text(encoding="utf-8") + r'''

@test "audit reports go-live prerelease movement without inferring a security condition" {
  add_isolated_sdk '13.0.100-rc.1.111'

  run_audit

  [ "$status" -eq 0 ]
  [[ "$output" == *"13.0.100-rc.1.111  Update available -> 13.0.100-rc.2.222  Go Live"* ]]
  [[ "$output" != *"13.0.100-rc.1.111  Security update available"* ]]
}

@test "audit reports unsupported lifecycle metadata explicitly" {
  add_isolated_sdk '14.0.100'

  run_audit

  [ "$status" -eq 0 ]
  [[ "$output" == *"14.0.100  Unsupported"* ]]
}

@test "audit fails clearly when required channel metadata cannot be obtained" {
  add_isolated_sdk '10.0.401'
  export AUDIT_FAIL_CHANNEL='10.0'

  run_audit

  [ "$status" -ne 0 ]
  [[ "$output" == *"Unable to load release metadata for .NET 10.0."* ]]
  [[ "$output" != *"10.0.401  Current"* ]]
}

@test "audit rejects an incomplete known-channel release-index entry" {
  add_isolated_sdk '10.0.401'
  sed -i.bak 's/"latest-sdk": "10.0.401", //' "$metadata_root/releases-index.json"
  rm -f "$metadata_root/releases-index.json.bak"

  run_audit

  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid .NET release metadata for .NET 10.0."* ]]
  [[ "$output" != *"10.0.401  Current"* ]]
}
''',
    encoding="utf-8",
)

# Deterministic PowerShell Audit boundaries.
replace(
    "tests/powershell/audit.Tests.ps1",
    '  "releases-index": [\n    { "channel-version": "11.0",',
    '  "releases-index": [\n    { "channel-version": "14.0", "latest-sdk": "14.0.100", "support-phase": "unsupported", "release-type": "sts", "releases.json": "https://example.invalid/14.0.json" },\n    { "channel-version": "13.0", "latest-sdk": "13.0.100-rc.2.222", "support-phase": "go-live", "release-type": "sts", "releases.json": "https://example.invalid/13.0.json" },\n    { "channel-version": "11.0",'
)
replace(
    "tests/powershell/audit.Tests.ps1",
    "            @'\n{\"releases\":[\n  {\"release-date\":\"2026-09-01\",\"security\":false,\"sdk\":{\"version\":\"11.0.100-rc.1.111\"}},",
    "            @'\n{\"releases\":[\n  {\"release-date\":\"2026-10-01\",\"security\":false,\"sdk\":{\"version\":\"14.0.100\"}}\n]}\n'@ | Set-Content -LiteralPath (Join-Path $script:MetadataRoot '14.0.json')\n            @'\n{\"releases\":[\n  {\"release-date\":\"2026-09-01\",\"security\":false,\"sdk\":{\"version\":\"13.0.100-rc.1.111\"}},\n  {\"release-date\":\"2026-10-01\",\"security\":true,\"sdk\":{\"version\":\"13.0.100-rc.2.222\"}}\n]}\n'@ | Set-Content -LiteralPath (Join-Path $script:MetadataRoot '13.0.json')\n            @'\n{\"releases\":[\n  {\"release-date\":\"2026-09-01\",\"security\":false,\"sdk\":{\"version\":\"11.0.100-rc.1.111\"}},"
)
powershell_boundary_tests = r'''
    It 'reports go-live prerelease movement without inferring a security condition' {
        Add-IsolatedSdk -Version '13.0.100-rc.1.111'

        $result = Invoke-TestAudit

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match '13\.0\.100-rc\.1\.111  Update available -> 13\.0\.100-rc\.2\.222  Go Live'
        $result.Text | Should -Not -Match '13\.0\.100-rc\.1\.111  Security update available'
    }

    It 'reports unsupported lifecycle metadata explicitly' {
        Add-IsolatedSdk -Version '14.0.100'

        $result = Invoke-TestAudit

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match '14\.0\.100  Unsupported'
    }

    It 'fails clearly when required channel metadata cannot be obtained' {
        Add-IsolatedSdk -Version '10.0.401'
        $env:AUDIT_FAIL_CHANNEL = '10.0'

        $result = Invoke-TestAudit

        $result.ExitCode | Should -Not -Be 0
        $result.Text | Should -Match 'Unable to load release metadata for \.NET 10\.0\.'
        $result.Text | Should -Not -Match '10\.0\.401  Current'
    }

    It 'rejects an incomplete known-channel release-index entry' {
        Add-IsolatedSdk -Version '10.0.401'
        $indexPath = Join-Path $script:MetadataRoot 'releases-index.json'
        $index = Get-Content -LiteralPath $indexPath -Raw | ConvertFrom-Json
        ($index.'releases-index' | Where-Object { $_.'channel-version' -eq '10.0' }).'latest-sdk' = ''
        $index | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $indexPath

        $result = Invoke-TestAudit

        $result.ExitCode | Should -Not -Be 0
        $result.Text | Should -Match 'Invalid \.NET release metadata for \.NET 10\.0\.'
        $result.Text | Should -Not -Match '10\.0\.401  Current'
    }

'''
append_before_last("tests/powershell/audit.Tests.ps1", "}", powershell_boundary_tests)

# Public help: make Audit's online boundary visible in PowerShell too.
replace(
    "isolated-dotnet-sdk.ps1",
    "List reports recognized isolated SDKs first and then the read-only SDK inventory returned by the normally resolved dotnet --list-sdks host. System SDK discovery is supplemental rather than an exhaustive filesystem inventory, and system SDKs are never managed by Remove or targeted by Verify.",
    "List reports recognized isolated SDKs first and then the read-only SDK inventory returned by the normally resolved dotnet --list-sdks host. List and Verify remain local operations and do not fetch lifecycle metadata. Audit explicitly retrieves current Microsoft release metadata and assesses installed Isolated and System SDKs without modifying them. System SDK discovery is supplemental rather than an exhaustive filesystem inventory, and system SDKs are never managed by Remove or targeted by Verify."
)
replace(
    "isolated-dotnet-sdk.ps1",
    ".EXAMPLE\n.\\isolated-dotnet-sdk.ps1 -Action Install -SdkVersion 10.0.100",
    ".EXAMPLE\n.\\isolated-dotnet-sdk.ps1 -Action Audit\n\nAudits installed Isolated and System SDKs against current Microsoft release metadata without changing them.\n\n.EXAMPLE\n.\\isolated-dotnet-sdk.ps1 -Action Install -SdkVersion 10.0.100"
)

# Real E2E: assert Audit reaches live metadata and reports the installed version,
# without pinning a transient servicing classification.
replace(
    "tests/e2e/bash/direct.sh",
    'echo "E2E direct: removing .NET SDK $sdk_version"',
    '''audit_output="$(bash "$saved_tool" audit)"
printf '%s\\n' "$audit_output"
if ! grep -Fq '.NET SDK audit' <<<"$audit_output" || ! grep -Fq "$sdk_version" <<<"$audit_output"; then
  printf 'Audit output did not report installed SDK %s.\\n' "$sdk_version" >&2
  exit 1
fi
if grep -Fq 'Vulnerable' <<<"$audit_output"; then
  printf 'Audit output used unsupported vulnerability attribution.\\n' >&2
  exit 1
fi

echo "E2E direct: removing .NET SDK $sdk_version"'''
)
replace(
    "tests/e2e/powershell/direct.ps1",
    '    Write-Host "E2E direct: removing .NET SDK $sdkVersion"',
    '''    $audit = Invoke-E2EProcess `
        -FilePath 'pwsh' `
        -Arguments @('-NoProfile', '-File', $savedTool, '-Action', 'Audit')
    Assert-Success -Result $audit -Operation 'Direct audit'
    Write-Host $audit.Output
    if ($audit.Output -notmatch [regex]::Escape('.NET SDK audit') -or
        $audit.Output -notmatch [regex]::Escape($sdkVersion)) {
        throw "Audit output did not report installed SDK $sdkVersion."
    }
    if ($audit.Output -match 'Vulnerable') {
        throw 'Audit output used unsupported vulnerability attribution.'
    }

    Write-Host "E2E direct: removing .NET SDK $sdkVersion"'''
)
replace(
    "tests/e2e/bash/interactive.sh",
    "# Main -> Install -> channel -> Back -> same discovered channel -> manual exact\n# version -> Main -> List -> Main -> Verify the only job-local SDK -> Main ->\n# Remove the same SDK -> Main -> Exit.",
    "# Main -> Install -> channel -> Back -> same discovered channel -> manual exact\n# version -> Main -> List -> Main -> Verify the only job-local SDK -> Main ->\n# Audit installed SDKs -> Main -> Remove the same SDK -> Main -> Exit."
)
replace(
    "tests/e2e/bash/interactive.sh",
    "interactive_input=\"$(printf 'i\\n%s\\nB\\n%s\\nM\\n%s\\nl\\nv\\n1\\nr\\n1\\ne\\n' \\",
    "interactive_input=\"$(printf 'i\\n%s\\nB\\n%s\\nM\\n%s\\nl\\nv\\n1\\na\\nr\\n1\\ne\\n' \\",
)
replace(
    "tests/e2e/bash/interactive.sh",
    'if [[ "$main_prompt_count" -ne 5 ]]; then\n  printf \'Expected 5 Main prompts but observed %s.\\n\' "$main_prompt_count" >&2',
    'if [[ "$main_prompt_count" -ne 6 ]]; then\n  printf \'Expected 6 Main prompts but observed %s.\\n\' "$main_prompt_count" >&2'
)
replace(
    "tests/e2e/bash/interactive.sh",
    '  "Isolated SDK $sdk_version is healthy."\n  "$sdk_version"',
    '  "Isolated SDK $sdk_version is healthy."\n  ".NET SDK audit"\n  "$sdk_version"'
)
replace(
    "tests/e2e/powershell/interactive.ps1",
    "        'v',\n        '1',\n        'r',",
    "        'v',\n        '1',\n        'a',\n        'r',"
)
replace(
    "tests/e2e/powershell/interactive.ps1",
    '    if ($mainPromptCount -ne 5) {\n        throw "Expected 5 Main prompts but observed $mainPromptCount."',
    '    if ($mainPromptCount -ne 6) {\n        throw "Expected 6 Main prompts but observed $mainPromptCount."'
)
replace(
    "tests/e2e/powershell/interactive.ps1",
    '        "Isolated SDK $sdkVersion is healthy.",\n        $sdkVersion,',
    '        "Isolated SDK $sdkVersion is healthy.",\n        \'.NET SDK audit\',\n        $sdkVersion,'
)

# Dedicated Audit command documentation.
Path("docs/commands/audit.md").write_text(r'''# Audit

Audit is an explicit online, read-only assessment of installed .NET SDK lifecycle and servicing state. It uses current Microsoft release metadata and reports Isolated SDKs and read-only System SDKs as separate ownership groups.

For exact shell syntax, see [Windows / PowerShell](../getting-started/windows-powershell.md#audit-installed-sdks) or [Linux and macOS / Bash](../getting-started/linux-macos-bash.md#audit-installed-sdks).

## Why Audit is separate

The command boundaries are intentional:

- **List** is fast local inventory and does not fetch Microsoft lifecycle metadata.
- **Verify** is a local exact-version health check for one isolated SDK and does not fetch lifecycle metadata.
- **Audit** is the explicit online lifecycle/update/security-servicing assessment.
- **Install** is the online acquisition and mutation operation.

Audit never installs, upgrades, repairs, removes, or otherwise changes either Isolated or System SDKs.

## Status model

Audit evaluates servicing state and lifecycle state separately, then renders them together when both matter.

Servicing results include:

- `Current` — the installed SDK matches Microsoft's current `latest-sdk` for an active channel;
- `Update available -> <version>` — a newer SDK is known for the channel;
- `Security update available -> <version>` — a newer SDK belongs to a Microsoft release explicitly marked `security: true`;
- `Newer than known metadata` — the installed SDK sorts newer than Microsoft's current `latest-sdk`, so Audit does not incorrectly call it outdated; and
- `Unknown channel` — the installed version cannot be mapped to a channel in the current release index.

Lifecycle results include `Maintenance`, `Preview`, `Go Live`, `End of life`, and `Unsupported` when those states are present in the metadata contract. For example:

```text
.NET SDK audit

Isolated SDKs:
  10.0.401  Current
  9.0.306   Security update available -> 9.0.318  Maintenance
  8.0.303   Update available -> 8.0.425  Maintenance
  7.0.410   End of life

System SDKs:
  10.0.401  Current
  8.0.425   Maintenance
```

End-of-life state takes lifecycle precedence. Preview and prerelease movement is not promoted to a security conclusion merely because a later prerelease is associated with a security-marked release.

## Security terminology

`Security update available` is deliberately narrower than `Vulnerable`. Audit derives that result only when current Microsoft channel metadata contains a newer SDK in a release marked as a security release.

That does **not** prove that the exact installed SDK is affected by a particular advisory or CVE. Audit therefore does not label an installed SDK `Vulnerable` unless exact advisory attribution could be established separately.

## Metadata and failure behavior

Audit requires current Microsoft release metadata. If the release index or required metadata for a known installed channel cannot be obtained or is structurally unusable, Audit fails clearly instead of fabricating or silently downgrading results.

An installed SDK on a channel absent from the current index is reported as `Unknown channel`. An installed SDK newer than the current known `latest-sdk` is reported as `Newer than known metadata`.

## Ownership boundary

The same exact version may appear under both Isolated and System SDKs. Audit preserves both entries because they describe separate installations. System SDKs remain read-only: visibility in Audit does not make them owned by the tool.

See [List](list.md), [Verify](verify.md), [SDK discovery and release metadata](../concepts/sdk-discovery.md), and [PowerShell and Bash behavioral parity](../contracts/behavioral-parity.md).
''', encoding="utf-8")

# Documentation indexes/navigation.
replace("docs/commands/README.md", "- [Verify](verify.md) — perform a read-only health check of one isolated SDK\n", "- [Verify](verify.md) — perform a read-only health check of one isolated SDK\n- [Audit](audit.md) — assess installed SDK lifecycle and servicing state using current Microsoft metadata\n")
replace("docs/README.md", "- [Verify](commands/verify.md) — health-check one installed isolated SDK\n", "- [Verify](commands/verify.md) — health-check one installed isolated SDK\n- [Audit](commands/audit.md) — assess installed SDK lifecycle and servicing state online\n")
replace("_data/navigation.yml", "    - title: Verify\n      path: docs/commands/verify.md\n", "    - title: Verify\n      path: docs/commands/verify.md\n    - title: Audit\n      path: docs/commands/audit.md\n")

# Root README.
replace("README.md", "  L. List installed SDKs\n\n  E. Exit", "  L. List installed SDKs\n  V. Verify an isolated SDK\n  A. Audit installed SDKs\n\n  E. Exit")
replace("README.md", "Explicit Install, List, Verify, Remove, and exact-version invocations remain one-shot", "Explicit Install, List, Verify, Audit, Remove, and exact-version invocations remain one-shot")
replace("README.md", "- **Verify** one installed isolated SDK with a read-only exact-version health check.\n", "- **Verify** one installed isolated SDK with a local, read-only exact-version health check.\n- **Audit** Isolated and System SDKs against current Microsoft lifecycle and servicing metadata without modifying them.\n")

# List and Verify boundaries.
replace("docs/commands/list.md", "List is a read-only inventory view. It reports SDKs in two ownership domains and always shows Isolated SDKs first.", "List is a read-only, local inventory view. It reports SDKs in two ownership domains and always shows Isolated SDKs first. List does not fetch Microsoft release metadata; use [Audit](audit.md) when lifecycle and servicing state is needed.")
replace("docs/commands/verify.md", "Verify performs a read-only health check of one exact SDK already installed under the isolated SDK root.", "Verify performs a local, read-only health check of one exact SDK already installed under the isolated SDK root. It does not fetch Microsoft lifecycle metadata; use [Audit](audit.md) for online lifecycle and servicing assessment.")
replace("docs/commands/verify.md", "See [Interactive mode](interactive.md)", "See [Audit](audit.md) for lifecycle/update assessment, [Interactive mode](interactive.md)")

# Interactive model.
replace("docs/commands/interactive.md", "  V. Verify an isolated SDK\n\n  E. Exit", "  V. Verify an isolated SDK\n  A. Audit installed SDKs\n\n  E. Exit")
replace("docs/commands/interactive.md", "`I`, `R`, `L`, `V`, and `E` are the product commands", "`I`, `R`, `L`, `V`, `A`, and `E` are the product commands")
replace("docs/commands/interactive.md", "After a successful Install, List, Remove, or Verify operation", "After a successful Install, List, Remove, Verify, or Audit operation")
replace("docs/commands/interactive.md", "└─ Verify\n   └─ SDK selection\n      └─ Back → Main", "├─ Verify\n│  └─ SDK selection\n│     └─ Back → Main\n└─ Audit\n   └─ online assessment → Main")
replace("docs/commands/interactive.md", "Explicit Verify remains a one-shot exact-version command. Interactive Verify is available separately from Main and selects from the installed isolated SDK inventory.", "Explicit Verify remains a one-shot exact-version command. Interactive Verify is available separately from Main and selects from the installed isolated SDK inventory. Explicit Audit is one-shot and requires no SDK version; interactive Audit runs the same online read-only assessment and returns to Main after success.")
replace("docs/commands/interactive.md", "## Input failure versus cancellation", "## Audit\n\nInteractive Audit uses `A` from Main. It assesses both Isolated and System SDK inventories against current Microsoft release metadata, does not prompt for a target SDK, and never mutates either inventory. A successful assessment returns to Main. Metadata acquisition or validation failure is an operational failure and terminates the session nonzero rather than returning to Main with fabricated results.\n\n## Input failure versus cancellation")
replace("docs/commands/interactive.md", "- [Verify](verify.md)\n", "- [Verify](verify.md)\n- [Audit](audit.md)\n")

# Getting-started guides.
for path in ("docs/getting-started/windows-powershell.md", "docs/getting-started/linux-macos-bash.md"):
    replace(path, "network access when bootstrap or SDK installation downloads remote artifacts", "network access when bootstrap, SDK installation, or Audit retrieves remote metadata/artifacts")
replace("docs/getting-started/windows-powershell.md", "uses `I` for Install, `R` for Remove, `L` for List, `V` for Verify, and `E` for Exit", "uses `I` for Install, `R` for Remove, `L` for List, `V` for Verify, `A` for Audit, and `E` for Exit")
replace("docs/getting-started/linux-macos-bash.md", "uses `I` for Install, `R` for Remove, `L` for List, `V` for Verify, and `E` for Exit", "uses `I` for Install, `R` for Remove, `L` for List, `V` for Verify, `A` for Audit, and `E` for Exit")
replace("docs/getting-started/windows-powershell.md", "## Use an isolated SDK", "## Audit installed SDKs\n\n```powershell\n& \"$HOME\\dotnet-sdks\\isolated-dotnet-sdk.ps1\" -Action Audit\n```\n\nAudit is read-only and online. It evaluates both Isolated and System SDKs against current Microsoft lifecycle and servicing metadata. List and Verify remain local operations. See [Audit](../commands/audit.md).\n\n## Use an isolated SDK")
replace("docs/getting-started/linux-macos-bash.md", "## Use an isolated SDK", "## Audit installed SDKs\n\n```bash\n\"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh\" audit\n```\n\nAudit is read-only and online. It evaluates both Isolated and System SDKs against current Microsoft lifecycle and servicing metadata. List and Verify remain local operations. See [Audit](../commands/audit.md).\n\n## Use an isolated SDK")

# Cross-shell parity.
replace("docs/contracts/behavioral-parity.md", "Use case-insensitive `I` / `R` / `L` / `V` / `E` for Install / Remove / List / Verify / Exit.", "Use case-insensitive `I` / `R` / `L` / `V` / `A` / `E` for Install / Remove / List / Verify / Audit / Exit.")
replace("docs/contracts/behavioral-parity.md", "| Explicit Verify with an exact version |", "| Audit | Explicitly fetch current Microsoft release metadata and assess installed Isolated and System SDKs without modifying them. Preserve ownership groups and fail clearly when required metadata for a known channel is unavailable or unusable. |\n| Audit servicing/lifecycle status | Keep servicing and lifecycle concepts distinct. Prefer `Security update available` only when a newer Microsoft release is marked as security-related; never infer `Vulnerable` without exact advisory attribution. Preserve Maintenance, Preview, Go Live, End of life, Unsupported, Unknown channel, and newer-than-known-metadata semantics. |\n| Explicit Audit plus Version | Reject the version instead of treating Audit as a single-SDK operation. |\n| Explicit Verify with an exact version |")
replace("docs/contracts/behavioral-parity.md", "Main provides mnemonic `I. Install`, `R. Remove`, `L. List`, `V. Verify`, and `E. Exit` commands;", "Main provides mnemonic `I. Install`, `R. Remove`, `L. List`, `V. Verify`, `A. Audit`, and `E. Exit` commands;")
replace("docs/contracts/behavioral-parity.md", "- Verify SDK selection provides Back to Main and contains isolated SDKs only;", "- Verify SDK selection provides Back to Main and contains isolated SDKs only;\n- Audit has no target picker; successful online assessment returns directly to Main;")

# Metadata architecture.
replace("docs/concepts/sdk-discovery.md", "This contract covers interactive version discovery only.", "Audit also consumes the release index and required channel metadata, but for a different purpose: online lifecycle and servicing assessment of installed SDKs. List and Verify do not use this networked metadata path. This contract covers interactive version discovery and Audit metadata acquisition; it does not define retry/backoff beyond their explicit failure behavior.")
replace("docs/concepts/sdk-discovery.md", "Display-only metadata such as `latest-sdk` and `release-type` may be absent without invalidating an otherwise selectable channel.", "For interactive Install selection, display-only metadata such as `latest-sdk` and `release-type` may be absent without invalidating an otherwise selectable channel. Audit is stricter for a known installed channel: `latest-sdk`, `support-phase`, and `releases.json` are required to produce a current assessment.")
replace("docs/concepts/sdk-discovery.md", "## Explicit-version installs", "## Audit metadata\n\nAudit maps an installed SDK version to its major/minor channel, fetches that channel metadata at most once per operation, and compares the installed SDK with the channel's current `latest-sdk`. Release-level `security: true` metadata may justify `Security update available` when a newer SDK is associated with that security release. Audit does not convert the release's CVE list into exact installed-SDK vulnerability attribution.\n\nUnknown installed channels are reported explicitly rather than guessed. Installed SDKs newer than current metadata are reported as newer than known metadata rather than outdated. A transport or structural failure for metadata required by a known installed channel fails the Audit rather than emitting partial fabricated status.\n\n## Explicit-version installs")

# Maintainer vocabulary/testing.
replace("docs/maintainers/development/coding-consistency.md", "The stable product actions are install, remove, list, and verify.", "The stable product actions are install, remove, list, verify, and audit.")
replace("docs/maintainers/development/coding-consistency.md", "`-Action Install`, `-Action Remove`, `-Action List`, and `-Action Verify`", "`-Action Install`, `-Action Remove`, `-Action List`, `-Action Verify`, and `-Action Audit`")
replace("docs/maintainers/development/coding-consistency.md", "`install`, `remove`, `list`, and `verify` subcommands", "`install`, `remove`, `list`, `verify`, and `audit` subcommands")
replace("docs/maintainers/testing/testing.md", "- `list` behavior and non-SDK artifact filtering, including rejection of an explicit list-version argument;", "- `list` behavior and non-SDK artifact filtering, including rejection of an explicit list-version argument;\n- `audit` lifecycle/servicing semantics, Isolated/System ownership preservation, metadata failures, direct/interactive behavior, and proof that List/Verify remain network-independent;")
replace("docs/maintainers/testing/testing.md", "- the `List` action and non-SDK artifact filtering, including rejection of explicit List plus Version;", "- the `List` action and non-SDK artifact filtering, including rejection of explicit List plus Version;\n- the `Audit` action's lifecycle/servicing semantics, Isolated/System ownership preservation, metadata failures, direct/interactive behavior, and List/Verify network-boundary regression coverage;")
replace("docs/maintainers/testing/testing.md", "required merge-candidate E2E remains tracked separately in Issue #60.", "exact-head E2E is run explicitly when the issue workflow calls for live pre-merge evidence; automatic post-merge E2E on `main` remains the landed-state signal.")
replace("docs/maintainers/testing/interactive-testing.md", "Main commands `I`, `R`, `L`, `V`, and `E`", "Main commands `I`, `R`, `L`, `V`, `A`, and `E`")
replace("docs/maintainers/testing/interactive-testing.md", "- Verify Back and Exit navigation, empty-inventory no-change behavior, healthy return to Main, retry feedback, and failure propagation;", "- Verify Back and Exit navigation, empty-inventory no-change behavior, healthy return to Main, retry feedback, and failure propagation;\n- Audit as a first-class read-only Main action, successful return to Main, metadata-failure propagation, and both ownership groups;")
replace("docs/maintainers/testing/interactive-testing.md", "installs a real isolated SDK, lists it, verifies it through Main, removes it, and exits", "installs a real isolated SDK, lists it, verifies it through Main, audits installed SDKs through Main, removes it, and exits")
replace("docs/maintainers/testing/interactive-testing.md", "semantic commands are explicitly `I`, `R`, `L`, `V`, and `E`", "semantic commands are explicitly `I`, `R`, `L`, `V`, `A`, and `E`")

# E2E documentation and current delivery model.
replace("docs/maintainers/testing/e2e-testing.md", "5. run List and require the configured isolated version to appear in the installed-SDK output;\n6. remove the configured SDK;\n7. require", "5. run List and require the configured isolated version to appear in the installed-SDK output;\n6. run Audit against live Microsoft metadata and require the configured installed version to appear without asserting a transient servicing label;\n7. remove the configured SDK;\n8. require")
replace("docs/maintainers/testing/e2e-testing.md", "8. runs Verify with `V`, selects the only job-local isolated SDK, requires a healthy result, and verifies return to Main;\n9. runs Remove", "8. runs Verify with `V`, selects the only job-local isolated SDK, requires a healthy result, and verifies return to Main;\n9. runs Audit with `A`, requires the live online assessment to complete, and verifies return to Main;\n10. runs Remove")
replace("docs/maintainers/testing/e2e-testing.md", "10. exits explicitly with `E`", "11. exits explicitly with `E`")
replace("docs/maintainers/testing/e2e-testing.md", "11. verifies the SDK is absent afterward.", "12. verifies the SDK is absent afterward.")
replace("docs/maintainers/testing/e2e-testing.md", "E2E is intentionally not triggered on pull requests and is not a required merge check yet. Future organization-backed merge-queue work may promote E2E into required merge-candidate gating. Until that protection exists and is demonstrated, deterministic `push: main` Validate remains enabled as the normal post-merge deterministic signal.", "E2E is intentionally not triggered automatically on pull requests. When the issue workflow requires exact-head live evidence, maintainers dispatch E2E explicitly for the reviewed branch head before the readiness/merge decision. Automatic `push: main` E2E and Validate remain enabled to verify the exact landed commit after merge. The repository does not rely on merge-queue enforcement for this delivery model.")
