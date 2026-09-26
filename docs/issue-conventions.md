# Issue and pull request conventions

This document defines the repository conventions for structuring implementation issues, recording issue evidence, and describing pull requests.

The execution lifecycle is defined in [`issue-workflow.md`](issue-workflow.md).

## Terminology

- A **Task** is a meaningful implementation deliverable within an issue. Tasks should be scoped so they can be implemented, validated, committed, and reported independently where practical.
- A GitHub **Milestone** is a release or planning grouping. Do not use milestone as a synonym for a Task.
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

## Issue comment headings

Use Markdown level-2 headings (`##`) as the first line of substantive issue comments so the history is easy to scan.

Use these default patterns:

1. `## Kickoff — requirements review`
2. `## Implementation plan — planned tasks`
3. `## Task N complete — <concise task/capability>`
4. `## Task N supplemental — <finding>` when new evidence extends an existing Task record.
5. `## Task N remediation complete — <finding>` when a Task required correction after new evidence.
6. `## Draft PR opened` when recording the PR link/head and Draft status adds useful traceability.
7. `## Manual validation — <behavior>` only when manual validation is genuinely required.
8. `## Full review — implementation complete` for the comprehensive branch/diff review after implementation and validation are complete.
9. `## Final review — completion evidence` for the final exact-head CI/review/follow-up summary before the user decides readiness or merge.
10. `## Post-merge verification` for final closure evidence after merge.

Keep text after the em dash concise and specific. Exceptional comments may use the same grammar with a precise qualifier. The heading should identify the lifecycle event and, for Task comments, the relevant Task.

## Issue comment content

Use comments sparingly and intentionally. The expected sequence is:

1. **Requirements review / kickoff** — understanding, assumptions, ambiguities, and confirmed scope.
2. **Implementation plan** — planned Tasks, likely commit boundaries, scope, validation approach, and initial test-list behaviors for behavioral work.
3. **Task completion** — one comment for each meaningful Task completed, including commit(s), changes, TDD evidence where applicable, validation, and follow-up findings.
4. **Supplemental/remediation evidence** — only when new findings materially change or extend a Task record.
5. **Manual evidence** — only when automation cannot reliably establish the behavior.
6. **Full review** — comprehensive diff review result after implementation and validation are complete.
7. **Final completion evidence** — exact reviewed head, CI evidence, final review result, and intentional follow-ups.
8. **Post-merge verification** — merge, issue closure, branch deletion, `main` validation, and roadmap status.

Do not add generic comments for every tool call, commit, or routine status change.

## Pull request description

A useful PR description normally includes:

- summary and linked issue;
- behavioral or technical contract being implemented;
- test-list and RED → GREEN → REFACTOR evidence when applicable;
- implementation summary;
- validation evidence;
- manual validation evidence when applicable;
- final review status;
- focused review areas.

The PR should be understandable from repository artifacts without requiring external conversation context.
