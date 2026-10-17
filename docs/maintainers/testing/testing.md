# Testing

The repository uses established test frameworks for behavioral coverage:

- **Pester** for PowerShell tests;
- **Bats-core** for Bash tests;
- **Node.js built-in `node:test`** for hermetic stable-release publisher regression tests (no npm framework dependency).

Exact framework versions are repository-owned in [`.config/test-frameworks.json`](../../../.config/test-frameworks.json). Bats is additionally pinned to the upstream commit behind the selected release tag. Local and CI runs must use those exact pins so diagnostics and behavior stay reproducible.

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
- prefix-free CLI presentation, explicit semantic heading roles, ANSI-free captured output, and preserved failure routing;
- bare-version install resolution, removal picker cancellation/no-installed behavior, and unavailable required picker input;
- rejection of an invalid SDK version;
- release-metadata transport/shape failures, required selection fields, no-SDK channel data, first-seen duplicate ordering, and exact-version metadata independence;
- Audit release type, exact SDK release dates, lifecycle states, internal security-servicing precedence, compact update-tail presentation, exact Preview/RC labels, optional Go-Live schedule fallback, end-of-support dates, newest-first ownership ordering, status styling, redirected ANSI-free output, unsupported/EOL channels, ownership overlap, metadata failures, interactive navigation, and List network independence and Verify's metadata-unavailability/local-proof separation;
- system and isolated-host native-command failures;
- unavailable interactive input versus explicit default-no cancellation;
- build-server shutdown failure context and deletion blocking;
- legacy shutdown invocation from neutral temporary working state with pinned isolated `DOTNET_ROOT`, no Windows multi-level lookup, first-run suppression, and cleanup before deletion;
- exact-version legacy `-AllowUnsupportedShutdown` / `--allow-unsupported-shutdown` opt-in boundaries, strict two-spelling missing-command classification, and successful SDK-local Roslyn shutdown for 2.1.105;
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
- prefix-free presentation with explicit cyan heading and green success roles while ordinary values remain neutral;
- ANSI-free redirected output and `NO_COLOR` behavior;
- warning/error stream preservation and prefix-free failure presentation;
- rejection of an invalid SDK version;
- release-metadata transport/shape behavior, required selection fields, no-SDK channel data, duplicate normalization, and exact-version metadata independence;
- Audit lifecycle/update presentation, security precedence, preview and Go Live behavior, newest-first ownership ordering, unsupported/EOL channels, ownership overlap, metadata failures, interactive navigation, and List network independence and Verify's metadata-unavailability/local-proof separation;
- repository-owned unavailable-interactive-input context;
- repository-owned SDK payload download context;
- source bootstrap forwarding for `-WhatIf`;
- rejection of removal-only risk-mitigation parameters on unsupported actions;
- fail-safe non-interactive removal without explicit approval;
- native `WhatIf` / `Confirm` parameter exposure;
- ordinary default-no cancellation and approval behavior;
- `-Confirm:$false` automation;
- `-Yes` automation and `-WhatIf` precedence;
- shutdown-before-delete ordering;
- shutdown environment isolation, restoration of caller state, and operation-owned temporary-state cleanup;
- shutdown failure blocking deletion;
- deletion failure blocking success reporting;
- transactional installation staging, verification, promotion, conflict preservation, cleanup, retry behavior, promotion-command failure, and post-promotion cleanup failure.

The cross-shell product contract is documented in [PowerShell and Bash behavioral parity](../../contracts/behavioral-parity.md). The authoritative PowerShell-specific removal behavior specification is the [PowerShell removal contract](../../contracts/powershell-removal.md).

## PowerShell behavioral-suite performance measurement

The standard `tests/powershell/run-tests.ps1` entry point is also the performance
measurement entry point. It runs the repository-pinned Pester suite with
`-Output Detailed`, reports shared fake-host creation time, and prints the full
behavioral-validation wall time. Pester's detailed output reports individual
test durations; the GitHub Actions log timestamps on `Running tests from
'...Tests.ps1'` identify file start times. Approximate each file's elapsed
interval by subtracting that timestamp from the next file-start timestamp,
or from `Tests completed in` for the last file. These intervals include
Pester fixture setup and teardown, not just test-body time.

