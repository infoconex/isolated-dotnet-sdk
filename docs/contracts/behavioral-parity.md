# PowerShell and Bash behavioral parity

The PowerShell and Bash implementations target the same product-level behavior where the contract is shared. Parity is judged at observable boundaries such as action selection, exact-version handling, confirmation, failure propagation, installation ownership, cleanup, and exit status. It does not require source-code structure, shell idioms, presentation streams, or platform mechanics to be identical.

The supported operating-system/runtime matrix and intentional platform mechanics are specified in [Cross-platform support](../concepts/cross-platform-support.md).

## Shared contract

| Behavior | Shared contract |
| --- | --- |
| Bare exact version | Treat it as an Install request. |
| Explicit Install with a version | Bypass Microsoft release-index/channel discovery and install that exact version. The exact-version artifact metadata required for payload acquisition and SHA-512 verification is still retrieved. |
| Install without a version | Use the interactive release/channel/version picker. Explicit picker cancellation is a successful no-change result. |
| Existing matching isolated SDK | Report it as already installed and return success without downloading or reinstalling. |
| Pre-existing non-valid destination | Fail closed and preserve the destination. |
| Normally installed matching SDK | Ask before creating an isolated copy unless the shell's explicit confirmation-bypass option is supplied. |
| `-Yes` / `--yes` | Bypass supported confirmation prompts only. It does not invent a version or bypass an unresolved selection prompt. |
| Required interactive input unavailable | Fail nonzero with repository-owned `Interactive input is unavailable.` context rather than looping or treating EOF as cancellation. |
| Persistent Main menu | Use case-insensitive `I` / `R` / `L` / `V` / `A` / `E` for Install / Remove / List / Verify / Audit / Exit. Old numeric Main aliases are rejected rather than retained as hidden aliases. |
| Explicit interactive no/blank/q cancellation | Return success with no state change where that response is part of the prompt's normal cancellation contract. |
| List | Report two ordered ownership groups: recognized isolated SDKs under the isolated root first, then read-only SDKs returned by the normally resolved `dotnet --list-sdks` host. Sort each ownership group by SDK version newest to oldest, include each SDK's concrete version directory, preserve same-version overlap across groups, and report `None` for each empty group. |
| Existing SDK detection | Distinguish SDKs already available from the system `dotnet` host from SDKs already present under the isolated root. An unavailable normal host is an empty system inventory; a resolved host whose `--list-sdks` command fails is an operational failure. |
| Explicit List plus Version | Reject the version instead of silently ignoring it. |
| Audit | Perform an online, read-only assessment of both ownership groups against current Microsoft release metadata. Sort each group newest to oldest and preserve duplicate versions across Isolated and System groups; report LTS/STS, lifecycle status, exact installed-SDK release date when published, authoritative future Go-Live date when available, end-of-support date, and an optional compact `Update -> <version>` tail without mutating either inventory or labeling an installed SDK `Vulnerable`. |
| Audit metadata failure | Fail nonzero when required release-index or known-channel metadata is unavailable or structurally unusable rather than emitting fabricated results. The official `dotnet/core` release-notes table is an optional fallback only for a missing future Go-Live date; fallback failure omits that date without fabricating one. Unknown installed channels remain explicit per-SDK results. |
| Explicit Audit plus Version | Reject the version instead of silently ignoring it. |
| Explicit Verify with an exact version | Run a one-shot, read-only health check against that version directory under the isolated SDK root. Require the platform host to be present/runnable, require `--list-sdks` to succeed, and require the host to report the requested exact SDK version. |
| Interactive Verify | From Main, list only recognized isolated SDKs, select one exact version, and run the same read-only health check as explicit Verify. System SDKs are not targets. Back or an empty isolated inventory is a normal no-change outcome that returns to Main. |
| Unhealthy Verify result | Return nonzero with repository-owned context for not-installed, missing/non-runnable host, native host failure, or exact-version mismatch. Verification never repairs or mutates the installation. In a persistent session, the failure terminates the process rather than returning to Main. |
| Remove without a version | Present the installed isolated SDK picker. Explicit cancellation or an empty installed set is a normal no-change result. |
| Remove with a version | Target only that version's directory under the isolated SDK root. |
| Removal confirmation | Default to no unless approval is explicitly supplied through the shell's supported mechanism. |
| Build-server shutdown | Must succeed before deletion. Failure identifies the selected SDK and native exit code where available, blocks deletion, and suppresses removal success. |
| Release-metadata / payload / extraction / verification / promotion failure | Return nonzero and do not report install success. |
| Operational failure | Return a nonzero status. Exact numeric status need not be identical across runtimes unless a narrower contract specifies it. |
| Diagnostics | Identify the failed product operation. Runtime-specific command/exception detail may be appended when useful. |

## Transactional installation baseline

The transactional installation contract defines the installation ownership and recovery baseline for both shells. Behavioral parity work must preserve these rules:

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

