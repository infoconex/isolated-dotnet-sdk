# Testing

The repository keeps its behavioral assertions in repository-owned test scripts so the same checks can run locally and in GitHub Actions.

## Bash behavioral tests

From the repository root, run:

```bash
bash tests/bash/run-tests.sh
```

The Bash suite covers:

- isolated temporary `HOME` handling;
- file-based bootstrap source preservation;
- the `list` command;
- rejection of an invalid SDK version.

## PowerShell behavioral tests

PowerShell 7 (`pwsh`) is required. From the repository root, run:

```powershell
pwsh -NoProfile -File ./tests/powershell/run-tests.ps1
```

The general PowerShell suite covers:

- isolated temporary home/profile handling;
- file-based bootstrap source preservation;
- the `List` action;
- information-stream versus success-stream separation;
- ANSI informational and success presentation colors;
- ANSI-free redirected output and `NO_COLOR` behavior;
- rejection of an invalid SDK version.

Removal behavior has a dedicated suite:

```powershell
pwsh -NoProfile -File ./tests/powershell/run-removal-tests.ps1
```

The removal suite covers:

- source bootstrap forwarding for `-WhatIf`;
- rejection of removal-only risk-mitigation parameters on unsupported actions;
- fail-safe non-interactive removal without explicit approval;
- native `WhatIf` / `Confirm` parameter exposure;
- ordinary default-no cancellation and approval behavior;
- `-Confirm:$false` automation;
- `-Yes` automation and `-WhatIf` precedence;
- shutdown-before-delete ordering;
- shutdown failure blocking deletion;
- deletion failure blocking success reporting.

The authoritative behavior specification is [`powershell-removal.md`](powershell-removal.md).

## Static analysis

Static-analysis scope and version policy are documented in [`static-analysis.md`](static-analysis.md). The authoritative analyzer versions are defined in [`.config/static-analysis.json`](../.config/static-analysis.json).

### PowerShell

PowerShell 7 and the pinned PSScriptAnalyzer version are required. Install the configured version for the current user:

```powershell
$config = Get-Content -LiteralPath './.config/static-analysis.json' -Raw | ConvertFrom-Json
Install-Module PSScriptAnalyzer `
    -RequiredVersion $config.psScriptAnalyzerVersion `
    -Scope CurrentUser `
    -Repository PSGallery
```

Then run the repository-owned analyzer command from the repository root:

```powershell
pwsh -NoProfile -File ./scripts/Invoke-PSScriptAnalyzer.ps1
```

### Bash

ShellCheck, `jq`, and the pinned ShellCheck version are required. Read the required version with:

```bash
jq -r '.shellCheckVersion' .config/static-analysis.json
```

Install that exact ShellCheck release using the upstream package appropriate for the local operating system, then run the repository-owned analyzer command from the repository root:

```bash
bash scripts/run-shellcheck.sh
```

The runner rejects missing or mismatched ShellCheck versions and ignores caller/user ShellCheck configuration so local analysis stays aligned with CI.

## Isolation

Both PowerShell suites and the Bash suite create temporary user/home state and clean it up when the run completes. They do not intentionally read from or modify the developer's real `~/dotnet-sdks` installation.

The current behavioral checks do not install an SDK or require release-metadata downloads.

## CI

`.github/workflows/validate.yml` runs:

- Bash syntax validation and the Bash behavioral suite on Ubuntu and macOS;
- ShellCheck once on Ubuntu;
- PowerShell parser validation, the general PowerShell behavioral suite, and the dedicated removal behavioral suite on Windows;
- PSScriptAnalyzer once on Windows.

CI reads analyzer versions and the ShellCheck release checksum from `.config/static-analysis.json` before installation.

Syntax/parser checks, static analysis, and behavioral tests remain separate validation layers.
