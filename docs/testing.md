# Testing

The repository uses established test frameworks for behavioral coverage:

- **Pester** for PowerShell tests;
- **Bats-core** for Bash tests.

Exact framework versions are repository-owned in [`.config/test-frameworks.json`](../.config/test-frameworks.json). Bats is additionally pinned to the upstream commit behind the selected release tag. Local and CI runs must use those exact pins so diagnostics and behavior stay reproducible.

## Test taxonomy

Use the smallest level that verifies the observable contract without forcing production code into a test-specific architecture.

### Process-level behavioral tests

Process-level tests invoke the public script entry point in a child process with isolated temporary user/home state. Use them for bootstrap behavior, CLI/action parsing, output/stream contracts, environment handling, interactive-input availability, and behavior whose public contract depends on a real process boundary.

### Focused function/component tests

Focused tests load only the production functions needed for the behavior under test and replace external or destructive seams when appropriate. Use them when a process-level test would require a real SDK installation, network dependency, destructive filesystem operation, or interactive host behavior.

PowerShell focused tests use Pester setup/teardown and mocks or controlled function seams where justified. Bash tests remain process-oriented until a focused seam provides a concrete advantage; do not grow a custom shell test framework alongside Bats.

## Framework versions

From the repository root, inspect the configured pins with:

```bash
jq . .config/test-frameworks.json
```

The current pins are Pester `6.2.0` and Bats-core `1.14.0`, with Bats fixed to commit `eb7f42f8d608ac693d7a4b67474f6714ea68cfc5`. Update the configuration, local instructions, and CI installation together when either framework is intentionally upgraded.

## Bash behavioral tests

Bats-core, Git, and `jq` are required. Install the exact configured Bats source commit into a user-owned prefix:

```bash
bats_version="$(jq -er '.batsVersion' .config/test-frameworks.json)"
bats_commit="$(jq -er '.batsCommit' .config/test-frameworks.json)"
prefix="$HOME/.local"
workdir="$(mktemp -d)"
git -C "$workdir" init
git -C "$workdir" remote add origin https://github.com/bats-core/bats-core.git
git -C "$workdir" fetch --depth=1 origin "$bats_commit"
git -C "$workdir" checkout --detach FETCH_HEAD
"$workdir/install.sh" "$prefix"
rm -rf "$workdir"
"$prefix/bin/bats" --version | grep -Fx "Bats $bats_version"
```

Ensure the selected prefix's `bin` directory is on `PATH`, then run from the repository root:

```bash
bash tests/bash/run-tests.sh
```

The Bash suites cover, among other focused reliability cases:

- isolated temporary `HOME` handling;
- file-based bootstrap source preservation, child-status propagation, and bootstrap filesystem/final-replacement failures;
- `list` behavior and non-SDK artifact filtering, including rejection of an explicit list-version argument;
- bare-version install resolution, removal picker cancellation/no-installed behavior, and unavailable required picker input;
- rejection of an invalid SDK version;
- release-metadata transport/shape failures, required selection fields, no-SDK channel data, first-seen duplicate ordering, and exact-version metadata independence;
- system and isolated-host native-command failures;
- unavailable interactive input versus explicit default-no cancellation;
- build-server shutdown failure context and deletion blocking;
- transactional installation staging, verification, promotion, conflict preservation, cleanup, retry behavior, promotion-command failure, and post-promotion cleanup failure.

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
- file-based bootstrap source preservation and bootstrap filesystem failures;
- the `List` action and non-SDK artifact filtering, including rejection of explicit List plus Version;
- Version-without-Action install resolution, removal picker cancellation/no-installed behavior, and unavailable required picker input;
- information-stream versus success-stream separation;
- ANSI informational and success presentation colors;
- ANSI-free redirected output and `NO_COLOR` behavior;
- rejection of an invalid SDK version;
- release-metadata transport/shape behavior, required selection fields, no-SDK channel data, duplicate normalization, and exact-version metadata independence;
- repository-owned unavailable-interactive-input context;
- repository-owned install-helper download context;
- source bootstrap forwarding for `-WhatIf`;
- rejection of removal-only risk-mitigation parameters on unsupported actions;
- fail-safe non-interactive removal without explicit approval;
- native `WhatIf` / `Confirm` parameter exposure;
- ordinary default-no cancellation and approval behavior;
- `-Confirm:$false` automation;
- `-Yes` automation and `-WhatIf` precedence;
- shutdown-before-delete ordering;
- shutdown failure blocking deletion;
- deletion failure blocking success reporting;
- transactional installation staging, verification, promotion, conflict preservation, cleanup, retry behavior, promotion-command failure, and post-promotion cleanup failure.

