# Interactive lifecycle testing

The repository keeps deterministic interactive-session coverage separate from real Microsoft/.NET end-to-end validation. The deterministic suites lock menu lifecycle, navigation, retry feedback, and operation transitions without depending on live release metadata or destructive system state.

## What the deterministic suites cover

Both product implementations have behavioral coverage for:

- no-action invocation remaining in the interactive session until Exit;
- case-insensitive Main commands `I`, `R`, `L`, and `E`, with the old numeric Main aliases rejected;
- normal operation/no-change outcomes returning to Main;
- explicit List remaining one-shot;
- operational failures terminating nonzero instead of returning to Main;
- Install channel Back to Main;
- Install SDK Back to channel selection;
- Remove SDK Back to Main;
- compact SDK presentation using latest/recommended metadata and newest-per-feature-band choices;
- `Show all versions` exposing older servicing releases in deterministic order;
- recoverable blank/invalid selection feedback and global Exit behavior across persistent menus.

The Bash suite also exercises a representative multi-operation session through Install, List, Remove, and Exit using deterministic fake metadata and an isolated fake SDK host. Existing focused suites continue to own transactional installation, confirmation, metadata failure, filesystem, native-command, cleanup, and presentation boundaries.

## Relationship to real E2E

These suites are repository-controlled integration/behavioral tests. They replace external network and destructive boundaries where necessary so failures are deterministic and fast to diagnose.

Real Microsoft/.NET lifecycle coverage exists separately in [`e2e-testing.md`](e2e-testing.md). The live E2E suite complements this deterministic layer; it does not replace the focused failure and navigation coverage here.

## Test design

Interactive tests resolve behavior from displayed labels and current data rather than assuming that a fixed numeric SDK-menu position always represents a particular version. Deterministic metadata fixtures intentionally contain SDK versions in non-sorted order so presentation ordering is established by the product rather than fixture order.

The persistent Main menu is different: its semantic commands are explicitly `I`, `R`, `L`, and `E`, so those mnemonics are part of the product contract rather than data-derived positions.

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

The GitHub Validate workflow remains the cross-platform deterministic evidence source for Ubuntu/Bash, macOS/Bash, and Windows/PowerShell.
