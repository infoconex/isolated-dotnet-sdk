# PowerShell and Bash behavioral parity

The PowerShell and Bash implementations target the same product-level behavior where the contract is shared. Parity is judged at observable boundaries such as action selection, exact-version handling, confirmation, failure propagation, installation ownership, cleanup, and exit status. It does not require source-code structure, shell idioms, presentation streams, or platform mechanics to be identical.

## Shared contract

| Behavior | Shared contract |
| --- | --- |
| Bare exact version | Treat it as an Install request. |
| Explicit Install with a version | Bypass Microsoft release-metadata discovery and install that exact version. |
| Install without a version | Use the interactive release/channel/version picker. Explicit picker cancellation is a successful no-change result. |
| Existing matching isolated SDK | Report it as already installed and return success without downloading or reinstalling. |
| Pre-existing non-valid destination | Fail closed and preserve the destination. |
| Normally installed matching SDK | Ask before creating an isolated copy unless the shell's explicit confirmation-bypass option is supplied. |
| `-Yes` / `--yes` | Bypass supported confirmation prompts only. It does not invent a version or bypass an unresolved selection prompt. |
| Required interactive input unavailable | Fail nonzero with repository-owned `Interactive input is unavailable.` context rather than looping or treating EOF as cancellation. |
| Explicit interactive no/blank/q cancellation | Return success with no state change where that response is part of the prompt's normal cancellation contract. |
| List | Report the isolated SDK root and recognized installed version directories; report `None` when empty. |
| Explicit List plus Version | Reject the version instead of silently ignoring it. |
| Remove without a version | Present the installed isolated SDK picker. Explicit cancellation or an empty installed set is a normal no-change result. |
| Remove with a version | Target only that version's directory under the isolated SDK root. |
| Removal confirmation | Default to no unless approval is explicitly supplied through the shell's supported mechanism. |
| Build-server shutdown | Must succeed before deletion. Failure identifies the selected SDK and native exit code where available, blocks deletion, and suppresses removal success. |
| Helper download / installer / verification / promotion failure | Return nonzero and do not report install success. |
| Operational failure | Return a nonzero status. Exact numeric status need not be identical across runtimes unless a narrower contract specifies it. |
| Diagnostics | Identify the failed product operation. Runtime-specific command/exception detail may be appended when useful. |

## Transactional installation baseline

Issue #18 established the installation ownership and recovery baseline for both shells. Behavioral parity work must preserve these rules:

- each new install uses an operation-owned Microsoft install helper;
- installation occurs in an operation-owned staging directory rather than directly in the final version directory;
- the staged host must exist, execute successfully, and report the requested exact SDK before promotion;
- a pre-existing final destination is never replaced or adopted accidentally;
- a final destination that appears before promotion blocks promotion and is preserved;
- clean-start failures do not leave a new final destination;
- operation-owned helper and staging state is cleaned after success or failure when cleanup is possible;
- cleanup failure is reported and does not mask the primary failure;
- a failed clean-start attempt can be retried deterministically.

This contract intentionally says nothing about making the Microsoft install helper persistent state. Install helpers and staging directories are transaction-scoped artifacts.

## Interactive and automation behavior

Automation should provide both the action and exact version when a version is required. `-Yes` and `--yes` are confirmation controls, not selection controls.

For example, `Install <exact-version> -Yes` / `install <exact-version> --yes` can run without the normally-installed-SDK confirmation. `Install -Yes` / `install --yes` still needs interactive selection because no version has been resolved. If that input cannot be obtained, the command fails rather than guessing or silently cancelling.

An explicit user decision to cancel is different from input failure. A blank/no answer at a default-no confirmation and `q`/`Q` at a documented picker remain successful no-change outcomes.

## Intentional runtime and platform differences

The following differences are intentional and are not parity defects:

- PowerShell removal uses native `SupportsShouldProcess` and therefore supports `-WhatIf`, `-Confirm`, and `-Confirm:$false`. Bash does not emulate those PowerShell facilities; it uses the tool-owned default-no prompt and `--yes` / `-y`.
- PowerShell uses PowerShell information, warning, and error semantics plus `$PSStyle`. Bash uses normal shell stdout/stderr and terminal-aware ANSI presentation. Output does not need to be byte-for-byte identical or use identical streams.
- PowerShell action and parameter names follow normal PowerShell case-insensitive command semantics. Bash command names and options follow normal shell CLI case sensitivity.
- PowerShell exposes comment-based help; Bash exposes `--help` / `-h`.
- The isolated host is platform-specific (`dotnet.exe` on Windows and executable `dotnet` on Linux/macOS).
- File-based bootstrap re-executes through PowerShell's child-script invocation on Windows and Bash `exec` on Linux/macOS. Both must preserve the saved tool's result, but the mechanics need not match.
- Runtime-specific exception or native-command detail can differ after repository-owned product context identifies the failed operation.

## Deferred boundaries

This parity contract deliberately does not absorb later roadmap work:

- broad failure and boundary coverage consolidation remains Issue #20;
- stable-release bootstrap, development-source selection, and self-update policy remain Issue #21;
- additional cross-platform path and race-condition hardening remains with Issue #20 or Issue #27 as applicable;
- general CLI/help redesign, formatting cleanup, and source-structure normalization are not parity requirements.

## Regression protection

The repository's Pester and Bats suites protect the focused shared behaviors, while the existing transactional-install suites protect the Issue #18 baseline. See [testing.md](testing.md) for the repository-owned validation commands and CI matrix, and [native-command-failures.md](native-command-failures.md) for correctness-significant native command boundaries.