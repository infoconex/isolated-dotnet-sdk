# Real end-to-end validation

This repository keeps deterministic validation and real ecosystem validation as separate signals.

## Deterministic Validate

`.github/workflows/validate.yml` remains the normal development and regression pipeline. It owns parser/syntax checks, static analysis, formatting, and deterministic behavioral/integration coverage across the supported product mappings.

Pinned validation dependencies are repository-owned through `.config/test-frameworks.json` and `.config/static-analysis.json`. CI may cache those tools as an optimization, but the pin/configuration files remain authoritative.

Cache requirements:

- exact keys are derived from the relevant repository-owned configuration plus runner OS/architecture and, for PowerShell modules, the PowerShell runtime version;
- no broad restore-key fallback accepts an older toolset;
- cache hits are verified against the configured version/identity before use;
- cache misses acquire the exact configured dependency and then populate the exact-key cache;
- ShellCheck checksum verification remains mandatory;
- caching must not weaken immutable commit, version, checksum, or repository-owned pinning controls;
- E2E SDK installations, temporary HOME/profile state, and other product test state are never cached.

## Live E2E

`.github/workflows/e2e.yml` runs automatically on `push` to `main` after changes land and also supports `workflow_dispatch` for ad hoc reruns. It is a real-system confidence layer and is not a required PR or merge check while the repository remains under personal-account ownership.

The workflow runs only the supported product mappings:

- Windows / PowerShell 7;
- Ubuntu / Bash;
- macOS / Bash.

Each job uses job-local temporary HOME/profile state so an E2E run cannot reuse or contaminate a normal runner profile or another E2E job.

The fixed SDK target is stored in `.config/e2e.json`. The test intentionally uses a fixed SDK version instead of a moving latest version so a failure can be reproduced and diagnosed.

### Direct-command scenario

The direct scenario uses the checked-out repository tool and real Microsoft infrastructure to:

1. bootstrap the tool into the job-local home;
2. install the configured exact SDK;
3. execute that isolated SDK and require its reported version to equal the configured version;
4. list isolated SDKs and require the configured version to appear;
5. remove the configured SDK;
6. require the isolated SDK directory to be absent afterward.

Exact-version installation intentionally bypasses release-metadata selection, but installer acquisition and SDK payload download remain real.

### Interactive scenario

The interactive scenario also uses live Microsoft release metadata. Before the persistent session starts, the driver invokes the real Install picker once and parses the displayed `.NET <channel>` line to discover the current numeric channel selection. It does not assume a fixed release-menu ordinal.

The persistent session then:

1. enters Install;
2. selects the discovered channel;
3. exercises `Back to .NET channels`;
4. selects the discovered channel again;
5. uses the picker’s semantic manual-version option to enter the configured fixed SDK version;
6. verifies return to Main after installation;
7. runs List and verifies the installed SDK is displayed;
8. runs Remove for the single job-local isolated SDK and verifies return to Main;
9. exits explicitly and requires a successful process result;
10. verifies the SDK is absent afterward.

The E2E driver may use the tool’s `-Yes` / `--yes` confirmation control so hosted-runner system SDK inventory cannot introduce an extra confirmation-input branch. `-Yes` / `--yes` does not choose menu items and does not replace the persistent interactive session.

## Trigger and gating model

The automatic `push: main` trigger proves the exact code that actually landed on the default branch against live Microsoft/.NET infrastructure. `workflow_dispatch` remains available when a maintainer needs to rerun the same live suite without creating another commit.

E2E is intentionally not triggered on pull requests and is not a required merge check yet. Issue #60 owns future organization-backed merge-queue enforcement and required merge-candidate E2E gating. Until that protection exists and is demonstrated, deterministic `push: main` Validate remains enabled as the normal post-merge deterministic signal.

## What E2E does not own

The live suite is deliberately small. It does not replace deterministic tests for metadata failures, network failures, filesystem boundaries, transactional install behavior, native-command propagation, cleanup, invalid input, or other exhaustive edge cases.
