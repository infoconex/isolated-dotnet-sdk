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

`.github/workflows/e2e.yml` runs automatically on `push` to `main` after a release candidate or released-line fix lands and also supports `workflow_dispatch` for ad hoc or release-candidate runs. It is a real-system confidence layer and is not a required normal issue-PR check while the repository remains under personal-account ownership.

During an active next-release integration cycle, routine issue PRs target the release integration branch and rely on deterministic Validate. Before the final release-candidate PR to `main`, maintainers can use `workflow_dispatch` to exercise the integrated candidate against live Microsoft/.NET infrastructure. After the approved candidate lands on `main`, the normal automatic E2E run provides exact landed-source evidence required before stable publication.

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
4. run the public standalone Verify action and require a healthy result;
5. run List and require the configured isolated version to appear in the installed-SDK output;
6. run Audit against live Microsoft metadata and require the configured isolated version to be assessed, without pinning a transient servicing status;
7. remove the configured SDK;
8. require the isolated SDK directory to be absent afterward.

Exact-version installation intentionally bypasses release-index/channel selection, but exact-version Microsoft release-metadata lookup, SDK payload download, SHA-512 verification, extraction, and staged-host verification remain real.

### Interactive scenario

The interactive scenario also uses live Microsoft release metadata. Before the persistent session starts, the driver invokes the real Install picker once and parses the displayed `.NET <channel>` line to discover the current numeric channel selection. It does not assume a fixed release-menu ordinal.

The persistent session then:

1. enters Install with the Main menu's `I` command;
2. selects the discovered channel;
3. exercises `Back to .NET channels`;
4. selects the discovered channel again;
5. uses the picker’s semantic manual-version option to enter the configured fixed SDK version;
6. verifies return to Main after installation;
7. runs List with `L` and verifies the installed SDK is displayed;
8. runs Verify with `V`, selects the only job-local isolated SDK, requires a healthy result, and verifies return to Main;
9. runs Remove with `R` for that isolated SDK and verifies return to Main;
10. exits explicitly with `E` and requires a successful process result;
11. verifies the SDK is absent afterward.

The E2E driver may use the tool’s `-Yes` / `--yes` confirmation control so hosted-runner system SDK inventory cannot introduce an extra confirmation-input branch. `-Yes` / `--yes` does not choose menu items and does not replace the persistent interactive session.

## Trigger and gating model

The automatic `push: main` trigger proves the exact source state that actually landed on the released-production line against live Microsoft/.NET infrastructure. `workflow_dispatch` remains available to validate the active release integration candidate or rerun the same live suite without creating another commit.

E2E is intentionally not triggered on every pull request and is not a required normal issue-merge check yet. Future organization-backed merge-queue work may promote E2E into required merge-candidate gating. Until that protection exists and is demonstrated:

- deterministic PR Validate is the authoritative normal pre-merge signal;
- deterministic Validate runs on landed `release/**` and `main` updates;
- manual E2E is appropriate for an integrated release candidate when release-level confidence is needed before promotion; and
- automatic `push: main` E2E remains required landed-source evidence before stable publication.

## What E2E does not own

The live suite is deliberately small. Its Audit assertion proves the real online metadata path and installed-version reporting, but deliberately does not pin a moving Current/Update/Security/Maintenance result. It does not replace deterministic tests for metadata failures, network failures, lifecycle/security classification, filesystem boundaries, transactional install behavior, native-command propagation, cleanup, invalid input, or other exhaustive edge cases.
