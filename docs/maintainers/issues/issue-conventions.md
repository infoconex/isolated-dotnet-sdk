# Issue and pull request conventions

This document defines the repository conventions for structuring implementation issues, recording issue evidence, and describing pull requests.

The execution lifecycle is defined in [`issue-workflow.md`](issue-workflow.md). Durable development principles and decision authority are defined in the [development operating model](../development/operating-model.md).

## Terminology

- A **Task** is a meaningful implementation deliverable within an issue. Tasks should be scoped so they can be implemented, validated, committed, and reported independently where practical, but routine coherent work does not require a separate issue comment for every Task.
- A GitHub **Milestone** is a release or planning grouping. Do not use milestone as a synonym for a Task.
- The **integration target** is the branch an issue is intended to merge into. During an active next-release cycle this is normally the release integration branch, such as `release/0.4`; otherwise it may be `main`.
- Use **defect** rather than bug in repository discussions.

## Issue structure

Use this default shape for implementation issues, adapting sections when they genuinely do not apply:

1. **Summary** — concise statement of the change and important scope boundary.
2. **Problem** — why the current state is insufficient and why the work matters.
3. **Desired changes** — intended technical or behavioral contract, grouped by capability where useful.
4. **Tasks** — numbered implementation deliverables (`Task 1`, `Task 2`, ...), each with focused sub-items.
5. **Acceptance criteria** — observable completion requirements, including validation and merge-through-PR criteria where applicable.
6. **Non-goals** — explicit boundaries that prevent adjacent or incidental work from entering scope.
7. **Development guidance** — implementation principles or constraints that preserve the intended contract without over-prescribing the solution.

Add sections such as baseline behavior, behavioral scenarios, sequencing/dependencies, repository specification, or traceability when they materially improve the issue.

Issue #9 is a useful example of this structure.

## Issue creation and owner approval

Discovery and backlog creation are separate decisions.

Maintainers and agents may investigate, analyze, prioritize, and recommend findings autonomously when repository contracts make that work appropriate. A discovered finding must not be turned into a new GitHub issue until the owner explicitly approves adding it to the repository backlog.

Before drafting a proposed issue:

1. read the current `.github/ISSUE_TEMPLATE/implementation.md` and this conventions document rather than relying on a remembered issue shape;
2. determine whether the finding materially warrants a separate issue;
3. draft the proposal using the current template structure, adapting or removing sections only when they genuinely do not apply; and
4. present the proposed title, rationale, scope, non-goals, and meaningful dependency/sequencing implications to the owner.

Create the issue only after explicit owner approval.

The resulting issue should be independently understandable and executable from repository artifacts without requiring a tracker or historical chat context for its contract. Record genuine dependencies and sequencing relationships when they matter; issue independence does not require removing legitimate relationships between work items.

## User-facing documentation references

User-facing product documentation must describe current behavior, guarantees, policies, and capabilities directly. Do not use GitHub issue numbers, pull request numbers, or implementation-history identifiers as product terminology or as context a user must understand to follow the documentation.

Issue and pull-request references remain appropriate when repository history is itself the subject, including contributor workflow, release notes or changelogs, implementation evidence, and explicit traceability records. In product documentation, prefer stable product concepts and repository-relative documentation links over references to the work item that originally introduced a behavior.

## Issue checkbox state

Task and acceptance-criteria checkboxes are live lifecycle state, not static planning text.

- Keep Task numbering stable across the issue body, implementation plan, and evidence so `Task N` always identifies the same deliverable.
- For routine coherent work, completed Tasks and already-established acceptance criteria may be reconciled together at the next meaningful lifecycle boundary rather than mutated after every small step. They must be synchronized no later than before Draft PR creation.
- For long-running, risky, interrupted, independently reviewable, or multi-contributor work, update a Task checkbox and add `## Task N complete — <concise task/capability>` as soon as that checkpoint is complete when the incremental record adds value.
- Check acceptance criteria as soon as the chosen lifecycle reconciliation establishes them. Leave a criterion unchecked only when its requirement genuinely depends on a later lifecycle event such as exact-head PR validation or merge.
- Reconcile Task and acceptance-criteria checkbox state at the lifecycle gates defined in [`issue-workflow.md`](issue-workflow.md), including before Draft PR creation, after exact-head validation, and after merge to the integration target.