When no action or exact version is supplied, the tool enters a persistent interactive session. The session shows Main and performs selected operations within a menu hierarchy. When both input and output are attached to an interactive terminal, a normal completed or cancellation/no-change result remains visible at a contextual `Press Enter to return to <parent>...` prompt and returns to its immediate parent only after Enter acknowledgement. List and Audit return to Main; Verify and Remove return to their SDK lists; Install returns to the selected channel's SDK list. Redirected input, redirected/captured output, pipes, CI, and automation skip the pause but follow the same parent navigation. `E`/`e` is the global Exit command from Main and persistent selection menus. Back and Exit navigation do not gain a completed-result acknowledgement step. The session remains active until the user selects Exit or an operational failure terminates the process.

When the caller supplies an explicit action, or supplies an exact version through the supported bare-version convenience form, the tool remains one-shot. It performs that requested operation once and exits after success, cancellation/no-change, or failure. Explicit invocation never enters the persistent Main loop after the operation.

Interactive navigation is deliberately limited:

- Main provides mnemonic `I. Install`, `R. Remove`, `L. List`, `V. Verify`, `A. Audit`, and `E. Exit` commands;
- each persistent selection menu also provides `E. Exit`;
- Install channel selection provides Back to Main;
- Install SDK version selection provides Back to channel selection;
- Remove SDK selection provides Back to Main;
- Verify SDK selection provides Back to Main and contains isolated SDKs only;
- persistent selection menus do not expose redundant `Q. Cancel` actions when Back already provides the relevant workflow navigation;
- explicit one-shot interactive selection may retain `Q. Cancel` as a successful no-change outcome.

Back is a selection-menu concept only. Ordinary yes/no install and removal confirmations retain their existing default-no cancellation behavior and do not become navigation menus. In a persistent interactive session, declining such a confirmation is a successful no-change result that waits for Enter acknowledgement before returning to the operation's immediate parent screen.

Operational failures are never converted into navigation results. Metadata, filesystem, payload acquisition/checksum/extraction, native-command, cleanup, verification, and other correctness-significant failures terminate nonzero immediately; a failed operation must not return to Main where a later successful Exit could mask the failure.

Automation should provide both the action and exact version when a version is required. Explicit `Verify <exact-version>` / `verify <exact-version>` remains one-shot and never enters the persistent Main loop. `-Yes` and `--yes` are confirmation controls, not selection controls.

For example, `Install <exact-version> -Yes` / `install <exact-version> --yes` can run without the normally-installed-SDK confirmation. `Install -Yes` / `install --yes` still needs interactive selection because no version has been resolved. If that input cannot be obtained, the command fails rather than guessing or silently cancelling.

An explicit user decision to cancel is different from input failure. A blank/no answer at a default-no confirmation remains a successful no-change outcome. `q`/`Q` remains a documented cancellation command only for explicit one-shot selection; persistent navigation uses `E`/`e` to exit and `B`/`b` to go back.

### SDK version picker

For a selected channel, the Install picker has two version views:

- **Currently prerelease channels** initially show **all** discovered SDK versions in deterministic SDK-aware newest-first order, including distinct Preview and RC milestones within the same feature band.
- **Stable channels** initially show the featured view: Microsoft's `latest-sdk` (when it identifies an SDK in that channel's releases), then the newest SDK from each other available feature band. Older servicing releases remain accessible.
- The picker offers `S. Show featured versions` from the complete view or `S. Show all versions` from the featured view **only if the two lists differ**. A channel with one SDK does not show `S`.

Classify the **selected channel's current SDK**, not its historical release list: prefer the release-index `latest-sdk` when it is present in the discovered channel SDK versions; otherwise use the SDK-aware newest discovered version as the deterministic fallback. A `-preview.N` or `-rc.N` suffix identifies a currently prerelease SDK. Do not use a hard-coded channel number, or classify a stable channel as prerelease because it contains older previews or an inconsistent support-phase label. An absent or nonmatching `latest-sdk` does not create a fabricated `latest` marker.

Both views preserve the existing `latest`, `system`, and `isolated` markers; Back, Exit, and manual exact-version entry; and numbered selection of any displayed version. The complete view reuses SDK-aware newest-first ordering. Feature-band grouping and Preview/RC ordering are derived from SDK version data, not fixed menu positions. Explicit exact-version command invocation continues to bypass release-index/channel discovery while retaining the exact-version artifact metadata lookup needed for installation. These picker rules apply in persistent interactive and one-shot Install picker contexts.

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

This parity contract deliberately does not absorb broader failure/boundary coverage consolidation or the stable-release bootstrap, development-source-selection, and self-update policy. Those remain separate repository contracts; stable release behavior is documented in [Stable bootstrap, update, and rollback](../releases/stable-bootstrap.md). General CLI/help redesign, formatting cleanup, and source-structure normalization are also not parity requirements.

## Regression protection

The repository's Pester and Bats suites protect the focused shared behaviors, while the existing transactional-install suites protect the transactional installation baseline above. See [Testing](../maintainers/testing/testing.md) for repository-owned validation commands and CI matrix, [Cross-platform support](../concepts/cross-platform-support.md) for supported platform/runtime mechanics, and [Native command failure boundaries](native-command-failures.md) for correctness-significant native command boundaries.
