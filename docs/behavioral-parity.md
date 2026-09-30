# PowerShell and Bash behavioral parity

The PowerShell and Bash implementations target the same product-level behavior where the contract is shared. Parity is judged at observable boundaries such as action selection, exact-version handling, confirmation, failure propagation, installation ownership, cleanup, and exit status. It does not require source-code structure, shell idioms, presentation streams, or platform mechanics to be identical.

The supported operating-system/runtime matrix and intentional platform mechanics are specified in [`cross-platform-support.md`](cross-platform-support.md).

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
| List | Report two ordered ownership groups: recognized isolated SDKs under the isolated root first, then read-only SDKs returned by the normally resolved `dotnet --list-sdks` host. Preserve same-version overlap across groups and report `None` for each empty group. |
| Existing SDK detection | Distinguish SDKs already available from the system `dotnet` host from SDKs already present under the isolated root. An unavailable normal host is an empty system inventory; a resolved host whose `--list-sdks` command fails is an operational failure. |
| Explicit List plus Version | Reject the version instead of silently ignoring it. |
| Verify with an exact version | Run a direct-command-only, read-only health check against that version directory under the isolated SDK root. Require the platform host to be present/runnable, require `--list-sdks` to succeed, and require the host to report the requested exact SDK version. |
| Unhealthy Verify result | Return nonzero with repository-owned context for not-installed, missing/non-runnable host, native host failure, or exact-version mismatch. Verification never repairs or mutates the installation. |
| Remove without a version | Present the installed isolated SDK picker. Explicit cancellation or an empty installed set is a normal no-change result. |
| Remove with a version | Target only that version's directory under the isolated SDK root. |
| Removal confirmation | Default to no unless approval is explicitly supplied through the shell's supported mechanism. |
| Build-server shutdown | Must succeed before deletion. Failure identifies the selected SDK and native exit code where available, blocks deletion, and suppresses removal success. |
| Release-metadata / payload / extraction / verification / promotion failure | Return nonzero and do not report install success. |
| Operational failure | Return a nonzero status. Exact numeric status need not be identical across runtimes unless a narrower contract specifies it. |
| Diagnostics | Identify the failed product operation. Runtime-specific command/exception detail may be appended when useful. |

## Transactional installation baseline

Issue #18 established the installation ownership and recovery baseline for both shells. Behavioral parity work must preserve these rules:

- each new install uses operation-owned Microsoft release metadata and SDK payload archive state;
- installation occurs in an operation-owned staging directory rather than directly in the final version directory;
- the downloaded SDK archive must match its Microsoft-published SHA-512 before extraction;
- the staged host must exist, execute successfully, and report the requested exact SDK before promotion;
- a pre-existing final destination is never replaced or adopted accidentally;
- a final destination that appears before promotion blocks promotion and is preserved;
- clean-start failures do not leave a new final destination;
- operation-owned metadata, payload-archive, and staging state is cleaned after success or failure when cleanup is possible;
- cleanup failure is reported and does not mask the primary failure;
- a failed clean-start attempt can be retried deterministically.

Release metadata, downloaded payload archives, and staging directories are transaction-scoped artifacts rather than persistent product state.

## Interactive and automation behavior

Invocation mode is determined from the caller's arguments, not from later menu choices.

When no action or exact version is supplied, the tool enters a persistent interactive session. The session shows Main, performs one selected operation, and returns to Main after a normal completion or a normal cancellation/no-change outcome. `E`/`e` is the global Exit command from Main and persistent selection menus. The session remains active until the user selects Exit or an operational failure terminates the process.

When the caller supplies an explicit action, or supplies an exact version through the supported bare-version convenience form, the tool remains one-shot. It performs that requested operation once and exits after success, cancellation/no-change, or failure. Explicit invocation never enters the persistent Main loop after the operation.

Interactive navigation is deliberately limited:

- Main and each persistent selection menu provide `E. Exit`;
- Install channel selection provides Back to Main;
- Install SDK version selection provides Back to channel selection;
- Remove SDK selection provides Back to Main;
- persistent selection menus do not expose redundant `Q. Cancel` actions when Back already provides the relevant workflow navigation;
- explicit one-shot interactive selection may retain `Q. Cancel` as a successful no-change outcome.

Back is a selection-menu concept only. Ordinary yes/no install and removal confirmations retain their existing default-no cancellation behavior and do not become navigation menus. In a persistent interactive session, declining such a confirmation is a successful no-change result and returns to Main.

Operational failures are never converted into navigation results. Metadata, filesystem, payload acquisition/checksum/extraction, native-command, cleanup, verification, and other correctness-significant failures terminate nonzero immediately; a failed operation must not return to Main where a later successful Exit could mask the failure.

Automation should provide both the action and exact version when a version is required. `Verify <exact-version>` / `verify <exact-version>` is always one-shot and never enters the persistent Main menu. `-Yes` and `--yes` are confirmation controls, not selection controls.

For example, `Install <exact-version> -Yes` / `install <exact-version> --yes` can run without the normally-installed-SDK confirmation. `Install -Yes` / `install --yes` still needs interactive selection because no version has been resolved. If that input cannot be obtained, the command fails rather than guessing or silently cancelling.

An explicit user decision to cancel is different from input failure. A blank/no answer at a default-no confirmation remains a successful no-change outcome. `q`/`Q` remains a documented cancellation command only for explicit one-shot selection; persistent navigation uses `E`/`e` to exit and `B`/`b` to go back.

### SDK version picker

For a selected channel, the default SDK picker prioritizes likely choices without removing exact-version access:

- when Microsoft release-index metadata supplies a `latest-sdk` value that is present in the selected channel data, that SDK is displayed first and marked `latest`;
- the default list also contains the newest SDK from every other available feature band;
- older servicing releases are hidden behind `Show all versions`;
- the expanded list contains every discovered SDK version in deterministic newest-first order;
- Back remains available from both compact and expanded version views;
- manual exact-version entry remains available and explicit exact-version command invocation continues to bypass release-metadata discovery.

Feature-band grouping is derived from SDK version data rather than menu positions. Preview and release-candidate labels are part of deterministic version ordering; fixed numeric menu positions are not a product contract. `latest-sdk` remains optional display metadata: its absence does not invalidate an otherwise usable channel and does not cause the tool to invent an authoritative `latest` marker.

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
- general CLI/help redesign, formatting cleanup, and source-structure normalization are not parity requirements.

## Regression protection

The repository's Pester and Bats suites protect the focused shared behaviors, while the existing transactional-install suites protect the Issue #18 baseline. See [testing.md](testing.md) for the repository-owned validation commands and CI matrix, [cross-platform-support.md](cross-platform-support.md) for supported platform/runtime mechanics, and [native-command-failures.md](native-command-failures.md) for correctness-significant native command boundaries.
