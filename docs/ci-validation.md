# CI validation architecture

`Validate` is the deterministic pre-merge and post-merge confidence layer. It intentionally keeps GitHub Actions focused on runner/matrix selection, checkout, GitHub-hosted cache restore/save, and invoking repository-owned validation commands.

## Responsibility split

`.github/workflows/validate.yml` owns GitHub-specific orchestration:

- supported versioned runner labels and matrices;
- immutable GitHub Action SHA references;
- checkout policy and least-privilege workflow permissions;
- GitHub Actions cache restoration/saving and cache keys;
- ordering of repository-owned validation commands.

Repository scripts own reusable setup and validation behavior:

- `scripts/initialize-bash-validation.sh` validates Bash/E2E syntax, resolves pinned Bats-core and ShellCheck configuration, installs missing pinned tooling, verifies a restored Bats commit marker and ShellCheck checksum/version, and publishes the Bats path to GitHub Actions when `GITHUB_PATH` is available;
- `scripts/Initialize-PowerShellValidation.ps1` validates PowerShell/E2E syntax, resolves pinned Pester and PSScriptAnalyzer versions, installs missing pinned modules, validates restored module manifests/versions, and publishes `PSModulePath` to GitHub Actions when requested;
- `scripts/run-shellcheck.sh`, `scripts/Invoke-PSScriptAnalyzer.ps1`, `scripts/Invoke-PSFormatter.ps1`, and the shell-specific behavioral runners remain the normal validation entry points.

Moving setup into repository scripts is not a relaxation of dependency controls. Exact version/commit/checksum configuration remains repository-owned, cache hits are revalidated before use, and there are no broad restore-key fallbacks. Product SDK state, E2E-installed SDKs, temporary test HOME/profile state, and other mutable test state are not cached.

## Local reproduction

The setup scripts accept the same cache-root conventions used by CI but can also be run outside GitHub Actions. A local caller is responsible for providing the external prerequisites needed by the selected setup path, such as `jq`, Git, PowerShell, and network access on a cache miss.

On Bash-compatible systems, a cache-miss-equivalent setup can be run with:

```bash
RUNNER_OS=Linux RUNNER_TEMP="${TMPDIR:-/tmp}" \
  bash scripts/initialize-bash-validation.sh false false
```

Then run the normal repository validation commands:

```bash
bash scripts/run-shellcheck.sh
bash tests/bash/run-tests.sh
```

On Windows/PowerShell, choose a user-owned temporary module root and run:

```powershell
$moduleRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'isolated-dotnet-sdk-validation-modules'
./scripts/Initialize-PowerShellValidation.ps1 `
    -ModuleRoot $moduleRoot `
    -CacheHit:$false

$env:PSModulePath = "$moduleRoot$([System.IO.Path]::PathSeparator)$env:PSModulePath"
./scripts/Invoke-PSScriptAnalyzer.ps1
./scripts/Invoke-PSFormatter.ps1 -Check
./tests/powershell/run-tests.ps1
```

The setup scripts fail with explicit diagnostics when required configuration, cached identity, checksum/version verification, or installation fails.

## PowerShell behavioral fixture

The deterministic fake `dotnet` executable used by transaction/finalization tests is built once per PowerShell behavioral run and exposed to those suites as an immutable run-scoped fixture. Each test still creates and removes its own mutable HOME, installer, SDK root, staging state, and environment controls.

On the supported Windows runner, fixture compilation prefers the Windows .NET Framework C# compiler to avoid the substantially heavier SDK restore/build startup path. The helper retains a `dotnet build` fallback for development environments where that compiler is unavailable.

Real `pwsh` subprocess boundaries are retained for tests that prove process-level exit status, bootstrap/source behavior, environment/profile isolation, streams, native-command failure propagation, shell invocation semantics, or transaction behavior that crosses the public script boundary. Those tests are intentionally not converted to in-process calls merely to improve timing.

## Timing and performance expectations

`tests/powershell/run-tests.ps1` reports both shared fake-host setup time and total behavioral-run wall time. Pester continues to report its own test-suite duration and per-test diagnostics. GitHub Actions job timestamps provide the overall Validate job duration for comparison across runner-image changes.

The Issue #62 pre-change hosted baseline on `windows-2025` was approximately 130 seconds for the full PowerShell Validate job, with Pester reporting 92.46 seconds for 101 tests. Ubuntu and macOS Validate jobs were approximately 13.7 and 14.0 seconds respectively. These measurements are comparison evidence, not brittle hard-fail thresholds: runner-image and service load can vary.

The maintained expectation is that validation changes should not materially regress the Bash jobs and should keep avoidable PowerShell setup/process overhead out of the suite. A hosted Windows behavioral result around or below one minute is desirable when it can be achieved without weakening deterministic coverage or removing a meaningful process boundary. When that target conflicts with confidence, preserving the contract takes priority and the measured result should be recorded in the issue/PR evidence.

## Relationship to E2E

`Validate` remains repository-controlled and deterministic. `.github/workflows/e2e.yml` is the separate real Microsoft/.NET ecosystem signal that runs automatically after merge to `main` and can be invoked manually. It intentionally does not share or cache installed product SDK/HOME state with deterministic validation. Merge-candidate E2E enforcement remains separate work tracked by Issue #60.
