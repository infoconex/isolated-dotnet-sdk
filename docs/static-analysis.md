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

To keep local and CI analysis deterministic, the runner ignores the caller's `SHELLCHECK_OPTS` and user-level `.shellcheckrc` configuration. Repository-owned source directives remain effective and must follow the suppression policy below.

## Rules and suppressions

Start with each analyzer's default rules and remediate findings when a standards-compliant implementation is practical. Do not add repository-wide exclusions or suppressions merely to make analysis pass.

A suppression is acceptable only when the rule genuinely does not apply or when remediation would change an explicit behavioral contract that must be specified and tested separately. Suppressions must be as narrow as practical, remain visible near the affected code, and include a concrete rationale. Temporary suppressions must reference the issue that tracks their removal or behavioral resolution.

The PowerShell CLI does not suppress `PSAvoidUsingWriteHost`. User-facing display and status messages use the information stream, warnings use the warning stream, and failures use the error stream so presentation does not become success-pipeline data.

PowerShell presentation color is applied only at the presentation boundary using `$PSStyle`. Informational prefixes use cyan and success prefixes use green when ANSI rendering is appropriate. Warning and error colors remain owned by their semantic PowerShell streams. `PlainText`/`NO_COLOR` execution is not decorated, and default redirected information output must not contain ANSI escape sequences.

`PSUseShouldProcessForStateChangingFunctions` remains narrowly suppressed only for `Remove-IsolatedSdk` while issue #11 defines and tests the intended `ShouldProcess`, `-Confirm`, `-WhatIf`, and existing `-Yes` semantics.

## CI execution

Each analyzer should run once in CI unless cross-platform analyzer execution provides demonstrated value:

- PSScriptAnalyzer on the Windows PowerShell job;
- ShellCheck on the Ubuntu Bash job.

Existing syntax/parser validation and cross-platform behavioral tests remain separate validation layers and must stay enabled.