The cross-shell product contract is documented in [`behavioral-parity.md`](behavioral-parity.md). The authoritative PowerShell-specific removal behavior specification is [`powershell-removal.md`](powershell-removal.md).

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

## Local validation layers

CI keeps syntax/parser checks separate from analyzers, formatting, and behavioral tests. The same layers can be run locally without a separate validation harness.

For Bash, validate syntax before static analysis and behavioral tests:

```bash
bash -n isolated-dotnet-sdk.sh
bash scripts/run-shellcheck.sh
bash tests/bash/run-tests.sh
```

For PowerShell, validate parser errors and then run the repository-owned analyzer, formatting check, and behavioral suite:

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

Install the pinned framework/analyzer versions described above before running these commands. The formatting check uses the pinned PSScriptAnalyzer version and the repository-owned formatter settings; it does not silently format files in check mode.

## Isolation

The behavioral suites create temporary user/home state and clean it up when the run completes. They do not intentionally read from or modify the developer's real `~/dotnet-sdks` installation.

The deterministic behavioral checks do not install a real SDK or require live release-metadata downloads. External downloads and native commands are replaced with deterministic test seams where necessary to exercise failure and transaction boundaries.

## Real end-to-end validation

Real Microsoft/.NET ecosystem coverage is intentionally separate from the deterministic behavioral suites. The repository-owned fixed SDK target, direct and persistent-interactive scenarios, isolated job-state rules, automatic post-merge trigger, and manual rerun procedure are documented in [`e2e-testing.md`](e2e-testing.md).

`.github/workflows/e2e.yml` runs automatically on `push` to `main` and also supports `workflow_dispatch` for ad hoc reruns. It runs the supported Windows/PowerShell, Ubuntu/Bash, and macOS/Bash product mappings against live Microsoft metadata, installer acquisition, and SDK payloads. It is a post-merge confidence signal, not a required PR or merge check; required merge-candidate E2E remains tracked separately in Issue #60.

## CI

`.github/workflows/validate.yml` uses explicit versioned GitHub-hosted runner labels and repository-owned dependency pins rather than relying on preinstalled tool versions. It runs:

- Bash syntax validation and the Bats behavioral suite on `ubuntu-24.04` and `macos-26`;
- ShellCheck once on `ubuntu-24.04`;
- PowerShell parser validation, PSScriptAnalyzer, formatting checks, and the Pester behavioral suite on `windows-2025`.

Validate uses exact-key caches for pinned Bats-core, ShellCheck, Pester, and PSScriptAnalyzer where practical. Cache identity derives from the repository-owned pin/configuration files plus relevant runner/runtime identity. A cache miss acquires the exact configured dependency; a cache hit still revalidates the configured commit, checksum, or module version before use. No broad restore-key fallback accepts an older toolset, and product/E2E SDK or HOME/profile state is not cached.

The dependency-update monitor uses `ubuntu-24.04` and remains separate from product validation. Workflows pin external Actions to full commit SHAs and disable persisted checkout credentials when the checkout is only used for read access.

Versioned hosted-runner labels intentionally pin the OS/architecture family, not an immutable VM image build. GitHub can patch and rebuild a selected hosted image over time; the exact resolved image and build revision are visible in each job log. Repository-owned test frameworks, analyzers, checksums, and action references remain independently pinned so those dependencies do not silently follow runner-image contents.

CI invokes the same repository-owned behavioral/analyzer/formatting commands documented above instead of maintaining parallel CI-only runners. Syntax/parser checks remain inline because they are small shell/runtime primitives rather than a second test harness. Framework failure output is emitted directly by Bats/Pester so CI retains test names, assertion context, and framework diagnostics.

Syntax/parser checks, static analysis/formatting, and behavioral tests remain separate validation layers because they identify different failure classes. Static analyzers intentionally run once per relevant shell; cross-platform duplication is not added without evidence that it catches a platform-specific analyzer contract.
