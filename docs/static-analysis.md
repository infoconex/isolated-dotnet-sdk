# Static analysis

The repository uses static analysis as an automated quality signal for the PowerShell and Bash implementations. Static analysis must not be treated as authority to change runtime behavior without separate evidence and review.

## Analyzer versions

The initial analyzer contract is pinned for deterministic local and CI execution:

- PSScriptAnalyzer `1.25.0`
- ShellCheck `0.11.0`

Version changes should be intentional repository changes so new analyzer behavior and findings are reviewed explicitly.

## PowerShell analysis scope

PSScriptAnalyzer analyzes:

- `isolated-dotnet-sdk.ps1`
- `tests/powershell/run-tests.ps1`
- `scripts/Invoke-PSScriptAnalyzer.ps1`

The repository-owned runner must fail with a nonzero exit code when PSScriptAnalyzer reports findings.

## Bash analysis scope

ShellCheck analyzes:

- `isolated-dotnet-sdk.sh`
- `tests/bash/run-tests.sh`
- `scripts/run-shellcheck.sh`

The repository-owned runner must propagate ShellCheck's nonzero exit code when findings are reported.

## Rules and suppressions

Start with each analyzer's default rules. Do not add repository-wide exclusions or suppressions without an observed, concrete need.

Any suppression must be as narrow as practical and documented with its rationale. If an analyzer finding could require a behavior change, preserve the current behavior and track the remediation separately rather than changing semantics as part of static-analysis setup.

## CI execution

Each analyzer should run once in CI unless cross-platform analyzer execution provides demonstrated value:

- PSScriptAnalyzer on the Windows PowerShell job;
- ShellCheck on the Ubuntu Bash job.

Existing syntax/parser validation and cross-platform behavioral tests remain separate validation layers and must stay enabled.
