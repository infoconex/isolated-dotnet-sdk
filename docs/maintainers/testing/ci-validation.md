# CI validation architecture

`Validate` is the deterministic pre-merge and post-merge confidence layer; only strict documentation-only PRs bypass the expensive behavioral jobs. It intentionally keeps GitHub Actions focused on runner/matrix selection, checkout, GitHub-hosted cache restore/save, and invoking repository-owned validation commands.

## Trigger model

The Validate workflow continues to run for every pull request without workflow-level path filtering. The lightweight Classify required validation job uses a paginated GitHub changed-file listing plus the reported count. Only root README.md and docs/**/*.md, including renames wholly within this allowlist, qualify for documentation-only validation. All other paths (product, tests, workflows, test configuration, release material, and unknown files) require the complete Ubuntu/macOS/Windows behavioral suite. Mixed changes run both documentation and behavioral checks.

Documentation-site inputs include layouts, CSS/JS assets, release notes, installer wrappers, Pages/Validate workflow files, and relevant configuration. They are NOT automatically exempted from behavioral validation. Old and new rename paths are classified. Missing or inconsistent API results, malformed paths, and listing limits fail closed and prevent approval.

A non-creation push to main or release/** and a manually dispatched Validate run always execute the full behavioral matrix AND documentation validation. No-change release-branch creation still skips runner execution. Working-branch pushes do not duplicate PR-head validation.

Every non-creation run includes the stable Validation gate job, which explicitly requires successful classification and each selected job, and expects intentionally unnecessary jobs to be skipped. GitHub's green skipped-job conclusion alone is insufficient evidence. The gate fails when required work is missing, failed, cancelled, or unexpectedly skipped. Deterministic regression tests cover this decision policy.

Active main/release GitHub rulesets currently require a pull request and squash merge but do not require CI. After verifying the live check name, configure BOTH rulesets to require the stable Validation gate check. This requires repository administration permission, which the connected GitHub App may not have; until an administrator applies it, passing CI remains advisory rather than branch-enforced. Do not add workflow-level path filtering to Validate, which can leave required checks pending.

## Documentation and Pages validation

Relevant PRs run the Documentation site job inside Validate. It checks repository-relative Markdown file paths, stages the documentation site, builds it using the pinned Pages Jekyll action, and validates generated pages, navigation, search assets, bootstrap files, and release-history consistency. Fragment headings and external HTTP links are not verified by the local link checker.

Both workflows use shared prepare-pages-source.sh and validate-pages-output.sh scripts in .github/scripts. Pages no longer builds a second copy for PRs; it retains its relevant main-push deployment and manual dispatch. Validate independently checks documentation on every main/release push for stronger post-merge confidence. Keeping the deployment workflow separate is intentional.

Baseline from documentation-only PR #207 on October 18, 2026: Validate run 39156528601 used 48 seconds Ubuntu, 62 seconds macOS, and 201 seconds Windows (311 combined runner-seconds, about 206 wall seconds). Pages PR build run 39156528592 used 26 seconds. Compare new doc-only job counts and hosted times with these measurements, accounting for queue and runner variability.

Local policy tests: node --test tests/node/ci-validation.test.js tests/node/documentation-links.test.js
Local documentation links: node .github/scripts/check-documentation-links.js

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

The deterministic fake `dotnet` executable used by transaction/finalization tests is built once per PowerShell behavioral run and exposed to those suites as an immutable run-scoped fixture. Each test still creates and removes its own mutable HOME, SDK root, release-metadata/payload state, staging state, and environment controls.

On the supported Windows runner, fixture compilation prefers the Windows .NET Framework C# compiler to avoid the substantially heavier SDK restore/build startup path. The helper retains a `dotnet build` fallback for development environments where that compiler is unavailable.

Real `pwsh` subprocess boundaries are retained for tests that prove process-level exit status, bootstrap/source behavior, environment/profile isolation, streams, native-command failure propagation, shell invocation semantics, or transaction behavior that crosses the public script boundary. Those tests are intentionally not converted to in-process calls merely to improve timing.

## Timing and performance expectations

`tests/powershell/run-tests.ps1` reports both shared fake-host setup time and total behavioral-run wall time. Pester continues to report its own test-suite duration and per-test diagnostics. GitHub Actions job timestamps provide the overall Validate job duration for comparison across runner-image changes.

The Issue #62 pre-change hosted baseline on `windows-2025` was approximately 130 seconds for the full PowerShell Validate job, with Pester reporting 92.46 seconds for 101 tests. Ubuntu and macOS Validate jobs were approximately 13.7 and 14.0 seconds respectively. These measurements are comparison evidence, not brittle hard-fail thresholds: runner-image and service load can vary.

The maintained expectation is that validation changes should not materially regress the Bash jobs and should keep avoidable PowerShell setup/process overhead out of the suite. A hosted Windows behavioral result around or below one minute is desirable when it can be achieved without weakening deterministic coverage or removing a meaningful process boundary. When that target conflicts with confidence, preserving the contract takes priority and the measured result should be recorded in the issue/PR evidence.

## Relationship to E2E

`Validate` remains repository-controlled and deterministic. `.github/workflows/e2e.yml` is the separate real Microsoft/.NET ecosystem signal that runs automatically after merge to `main` and can be invoked manually.

During an active next-release integration cycle, deterministic Validate runs after landed changes on the release integration branch, while real E2E remains a release-level signal that can be invoked manually on the integrated candidate before the final release PR. After the approved candidate merges to `main`, the normal automatic E2E run provides landed release-source evidence before publication.

E2E intentionally does not share or cache installed product SDK/HOME state with deterministic validation. Automatic merge-candidate E2E gating is **not current policy**: [#60](https://github.com/infoconex/isolated-dotnet-sdk/issues/60) was closed as not planned. Real E2E remains an optional manual integration-candidate signal and a normal post-`main`-merge release signal unless a separately approved policy change is adopted.
