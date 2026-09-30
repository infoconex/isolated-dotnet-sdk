# Static analysis

The repository uses static analysis as an automated quality signal for the PowerShell and Bash implementations. Static analysis must not be treated as authority to change runtime behavior without separate evidence and review.

## Analyzer versions

`.config/static-analysis.json` is the authoritative source for pinned static-analysis tool versions and version-coupled installation metadata.

The PowerShell runner, Bash runner, and CI installation steps must consume that file rather than independently declaring analyzer versions. Version changes should be intentional repository changes so new analyzer behavior and findings are reviewed explicitly.

The config currently owns:

- the required PSScriptAnalyzer version;
- the required ShellCheck version;
- the checksum for the pinned Linux x64 ShellCheck release archive used by CI.

## PowerShell analysis scope

PSScriptAnalyzer analyzes the repository-owned PowerShell surface:

- `isolated-dotnet-sdk.ps1`;
- every `*.ps1` support script directly under `scripts/`;
- every `*.ps1` test/runner file directly under `tests/powershell/`.

The runner discovers those support and test files deterministically by path instead of maintaining a hand-written list. Adding a new PowerShell support script or Pester file in those directories therefore brings it into the existing analyzer contract automatically.

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

Presentation color is selected by explicit semantic role at the call site rather than inferred from punctuation. Interactive/menu and section headings use a restrained cyan accent, success messages use green, and ordinary informational text, values, choices, and paths remain neutral. PowerShell warning and error colors remain owned by their semantic streams; Bash warnings retain their warning presentation while failures stay on stderr. `PlainText`/`NO_COLOR` PowerShell execution is not decorated, and redirected/captured output from both implementations must not contain ANSI escape sequences.

`Remove-IsolatedSdk` now implements native `ShouldProcess` semantics and no longer suppresses `PSUseShouldProcessForStateChangingFunctions`. Its `-WhatIf`, `-Confirm`, default confirmation, and `-Yes` behavior is specified in [`powershell-removal.md`](powershell-removal.md) and protected by the dedicated removal behavioral suite.

PowerShell helper naming follows the conventions recorded in [`coding-consistency.md`](coding-consistency.md), including the deliberate use of analyzer-aligned singular nouns for collection-returning Verb-Noun functions.

## CI execution

Each analyzer should run once in CI unless cross-platform analyzer execution provides demonstrated value:

- PSScriptAnalyzer on the Windows PowerShell job;
- ShellCheck on the Ubuntu Bash job.

Existing syntax/parser validation and cross-platform behavioral tests remain separate validation layers and must stay enabled.
