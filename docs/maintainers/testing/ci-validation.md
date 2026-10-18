# CI validation architecture

`Validate` is the deterministic pre-merge and post-merge confidence layer; only strict documentation-only PRs bypass the expensive behavioral jobs. It intentionally keeps GitHub Actions focused on runner/matrix selection, checkout, GitHub-hosted cache restore/save, and invoking repository-owned validation commands.

## Trigger model

Both workflows retain independent and stable pull-request checks, with separate responsibilities:

- **Validate** is always triggered for PRs. It classifies GitHub's paginated changed-file list (including original and new rename paths), conservatively requires the Windows, Ubuntu and macOS behavioral matrix for everything except root README.md and docs/**/*.md, and reports the **Validation gate**. Classification failure and missing/failed/incorrectly skipped required jobs fail the gate.
- **Pages** is also always triggered for PRs. Its own classifier identifies relevant documentation and website inputs, runs the site build and link/output checks only when required, and reports the independent **Pages gate**. Classification failure, a missing/failed applicable build, or an unexpectedly skipped required build fails that gate. When a PR has no site-relevant change, the build is intentionally skipped and Pages gate still reports success.
- On non-creation pushes to release/** and main, Validate runs the full cross-platform behavioral suite but **never builds documentation**. For release integration branches there is intentionally no automatic Pages publication.
- On relevant pushes to main, Pages builds, checks, uploads and deploys the published site. It is the sole owner of site publication and of documentation-site validation. Pages manual runs may build/check a branch but never deploy; publication requires a push to main.
- Manually dispatched Validate always runs the complete Windows/Ubuntu/macOS behavioral matrix. Manual Pages provides a separate on-demand documentation build.
- Creating a new release/** branch does not start product validation jobs, preserving the no-change branch-creation optimization.

Use a narrow documentation-only **behavioral exclusion**: only root README.md and docs/**/*.md skip cross-platform tests. Every other path triggers the full supported-platform matrix, including source scripts, CI workflows, dependency pins, tests, release material, and unknown paths. For Pages relevance, layouts, assets, scripts that stage/check the site, publication configuration, and release docs also count. Missing/inconsistent GitHub listing data, renames without original paths, or the listing limit fail closed. Mixed PRs run all applicable paths in their respective workflows.

## Required checks and enforcement

The two stable PR job identities are **Validation gate** and **Pages gate**, both with source github-actions. Configure **both** as required checks in the active main and release/** rulesets. Never require individually conditional jobs, since GitHub can consider a skipped job successful. Do not put workflow-level path filters on either PR workflow, since a required check for an untriggered workflow may remain pending. Both gates report an explicit terminal status for every PR.

The repository rulesets previously required PRs/squash merges but no CI checks. Ruleset edits require repository administration and must be verified after applying them; until then the successful checks are advisory, not branch enforced.

## Pages validation and deployment

The Pages build job performs local Markdown file-link checks through .github/scripts/check-documentation-links.js, stages the site through .github/scripts/prepare-pages-source.sh, runs the pinned Jekyll build, and checks generated navigation, release-history linkage, search assets, and bootstrap presence through .github/scripts/validate-pages-output.sh. The local link checker does not validate external HTTP availability or heading anchors.

A relevant Pages PR gets build and gate results without publication or artifact upload. A main push receives the full Pages build and publication pipeline. The distinct E2E and release workflows are not changed by this optimization.

Reproduce routing and link checks locally with:

```bash
node --test tests/node/ci-validation.test.js tests/node/documentation-links.test.js
node .github/scripts/check-documentation-links.js
```

## Measured baseline

On October 18, 2026, documentation-only PR #207 consumed 48 runner-seconds Ubuntu, 62 macOS, and 201 Windows in Validate (311 combined; 206 elapsed), and 26 runner-seconds in Pages. Earlier smoke-test PR #210 confirmed that the conditional behavioral jobs can skip successfully. This two-workflow design eliminates three behavioral runners for docs-only changes, does not launch documentation builds from Validate, and retains a dedicated required-check identity for each workflow. Compare GitHub job results and timestamps on actual PR heads instead of treating timing as a hard fail threshold.

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
