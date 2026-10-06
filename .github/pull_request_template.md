<!--
Keep this description concise and evidence-focused.
Authoritative guidance:
- docs/maintainers/development/operating-model.md
- docs/maintainers/issues/issue-workflow.md
- docs/maintainers/issues/issue-conventions.md
Open this Draft PR only after implementation is believed complete, appropriate targeted pre-PR validation is green, the linked issue is reconciled, and the full branch diff against the intended integration target has been reviewed with no known blocking findings.
A full branch Validate run is optional when it serves a distinct purpose; the normal authoritative full pre-merge signal is Validate on the exact PR head.
Before opening the Draft PR, reconcile the linked issue so completed Tasks are checked and acceptance criteria already established by durable evidence are checked; leave only criteria that genuinely depend on exact-head PR validation or merge open.
The Draft PR is for final exact-head CI/verification and the explicit Ready-for-Review decision. Ready-for-Review approval also authorizes merge of that reviewed state after final verification; seek renewed approval only if the reviewed state materially changes, validation regresses, or a new blocking finding appears.
For a PR targeting main, use Closes #<issue> when auto-close is intended. For a PR targeting a non-default release integration branch, use Refs #<issue> and close the issue explicitly only after successful post-merge integration verification.
Lifecycle evidence such as Kickoff, consolidated Task reconciliation (or useful incremental Task checkpoints), Full review, Draft PR opening, Final review, and Post-merge verification belongs in the linked issue history.
-->

Refs #

## Base / integration target

<!-- Name the intended PR base, for example release/0.4 or main. -->

-

## Contract / scope

<!-- What contract or scoped change does this PR implement? Include important non-goals when useful. -->

-

## Implementation summary

-

## TDD / mechanical-change exception

<!-- For behavioral work, summarize meaningful RED → GREEN → REFACTOR evidence. For documentation/mechanical work, state why the TDD exception applies. -->

-

## Validation evidence

<!-- Report targeted pre-PR evidence, any justified manual full branch validation, and authoritative exact-head PR CI as it becomes available. Do not assign mechanically verifiable checks to the reviewer. -->

-

## Manual validation / user judgment

<!-- Include only validation that cannot reasonably be automated or decisions requiring policy/product/UX/architecture/risk judgment. Write "None" when not applicable. -->

-

## Review status

<!-- Confirm the pre-PR full diff and adjacent-impact review completed with no known blocking findings, then summarize any findings from final PR-level verification. Ready-for-Review approval is the owner merge authorization for the reviewed state unless material changes or new blocking evidence require renewed approval. -->

-

## Focused review areas

-