To reproduce a comparable measurement:

1. Use the same commit/test files, pinned Pester version, and PowerShell
   runner/OS family for before-and-after trials. Record the exact commit SHA,
   runner image and PowerShell version, passed/failed/skipped counts, and whether
   the PowerShell dependency cache was warm.
2. Run `pwsh -NoProfile -File ./tests/powershell/run-tests.ps1` as usual, or
   use the `Run PowerShell behavioral tests` step in the repository's Validate
   workflow. The runner's printed wall time includes fixture initialization;
   Pester's `Tests completed in` excludes it.
3. Inspect the timestamped Actions job log in GitHub. Optionally retrieve it
   with `gh run view <run-id> --job <job-id> --log` if GitHub CLI is available.
   Use the `Running tests from` transitions for file-level intervals and the
   Pester `[+]` lines for selected test durations. Compare file counts and
   names, not only the overall elapsed total.
4. Prefer several runs under the same runner class to interpret variance.
   Treat a warm/cold runner or different number of tests as a separate
   comparison, and investigate any failure or newly flaky scenario regardless
   of runtime.

### Optional Verify child-process tracing

Use the standard test entry point to capture diagnostics for the Verify suite
without changing production code or permanently altering any tests:

```powershell
pwsh -NoProfile -File ./tests/powershell/run-tests.ps1 -Suite Verify -TraceVerifyProcesses
```

The switch is **off by default** and requires `-Suite Verify`. A focused run
still executes every Verify test with its independent temporary HOME and the
real child PowerShell processes. The runner prints a ZIP path under the user's
temporary directory containing:

- `test-timings.csv`: test names, timestamps, duration, user time, and Pester overhead;
- `verify-invocations.csv`: each Verify helper's child PowerShell elapsed time,
  exit code, requested SDK version, and unique per-case identifier;
- `fake-host-events.tsv`: UTC start/exit markers, arguments, process IDs and
  elapsed fake-host main-to-exit time, correlated by case and invocation ID;
- `verify-child-events.tsv`: child command entry, product invocation, and
  synthetic metadata start/success/failure markers, correlated by invocation ID;
- `summary.json`: versions, commit when Git is available, counts, elapsed time.

Exit codes from negative Verify scenarios are expected and are still asserted
normally. A fake-host event timestamp starts after native process initialization,
so fake-host elapsed time does **not** measure native startup overhead. Similarly,
child PowerShell elapsed time includes startup, script loading, internal native
probes, and cleanup; it is not merely PowerShell startup time. Child timeline
events come from the test-only command wrapper, not the product. Product-return
markers may be absent when the product intentionally exits the child process.
Tracing creates
additional file I/O and should not be used as the before/after performance
benchmark. Normal CI and local runs remain uninstrumented.

### Detailed single-case Verify step profile

For a focused, **opt-in** step-by-step diagnostic on Windows, run:

```powershell
pwsh -NoProfile -File ./tests/powershell/run-tests.ps1 -Suite Verify -TraceVerifySteps
```

This runs **one tagged Pester test** (the existing optional-tracing regression
case), not the full Verify suite. It exercises two representative subprocess
scenarios in independent sequence: first an expected failure for a missing SDK,
then a successful Verify after installing the deterministic fake SDK fixture.
The original exit-code, output, and trace-correspondence assertions remain
active. Do not combine `-TraceVerifySteps` with `-TraceVerifyProcesses`;
the step flag already enables the latter's existing child and fake-host events.

