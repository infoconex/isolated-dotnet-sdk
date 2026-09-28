# Interactive lifecycle testing

Issue #57 adds deterministic behavioral coverage for the persistent interactive-session and menu-navigation contract without introducing live Microsoft/.NET end-to-end testing.

## What the deterministic suites cover

Both product implementations have behavioral coverage for:

- no-action invocation remaining in the interactive session until Exit;
- normal operation/no-change outcomes returning to Main;
- explicit List remaining one-shot;
- operational failures terminating nonzero instead of returning to Main;
- Install channel Back to Main;
- Install SDK Back to channel selection;
- Remove SDK Back to Main;
- compact SDK presentation using latest/recommended metadata and newest-per-feature-band choices;
- `Show all versions` exposing older servicing releases in deterministic order.

The Bash suite also exercises a representative multi-operation session through Install, List, Remove, and Exit using deterministic fake metadata and an isolated fake SDK host. Existing focused suites continue to own transactional installation, confirmation, metadata failure, filesystem, native-command, and cleanup boundaries.

## Test design

Interactive tests resolve behavior from displayed labels and data rather than assuming that a fixed numeric menu position always represents a particular SDK version. Deterministic metadata fixtures intentionally contain SDK versions in non-sorted order so presentation ordering is established by the product rather than fixture order.

These tests remain repository-controlled integration/behavioral tests. They replace external network/destructive boundaries where necessary and do not prove the real Microsoft ecosystem end to end. Live end-to-end coverage is intentionally deferred to Issue #58.

## Running validation

Use the standard repository-owned commands documented in [`testing.md`](testing.md). In particular:

```bash
bash -n isolated-dotnet-sdk.sh
bash scripts/run-shellcheck.sh
bash tests/bash/run-tests.sh
```

and on the supported Windows/PowerShell mapping:

```powershell
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path './isolated-dotnet-sdk.ps1'),
    [ref]$tokens,
    [ref]$errors) | Out-Null
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_.Message }
    throw 'PowerShell syntax validation failed.'
}

pwsh -NoProfile -File ./scripts/Invoke-PSScriptAnalyzer.ps1
pwsh -NoProfile -File ./scripts/Invoke-PSFormatter.ps1 -Check
pwsh -NoProfile -File ./tests/powershell/run-tests.ps1
```

The GitHub Validate workflow remains the cross-platform evidence source for Ubuntu/Bash, macOS/Bash, and Windows/PowerShell.
