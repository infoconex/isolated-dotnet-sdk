# Repository agent instructions

These instructions apply to AI/code agents working in this repository.

## Before issue work

1. Read [`docs/maintainers/development/operating-model.md`](docs/maintainers/development/operating-model.md) and [`docs/maintainers/issues/issue-workflow.md`](docs/maintainers/issues/issue-workflow.md). Together they define the durable development principles and authoritative issue lifecycle.
2. Read the exact current GitHub issue, including comments, dependencies, acceptance criteria, and non-goals.
3. Inspect the active release integration branch when one exists, the released `main` line, relevant source/tests/docs, and latest repository validation. Review the current roadmap/tracker when one applies.

Repository documentation and the current issue define the working contract. Resolve contradictions between current repository artifacts before implementation. Prefer live repository state over historical conversation context.

## Decision authority

Proceed autonomously on routine implementation choices governed by established repository contracts. Stop for owner direction before removing/deprecating capabilities, materially changing user-visible workflows, changing architecture or compatibility commitments, changing release/versioning policy, weakening safety/integrity guarantees, or resolving meaningful product/UX ambiguity.

## Non-negotiable guardrails

- Work one implementation issue at a time.
- Before proposing or creating a new GitHub issue from a review, retrospective, implementation finding, adjacent-impact finding, validation finding, or other repository work, inspect the current `.github/ISSUE_TEMPLATE/implementation.md` and `docs/maintainers/issues/issue-conventions.md`. Present the proposed issue to the owner and obtain explicit approval before creating it. Investigation, analysis, prioritization, and recommendation remain autonomous.
- When an active next-release integration branch exists, branch from it and target it unless the issue is explicitly a released-line hotfix or other approved exception.
- Do not mark a Draft PR ready for review unless the user explicitly directs it.
- The user's Ready-for-Review approval also authorizes merge of that reviewed state after final verification; do not request a separate merge approval unless the reviewed state materially changes, validation regresses, or a new blocking finding appears.
- After fully closing out an issue, stop and let the user decide when to begin the next one.

Follow all detailed process requirements in `docs/maintainers/issues/issue-workflow.md`; they are intentionally not duplicated here.
