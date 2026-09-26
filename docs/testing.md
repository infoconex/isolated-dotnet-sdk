# Testing

The repository uses established test frameworks for behavioral coverage:

- **Pester** for PowerShell tests;
- **Bats-core** for Bash tests.

Exact framework versions are repository-owned in [`.config/test-frameworks.json`](../.config/test-frameworks.json). Local and CI runs must use those exact versions so diagnostics and behavior stay reproducible.

## Test taxonomy

Use the smallest level that verifies the observable contract without forcing production code into a test-specific architecture.

### Process-level behavioral tests

Process-level tests invoke the public script entry point in a child process with isolated temporary user/home state. Use them for bootstrap behavior, CLI/action parsing, output/stream contracts, environment handling, and behavior whose public contract depends on a real process boundary.

### Focused function/component tests

Focused tests load only the production functions needed for the behavior under test and replace external or destructive seams when appropriate. Use them when a process-level test would require a real SDK installation, network dependency, destructive filesystem operation, or interactive host behavior.

PowerShell focused tests use Pester setup/teardown and mocks or controlled function seams where justified. Bash tests remain process-oriented until a focused seam provides a concrete advantage; do not grow a custom shell test framework alongside Bats.

## Framework versions

From the repository root, inspect the configured versions with:

```bash
jq . .config/test-frameworks.json
```

The current pins are Pester `6.2.0` and Bats-core `1.14.0`. Update the configuration, local instructions, and CI installation together when either framework is intentionally upgraded.

## Bash behavioral tests

Bats-core and `jq` are required. Install the exact configured Bats version, for example with npm:

```bash
bats_version="$(jq -er '.batsVersion' .config/test-frameworks.json)"
npm install --global "bats@${bats_version}"
```

Then run from the repository root:

```bash
bash tests/bash/run-tests.sh
```

The Bash suite covers:

- isolated temporary `HOME` handling;
- file-based bootstrap source preservation;
- the `list` command;
- rejection of an invalid SDK version.

## PowerShell behavioral tests

PowerShell 7.4 or newer is required by the pinned Pester major version. Install the exact configured Pester version for the current user:

```powershell
$config = Get-Content -LiteralPath './.config/test-frameworks.json' -Raw | ConvertFrom-Json
Install-Module Pester `
    -RequiredVersion $config.pesterVersion `
    -Scope CurrentUser `
    -Repository PSGallery `
    -Force `
    -SkipPublisherCheck
```

Then run from the repository root:

```powershell
pwsh -NoProfile -File ./tests/powershell/run-tests.ps1
```

The PowerShell behavioral coverage includes:

- isolated temporary home/profile handling;
- file-based bootstrap source preservation;
- the `List` action;
- information-stream versus success-stream separation;
- ANSI informational and success presentation colors;
- ANSI-free redirected output and `NO_COLOR` behavior;
- rejection of an invalid SDK version;
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

The authoritative removal behavior specification is [`powershell-removal.md`](powershell-removal.md).

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

The behavioral suites create temporary user/home state and clean it up when the run completes. They do not intentionally read from or modify the developer's real `~/dotnet-sdks` installation.

The current behavioral checks do not install an SDK or require release-metadata downloads.

## CI

`.github/workflows/validate.yml` installs the exact framework versions from `.config/test-frameworks.json` and runs:

- Bash syntax validation and the Bats behavioral suite on Ubuntu and macOS;
- ShellCheck once on Ubuntu;
- PowerShell parser validation and the Pester suite on Windows;
- PSScriptAnalyzer once on Windows.

Syntax/parser checks, static analysis, and behavioral tests remain separate validation layers. Framework failure output is emitted directly by Bats/Pester so CI retains test names, assertion context, and framework diagnostics.