The runner prints buffered per-step timings at the end and creates the same
temporary ZIP report as regular Verify tracing, with one additional file:
`step-timings.csv`. Each row has `Scope` (`Test`, `Child`, or `Native`),
`InvocationId`, `Scenario`, `Step`, `ElapsedMs` since the preceding
marker **within that scope/invocation**, and `CumulativeMs` since the scope
started (blank for `Native`). Follow each scenario's rows in recorded order;
test-level spans contain the child's time and **must not** be added to child
or native spans as independent work. Correlate child rows with `verify-invocations.csv`,
`verify-child-events.tsv`, and `fake-host-events.tsv` when examining host
probes and process startup.

For this diagnostic **only**, the test creates an instrumented *copy* of the
already-installed PowerShell tool in its unique temporary HOME. Markers inside
that copy bracket local SDK proof (including filesystem preflight, environment
preparation, SDK inventory, origin comparison, and version resolution), metadata
classification, component gathering, failure handling, and report presentation. The child also records
metadata mock, product invocation, and return milestones. The original native
`dotnet` invocation statements are **not altered**. Existing fake-host start
and exit events yield additional `Scope=Native` rows with the native
`dotnet.exe` command and its **Main-to-ProcessExit** duration. The repository's
production tool source is **not edited**, and other tests run the ordinary tool.
Step events accumulate in memory and are written once per child process at
return, and once for the test after teardown. No step events are collected
without the flag.

**Measurement limitations:** the first child-side marker occurs *after*
PowerShell startup. Native host intervals cover only the compiled fake host's managed
`Main` to `ProcessExit`: they exclude process creation, runtime initialization
before `Main`, and PowerShell native-command dispatch and stream processing. Product-function intervals can contain nested instrumentation;
do not sum overlapping parent and child spans. Reporting and test-only code
insertion introduce measurement overhead, so this is a **diagnostic breakdown**,
not a valid before/after throughput benchmark or proof of a production
performance regression. The unmodified `-TraceVerifyProcesses` mode remains
available for full Verify tracing.

### Deep native Verify stack instrumentation (experimental)

On Windows, the following command enables the full diagnostic stack:

```powershell
pwsh -NoProfile -File ./tests/powershell/run-tests.ps1 -Suite Verify -TraceVerifyStack
```

This experimental flag implies `-TraceVerifySteps`, `-TraceVerifyProcesses`, and the
test-only native-host phase markers. Do not combine these switches. It
runs the same one tagged Pester case, plus **four additional fresh child
PowerShell processes**. Each of the latter runs the fake `dotnet.exe --list-sdks`
three times, alternating PowerShell's native-command pipeline and direct
`System.Diagnostics.Process` calls, and comparing reuse of the original already
executed fake host with a **newly copied executable for every iteration**.
Eight short-lived PowerShell children balance the two launch methods and the
two executable-copy conditions. Copy duration is measured separately, outside
the native launch timer. Each child also launches Windows
`cmd.exe /d /c exit 0` as a reference process without the fake host's managed
runtime. Only this flag enables the extra
processes; regular validation is unchanged.

The resulting archive additionally includes:

- `stack-launch-probes.csv` — buffered command timings in each
  control child process, with unique invocation IDs, UTC timestamps, mode,
  exit code, and diagnostics.
- `stack-probe-processes.csv` — total lifecycle wall time for each
  control child PowerShell process.
- `stack-host-startup.tsv` — native fake-host managed `Main`
  checkpoints, including the Windows process creation UTC timestamp, first
  managed instruction, command handling, output, and process-exit event.
- `stack-host-startup-summary.csv` — automatically correlated process-created,
  managed-entry, and exit UTC events, grouped by invocation ID and process ID.
  For the normal SDK inventory command, the summary also correlates the
  PowerShell-local-proof marker with OS process creation, splitting its total
  duration into call-to-process, process-to-managed-entry, and managed execution.

The existing `step-timings.csv` adds UTC markers for the test/child
scopes, product bootstrap, selected action, SDK validation, failure
`Write-Error` boundary and return. All step/host records are
buffered and written at the end of each measured process. The optional
existing per-process trace remains a separate timestamp source.

