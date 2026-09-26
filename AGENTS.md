# Repository agent instructions

These instructions apply to AI/code agents working in this repository.

## Mandatory first reads

Before starting issue work:

1. Read [`docs/issue-workflow.md`](docs/issue-workflow.md) and follow it as the authoritative issue lifecycle.
2. Read the exact current GitHub issue, including comments, dependencies, acceptance criteria, and non-goals.
3. Review the current roadmap/tracker when one applies. For the current v0.2.0 hardening cycle, see GitHub issue #29.
4. Inspect current `main`, relevant source/tests/docs, and latest repository validation before making changes.

Do not rely on chat history when repository artifacts provide the current contract.

## Required working behavior

- Work one implementation issue at a time.
- Review and clarify requirements before implementation.
- Add the required focused issue comments described in `docs/issue-workflow.md`; avoid generic operational chatter.
- Use a focused short-lived branch and Draft PR.
- Use specification-driven development and disciplined TDD for behavioral changes: maintain a test list, take one smallest behavior at a time through RED → GREEN → REFACTOR, and update the list as new cases are discovered.
- Do not manufacture RED evidence for documentation/mechanical-only work.
- Use small scoped Conventional Commits.
- Do not mix unrelated cleanup into the active issue; create a follow-up issue instead.
- Use **Task** for a meaningful implementation deliverable within an issue. Complete, validate, commit, and record focused evidence for each Task independently where practical. Reserve GitHub **Milestones** for release/planning groupings.
- Treat green CI as evidence, not a substitute for final diff review.
- Prefer automated validation; require manual validation only when automation cannot establish the behavior reliably.
- Do not mark a Draft PR ready for review unless the user explicitly directs it.
- Do not merge without explicit user approval.
- Prefer squash merge unless the repository/issue requires otherwise.
- Perform the complete post-merge verification defined in `docs/issue-workflow.md`.
- After closing out an issue, stop and let the user decide when to begin the next one.

## Repository engineering principles

Favor simple, deterministic, cross-platform behavior; explicit contracts; repository-owned validation; analyzer-clean implementations; and proportional architecture.

Do not introduce speculative abstractions, unnecessary services/configuration layers, or standards suppressions merely to make validation green.

When repository documentation, issue requirements, and chat context disagree, verify current repository state and resolve the discrepancy before implementation.
