# Dependency update monitoring

Repository-owned dependency pins are intentionally immutable until a reviewed repository change adopts an update. Update monitoring exists to discover newer stable upstream releases and provide review context; it does not make dependency selection float at validation or runtime.

## Policy

- Use GitHub-supported Dependabot where it natively understands the dependency surface.
- Use repository-owned discovery only for pins stored in custom configuration that Dependabot does not natively maintain.
- Treat stable upstream releases as update candidates by default. Prereleases are ignored unless repository policy is intentionally revised.
- Discovery must never rewrite a version, commit, checksum, blob ID, raw URL, or product constant.
- A dependency update is adopted only through a normal reviewed pull request that updates every coupled integrity/provenance value together.
- Monitoring failures are visible failures. An unavailable or malformed authoritative source must not be interpreted as "up to date."
- Scheduled discovery should be low-noise: one outstanding review artifact is reconciled as the candidate set changes instead of opening duplicate artifacts for the same state.
- Dependency update automation must not auto-merge.

## Pin inventory

| Dependency | Repository-owned pin | Integrity / provenance coupling | Authoritative update source | Monitoring mechanism |
| --- | --- | --- | --- | --- |
| GitHub Actions (`actions/checkout`) | Full commit SHA plus readable release comment in repository workflows | Immutable action commit SHA | GitHub Actions dependency metadata / upstream action releases | Weekly Dependabot `github-actions` updates from `.github/dependabot.yml` |
| PSScriptAnalyzer | `psScriptAnalyzerVersion` in `.config/static-analysis.json` | Exact PowerShell Gallery module version | PowerShell Gallery package metadata | Repository-owned unsupported-pin monitor |
| Pester | `pesterVersion` in `.config/test-frameworks.json` | Exact PowerShell Gallery module version | PowerShell Gallery package metadata | Repository-owned unsupported-pin monitor |
| ShellCheck | `shellCheckVersion` in `.config/static-analysis.json` | Linux x64 release archive SHA-256 in the same configuration | Official `koalaman/shellcheck` GitHub stable releases | Repository-owned unsupported-pin monitor |
| Bats-core | `batsVersion` plus `batsCommit` in `.config/test-frameworks.json` | Release version must resolve to the reviewed immutable upstream commit | Official `bats-core/bats-core` GitHub stable releases and release tag object | Repository-owned unsupported-pin monitor |

The Microsoft `dotnet/install-scripts` helper is no longer a product runtime dependency after Issue #72. SDK acquisition now consumes Microsoft's per-version release metadata and payload checksum dynamically for the exact requested SDK rather than pinning a helper release, so there is no helper dependency pin for this monitor to track.

There are currently no repository-owned executable/module/tool pins that require a manual-only monitoring exception. If a future dependency cannot be monitored from a deterministic authoritative package or release source, document that exception here with the reason and review cadence instead of adding heuristic scraping.

## Unsupported-pin monitor

`.github/workflows/dependency-update-monitor.yml` runs the repository-owned monitor once per week and supports `workflow_dispatch` for an intentional on-demand check. It uses only the repository's immutable `actions/checkout` pin, grants `contents: read` plus `issues: write`, and does not receive pull-request write permission.

The workflow runs two repository-owned PowerShell scripts:

1. `scripts/Invoke-DependencyUpdateCheck.ps1` reads the current pins, queries authoritative upstream package/release sources, and writes deterministic JSON and Markdown results under the runner's temporary directory.
2. `scripts/Sync-DependencyUpdateIssue.ps1` reconciles those results with one GitHub tracking issue titled `Pinned dependency updates available`.

The discovery step runs before issue synchronization. If an upstream query, release shape, version, or immutable release-commit resolution fails, the workflow fails and the synchronization step does not run. A failed lookup therefore cannot close an existing update issue or turn an unknown state into a false "current" result.

The synchronization contract is intentionally idempotent:

- updates plus no existing tracking issue: create it;
- updates plus an open tracking issue: update its body;
- updates plus the prior closed tracking issue: reopen and update it;
- no updates plus an open tracking issue: update it with the current report and close it;
- no updates plus no tracking issue, or an already closed one: make no issue mutation;
- more than one exact-title tracking issue: fail visibly so duplicate state is reconciled deliberately rather than guessing.

The workflow uses a concurrency group so scheduled/manual executions do not race one another while deciding the tracking-issue state. It does not modify repository files, create dependency branches, open dependency pull requests, or merge anything.

## Review artifact contract

The unsupported-pin monitor reports each available update with:

- dependency name;
- current repository-owned version/release value;
- newer stable candidate value;
- authoritative upstream release or package URL;
- integrity/provenance metadata that must be reviewed together when the update is adopted.

The durable GitHub review artifact is discovery state, not an implementation branch and not permission to update automatically. The exact-title tracking issue is reused rather than duplicated as candidate state changes. When no unsupported dependency has a newer candidate, the scheduled check succeeds without proposing a repository change and closes the previously open tracking issue when one exists.

## Coupled update requirements

### ShellCheck

Changing `shellCheckVersion` requires reviewing the selected upstream release asset and replacing `shellCheckLinuxX64Sha256` with the digest for that exact Linux x64 archive. Verification-before-extraction remains mandatory.

### Bats-core

Changing `batsVersion` requires resolving the selected stable release tag to its immutable commit and updating `batsCommit` in the same reviewed change. CI must continue fetching and checking out that exact commit rather than a mutable tag.

## Maintainer workflow

1. Review the monitor's current-versus-candidate report and authoritative upstream release/package context.
2. Decide whether the update is wanted; discovery alone does not require adoption.
3. Create a focused repository issue/branch when the update warrants implementation.
4. Resolve and verify all coupled commit/checksum/provenance values from authoritative sources.
5. Update pins and coupled metadata together, using behavioral TDD only when observable behavior changes; use the documented mechanical dependency-pin exception when behavior is preserved.
6. Run repository-owned validation and review the complete diff before opening the Draft PR under the normal issue lifecycle.
7. Use the normal explicit Ready-for-Review and merge approvals. Monitoring never bypasses those lifecycle gates and never auto-merges.

GitHub Actions remain a special case only in discovery mechanics: Dependabot opens the reviewable update PR directly, but immutable SHA pinning, repository validation, explicit readiness, and explicit merge approval still apply.