**Limits:** The Windows OS process-start timestamp is an estimate of the
boundary before managed `Main`, not a continuous trace of the OS loader,
antivirus, or CLR boot internals. Independent clocks and instrumentation
overhead introduce imprecision. Correlate by invocation ID and UTC events,
not by adding overlapping parent, child, and native durations. Cold/warm
commands are ordered controls, not a randomized benchmark; a large
difference identifies a phase to investigate, not its definitive cause.
Do not disable real subprocess validation or change the product to
accommodate profiling results.

### Historical Windows reference

The successful [Issue #161 Validate run](https://github.com/infoconex/isolated-dotnet-sdk/actions/runs/38745162881)
used PR-head commit `bf40568410208de8d87947ef13f691e400b0ad3b`,
`windows-2025`, PowerShell `7.6.6`, and pinned Pester `6.2.0`.
This was the CI-tested source for the subsequent `release/0.4` squash
merge `e4c84accb28ab900974bcaa8bc9607d2fb019893`. The merge verification
confirmed the changed files were identical. The recorded baseline is a
**prior PR run**, not a run executed against the later squash-merge SHA.

| Measurement | Value |
| --- | ---: |
| Passed / failed / skipped | 243 / 0 / 0 |
| Pester test duration | 234.23s |
| PowerShell behavioral-validation wall time | 236.29s |
| Shared fake-host setup | 1.46s |
| Verify file interval | ~46s |
| Transactional Install file interval | ~33s |
| Interactive Lifecycle file interval | ~23s |
| Process-level Behavior file interval | ~18s |
| Interactive Verify file interval | ~12s |
| Global Exit file interval | ~13s |
| Prerelease Picker file interval | ~11s |

The older Windows local observation (236 tests, ~230.68s) and this hosted
run (243 tests, 236.29s) are **not** like-for-like measurements.

### Optimization boundaries

Process startup can dominate some test-file time, but repeated setup
launches must be distinguished from scenario subprocesses. For example,
the original Verify `BeforeEach` started a PowerShell child merely to copy
and bootstrap the test tool before starting separate scenario processes.
A direct byte-for-byte copy to that scenario's own temporary HOME avoids
the unrelated setup process. Dedicated bootstrap tests must still start with
an absent installed tool and execute the actual source entry point.

The interactive lifecycle, interactive Verify, global exit, and prerelease
picker suites likewise prepare an installed script directly while retaining
their real child processes. The process-level Behavior suite keeps its
dedicated source-preservation/bootstrapping and source-color tests, while ten
other scenarios can use direct installed-tool setup. The installed-SDK
listing suite's eight scenarios use their own controlled system-dotnet stubs;
its earlier bootstrap-only stub and launcher were preparation overhead, not
part of the listing contract. Across those seven suites, this removes **85
per-case preparatory PowerShell process launches** without removing their
scenario process executions. Per-case file copies remain inside fresh GUID
test roots, fail immediately on copy errors, and assert the installed script
exists.

An intermediate [Issue #174 Draft PR run](https://github.com/infoconex/isolated-dotnet-sdk/actions/runs/38788626227)
on head `a9a782657500ba41bc5dc88919838bd38156cc37` passed all
243 Windows Pester tests, with Pester duration **196.57s**, an improvement
of **16.1%** versus the previous 234.23s reference. Its fake-host
initialization was **14.18s**, however, versus **1.46s** in the reference;
the full wall times were **211.31s** versus **236.29s**. Do not mistake
that variation in unrelated one-time host setup for a Pester regression or
a test-harness optimization. A later head must be compared separately.

Transactional Install's many `pwsh` calls mostly exercise distinct
transaction, native-host, failure, and exit-code boundaries. Such execution
is not redundant just because it is expensive. The shared fake host is
built once per full suite and should not be rebuilt for each test. Do not
share mutable HOME, SDK directories, test environment variables, or
download/staging state across cases, and do not replace process-boundary
assertions with mocks for the sake of speed.

## Static analysis

Static-analysis scope and version policy are documented in [Static analysis](static-analysis.md). The authoritative analyzer versions are defined in [`.config/static-analysis.json`](../../../.config/static-analysis.json).

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

Real Microsoft/.NET ecosystem coverage is intentionally separate from the deterministic behavioral suites. The repository-owned fixed SDK target, direct and persistent-interactive scenarios, isolated job-state rules, automatic post-merge trigger, and manual rerun procedure are documented in [Real end-to-end validation](e2e-testing.md).

`.github/workflows/e2e.yml` runs automatically on `push` to `main` and also supports `workflow_dispatch` for ad hoc reruns. It runs the supported Windows/PowerShell, Ubuntu/Bash, and macOS/Bash product mappings against live Microsoft release metadata and SDK payload acquisition, checksum verification, extraction, and staged-host verification. It is a post-merge confidence signal, not a required PR or merge check. Automatic merge-candidate E2E gating was proposed in [#60](https://github.com/infoconex/isolated-dotnet-sdk/issues/60), **closed as not planned**; adopting that gate would require a separately approved policy change.

## Stable release publication regression tests

The Node test suite invokes the **real** `.github/scripts/publish-release.js` with isolated local release-source/manifest fixtures and an in-memory GitHub API implementation. It deterministically exercises commit/tag identity, checksum verification, draft/public release state, API failures and cleanup ownership without any remote API requests, GitHub write credentials, or real tag/release mutations.

From the repository root, with Node.js supporting its built-in test runner:

```bash
node --test tests/node/publish-release.test.js
```

Normal `Validate` also runs this suite on Ubuntu, where the actual publication workflow executes. Node's test runner is part of the runtime (like the Bash/PowerShell runtimes), not an additional externally pinned test package. The workflow reports the runner-provided Node version alongside test results. The deterministic suite does **not** replace live publication, candidate E2E, or the read-only `Verify Release` workflow.

## CI

`.github/workflows/validate.yml` uses explicit versioned GitHub-hosted runner labels and repository-owned dependency pins rather than relying on preinstalled tool versions. It runs:

- Bash syntax validation and the Bats behavioral suite on `ubuntu-24.04` and `macos-26`;
- ShellCheck once on `ubuntu-24.04`;
- Node stable-release publisher regression tests once on `ubuntu-24.04`;
- PowerShell parser validation, PSScriptAnalyzer, formatting checks, and the Pester behavioral suite on `windows-2025`.

Validate uses exact-key caches for pinned Bats-core, ShellCheck, Pester, and PSScriptAnalyzer where practical. Cache identity derives from the repository-owned pin/configuration files plus relevant runner/runtime identity. A cache miss acquires the exact configured dependency; a cache hit still revalidates the configured commit, checksum, or module version before use. No broad restore-key fallback accepts an older toolset, and product/E2E SDK or HOME/profile state is not cached.

The dependency-update monitor uses `ubuntu-24.04` and remains separate from product validation. Workflows pin external Actions to full commit SHAs and disable persisted checkout credentials when the checkout is only used for read access.

Versioned hosted-runner labels intentionally pin the OS/architecture family, not an immutable VM image build. GitHub can patch and rebuild a selected hosted image over time; the exact resolved image and build revision are visible in each job log. Repository-owned test frameworks, analyzers, checksums, and action references remain independently pinned so those dependencies do not silently follow runner-image contents.

CI invokes the same repository-owned behavioral/analyzer/formatting commands documented above instead of maintaining parallel CI-only runners. Syntax/parser checks remain inline because they are small shell/runtime primitives rather than a second test harness. Framework failure output is emitted directly by Bats/Pester/Node so CI retains test names, assertion context, and framework diagnostics.

Syntax/parser checks, static analysis/formatting, and behavioral tests remain separate validation layers because they identify different failure classes. Static analyzers intentionally run once per relevant shell; cross-platform duplication is not added without evidence that it catches a platform-specific analyzer contract.