A completed Task or satisfied acceptance criterion left unchecked at a lifecycle gate is stale issue state and should be corrected before proceeding.

## Issue comment headings

Use Markdown level-2 headings (`##`) as the first line of substantive issue comments so the history is easy to scan.

Use these default patterns when the corresponding evidence is useful:

1. `## Kickoff — requirements review`
2. `## Implementation plan — planned tasks`
3. `## Task reconciliation — implementation complete` for the normal consolidated completion record on coherent work.
4. `## Task N complete — <concise task/capability>` when incremental Task-level checkpoints add value.
5. `## Task N supplemental — <finding>` when new evidence extends an existing Task record.
6. `## Task N remediation complete — <finding>` when a Task required correction after new evidence.
7. `## Manual validation — <behavior>` only when manual validation is genuinely required.
8. `## Full review — implementation complete` for a distinct comprehensive branch/diff review record when it is not already clear in the consolidated reconciliation.
9. `## Draft PR opened` after the implementation/targeted-validation/full-review quality threshold is met, when recording the PR link, reviewed head, base branch, and Draft status adds useful traceability.
10. `## Final review — completion evidence` for the final exact-head PR CI/review/follow-up summary before the user decides Ready for Review; that approval also authorizes merge of the reviewed state.
11. `## Post-merge verification` for final closure evidence after merge to the issue's integration target.

Keep text after the em dash concise and specific. Exceptional comments may use the same grammar with a precise qualifier. The heading should identify the lifecycle event and, for Task comments, the relevant Task.

## Issue comment content

Use comments sparingly and intentionally. The normal concise sequence is:

1. **Requirements review / kickoff** — understanding, assumptions, ambiguities, and confirmed scope.
2. **Implementation plan** — planned Tasks, likely commit boundaries, scope, validation approach, and initial test-list behaviors for behavioral work.
3. **Consolidated implementation reconciliation** — for coherent work, one deliberate record mapping completed Tasks to commits/changes/tests/validation and synchronizing Task/acceptance checkbox state before the Draft PR.
4. **Incremental Task evidence** — optional checkpoints for long-running, risky, interrupted, independently reviewable, or multi-contributor work; use supplemental/remediation comments only when new findings materially change the record.
5. **Manual evidence** — only when automation cannot reliably establish the behavior.
6. **Full review** — record separately when useful; otherwise it may be summarized in the consolidated implementation evidence if the comprehensive review result remains explicit.
7. **Draft PR opening** — only after implementation, appropriate targeted pre-PR validation, full diff review, and linked-issue state reconciliation are complete with no known blocking findings.
8. **Final completion evidence** — exact reviewed PR head, authoritative full PR Validate evidence, final review result, reconciled acceptance criteria, and intentional follow-ups.
9. **Post-merge verification** — merge, explicit issue closure when required, branch deletion, integration-target validation, tracker status, and final issue checkbox reconciliation.

Do not add generic comments for every tool call, commit, routine status change, or small Task when a consolidated lifecycle-boundary record carries the same evidence more clearly.

## Pull request issue references

GitHub closing keywords such as `Closes #123` are interpreted for pull requests that target the repository's default branch. They do not provide the intended issue-link/auto-close behavior when a pull request targets a non-default integration branch.

Use:

- `Closes #<issue>` when the pull request targets `main` and the issue should close automatically when that PR merges;
- `Refs #<issue>` for a pull request targeting a non-default release integration branch, then explicitly close the issue only after merge and successful post-merge integration verification.

The explicit close for an integration-branch issue is part of lifecycle reconciliation, not an exception to traceability.

## Pull request description

A useful PR description normally includes:

- summary and linked/referenced issue;
- intended base/integration target;
- behavioral or technical contract being implemented;
- test-list and RED → GREEN → REFACTOR evidence when applicable;
- implementation summary;
- targeted pre-PR validation plus authoritative exact-head PR validation evidence as it becomes available;
- manual validation evidence when applicable;
- final review status;
- focused review areas.

The PR should be understandable from repository artifacts without requiring external conversation context.
