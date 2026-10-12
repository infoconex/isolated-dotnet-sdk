# Interactive lifecycle testing

The repository keeps deterministic interactive-session coverage separate from real Microsoft/.NET end-to-end validation. The deterministic suites lock menu lifecycle, navigation, retry feedback, and operation transitions without depending on live release metadata or destructive system state.

## What the deterministic suites cover

Both product implementations have behavioral coverage for:

- no-action invocation remaining in the interactive session until Exit;
- case-insensitive Main commands `I`, `R`, `L`, `V`, and `E`, with the old numeric Main aliases rejected;
- terminal-backed normal operation/no-change outcomes remaining visible until contextual Enter acknowledgement before returning to the immediate parent screen;
- capability-aware screen clearing at persistent navigation and picker-view boundaries, including Back and only *after* completed-result acknowledgement;
- successful Install, Verify, and Remove picker selections clearing once before operation details or confirmation, retaining output until acknowledgement and clearing again before the parent picker;
- unsupported terminals retaining scrolling, and captured/redirected/one-shot execution staying free of clearing controls;
- invalid-selection feedback and active operation progress not being erased by a generic menu redraw;
- redirected/captured persistent execution skipping acknowledgement so pipes, CI, and automation never wait;
- completed Install, List, Audit, Verify, and Remove transitions sharing the same terminal acknowledgement boundary while returning to the correct parent screen;
- Back and Exit navigation returning/leaving immediately without completed-result acknowledgement;
- explicit List and other one-shot execution remaining acknowledgement-free;
- operational failures terminating nonzero instead of returning to Main or waiting for acknowledgement;
- Install channel Back to Main;
- Install SDK Back to channel selection;
- Remove SDK Back to Main;
- Verify selecting only installed isolated SDKs, never System SDKs;
- Verify Back and Exit navigation, terminal acknowledgement capability, captured empty-inventory/healthy no-wait behavior, retry feedback, and failure propagation;
- compact SDK presentation using latest/recommended metadata and newest-per-feature-band choices;
- `Show all versions` exposing older servicing releases in deterministic order;
- recoverable blank/invalid selection feedback and global Exit behavior across persistent menus.

The Bash suite also exercises a representative multi-operation session through Install, List, Remove, and Exit using deterministic fake metadata and an isolated fake SDK host. Parent-navigation coverage verifies that Verify and Remove return to their SDK lists and that Install returns to the selected channel's SDK list. A Bash pseudo-terminal test proves the visible Enter acknowledgement in a real terminal-capable session, while PowerShell exercises the acknowledgement helper with explicit terminal-capability inputs and contextual destinations. Focused captured-process tests prove that redirected input/output never waits while still following parent navigation. The real interactive E2E flow is intentionally captured automation, so it asserts zero acknowledgement prompts while still exercising Install, List, Audit, Verify, Remove, and Exit. Existing focused suites continue to own transactional installation, confirmation, metadata failure, filesystem, native-command, cleanup, direct Verify, and presentation boundaries.

## Relationship to real E2E

These suites are repository-controlled integration/behavioral tests. They replace external network and destructive boundaries where necessary so failures are deterministic and fast to diagnose.

Real Microsoft/.NET lifecycle coverage exists separately in [`e2e-testing.md`](e2e-testing.md). The live interactive E2E path installs a real isolated SDK, lists it, verifies it through Main, removes it, and exits. The live E2E suite complements this deterministic layer; it does not replace the focused failure and navigation coverage here.

## Test design

Interactive tests resolve behavior from displayed labels and current data rather than assuming that a fixed numeric SDK-menu position always represents a particular version. Deterministic metadata fixtures intentionally contain SDK versions in non-sorted order so presentation ordering is established by the product rather than fixture order.

The persistent Main menu is different: its semantic commands are explicitly `I`, `R`, `L`, `V`, and `E`, so those mnemonics are part of the product contract rather than data-derived positions.

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
