# Issue execution workflow

This document is the authoritative repository process for taking an implementation issue from selection through post-merge verification.

The goal is repeatable, evidence-driven delivery with clear traceability. Do not rely on chat history to reconstruct this process.

## Core rules

- Work one implementation issue at a time unless an issue explicitly permits independent parallel work.
- Treat the GitHub issue as the traceability and evidence hub.
- GitHub issues in this repository use **open/closed** state only. Do not invent or simulate an "in progress" issue state; active work is represented by the branch, Draft PR, and focused issue comments.
- Keep requirements, implementation, tests, documentation, and evidence aligned.
- Prefer automation and deterministic evidence over manual checks.
- Green CI is necessary evidence, not proof by itself that a change is correct.
- Do not include unrelated cleanup. Capture material unrelated work as a follow-up issue.
- Use **Task** for a meaningful implementation deliverable inside an issue. Tasks are the units we plan, implement, validate, commit, and report independently where practical.
- Reserve GitHub **Milestones** for release/planning groupings such as `v0.2.0 - Quality & Hardening`.
- Use the term **defect** rather than bug in repository discussions.

## 1. Select and verify the issue

Before making changes:

1. Read `AGENTS.md` and this document.
2. Review the current roadmap/tracker and verify the selected issue's dependencies are complete or intentionally revised.
3. Inspect current `main` and confirm the latest repository validation state.
4. Fetch and read the exact current issue body, comments, acceptance criteria, dependencies, and non-goals.
5. Inspect the relevant source, tests, specifications, and documentation on current `main`.

Do not implement stale assumptions from an earlier chat or summary when the repository or issue now says something different.

## 2. Review requirements before implementation

Before creating repository changes, review the issue as a specification.

Confirm that it defines, as appropriate:

- current/baseline behavior;
- desired externally observable behavior;
- failure and boundary behavior;
- invalid-input behavior;
- unavailable-dependency behavior;
- recovery behavior;
- explicit non-goals;
- acceptance criteria;
- expected automated evidence.

Add a focused kickoff comment to the issue summarizing the requirements review and your understanding of the intended work.

If a material requirement is unclear, contradictory, or missing and the choice could change the public contract, safety, scope, or architecture:

1. comment on the issue with the specific ambiguity;
2. stop implementation;
3. wait for user feedback before proceeding.

Do not stop for trivial implementation choices that can be resolved safely from established repository conventions.

If requirements need refinement, update the issue before implementation so the issue remains authoritative.

## 3. Create the working branch and Draft PR

After requirements are clear:

1. create a focused short-lived branch from current `main`;
2. keep the issue open;
3. create the pull request as **Draft** as soon as there is a useful diff to review;
4. link the PR to the issue, normally with `Closes #<issue>` when appropriate.

The user decides when the Draft PR becomes ready for review. Do not mark it ready automatically.

Do not merge without explicit user approval.

## 4. Comment before implementation

Before making implementation changes, including production, test, CI, configuration, or documentation changes, add an issue comment stating what will be implemented next.

The comment should identify the planned Tasks or capability-level scope and the validation approach. For behavioral work, include the initial test-list behaviors or scenarios that will drive the first TDD cycles. Avoid generic status comments such as "starting work" without meaningful scope.

## 5. Specification-driven and test-driven implementation

### Behavioral changes

Use the repository specification to drive a disciplined TDD cycle. A Task may contain multiple behaviors; the Task is not itself the TDD unit. Take one smallest meaningful behavior at a time through **RED → GREEN → REFACTOR**.

Use this sequence:

1. **Identify the specification and observable outcome.** Confirm the requirement/scenario and the behavior that must be externally observable.
2. **Create or update the test list.** Derive a working list of behaviors and cases that need automated evidence. Include relevant happy-path, boundary, invalid-input, unavailable-dependency, failure, recovery, and cross-platform cases. Keep the list intentionally lightweight and allow it to evolve as implementation reveals new information.
3. **Select the next smallest behavior.** Choose one test-list item that can be implemented and validated independently. Do not implement the entire Task and backfill tests afterward.
4. **RED — write the smallest test that expresses that behavior.** Run it and confirm it fails for the expected reason because the behavior is missing or incorrect.
5. **GREEN — implement the smallest correct production change.** Make only the change needed to satisfy the selected behavior; avoid speculative implementation for later test-list items.
6. **Run the relevant broader tests.** Confirm the new behavior did not regress existing contracts or adjacent behavior.
7. **REFACTOR — improve the design while remaining green.** Refactor production and/or test code to remove duplication, improve names/structure, and simplify the design without changing behavior. Re-run the relevant tests after refactoring.
8. **Update the test list.** Mark the completed behavior, add newly discovered cases when they materially affect the contract, and select the next smallest behavior.
9. **Repeat RED → GREEN → REFACTOR** until the Task's specified behavior and relevant test-list items are complete.
10. **Run final repository validation and review against the specification.** Confirm the completed Task satisfies the issue contract, not merely that the tests happen to pass.

A failing parser, analyzer, dependency install, broken test harness, or unrelated existing failure is not meaningful RED evidence for the product behavior. Fix the harness/environment first and establish a failure that demonstrates the missing behavior.

Do not treat the test list as a fixed up-front implementation specification. It is a working design aid that should evolve as TDD exposes additional behavior, boundaries, and design pressure.

Refactoring is part of TDD, not optional cleanup. Tests are repository assets too; refactor test code when doing so improves clarity or maintainability without hiding the behavioral contract behind unnecessary abstraction.

BDD-style Given/When/Then scenarios are useful for externally observable behavior where they improve clarity. Do not force BDD syntax onto low-level tests.

### Mechanical or documentation-only changes

Do not manufacture a failing test for work where RED provides no meaningful behavioral evidence, such as:

- documentation-only changes;
- dependency pin changes that preserve behavior;
- purely mechanical formatting;
- narrowly scoped non-behavioral refactors.

For these changes, state the TDD exception explicitly in the issue/PR and rely on appropriate static checks, existing tests, diff review, and CI evidence.

## 6. Commit discipline

Use small, scoped commits containing only related changes.

Use Conventional Commits as defined by https://www.conventionalcommits.org/en/v1.0.0/.

Examples:

- `feat(powershell): ...`
- `fix(bash): ...`
- `test(powershell): ...`
- `docs: ...`
- `ci: ...`
- `chore: ...`

Do not bundle incidental cleanup into a commit because a nearby file was already being edited.

If unrelated work is worth doing, create a follow-up issue and leave the current branch focused.

## 7. Task completion

When an issue contains multiple meaningful implementation Tasks:

1. complete one Task;
2. run the relevant validation;
3. commit the scoped change;
4. add a focused issue comment describing what was completed and the evidence;
5. then move to the next Task.

Task comments should be useful traceability, not a running activity log.

A useful completion comment includes items such as:

- Task/capability completed;
- important contract decisions;
- test-list/TDD evidence for behavioral work;
- tests/static analysis run;
- relevant commit or CI evidence;
- newly discovered follow-up issues.

This is the pattern established in recent completed issues: Tasks represent meaningful implementation deliverables within an issue, while GitHub Milestones remain release/planning groupings.

## 8. Validation expectations

Use repository-owned validation whenever possible.

Evidence may include:

- parser/syntax validation;
- static analysis;
- unit/component tests;
- process-level behavioral tests;
- cross-platform CI jobs;
- deterministic version/checksum verification;
- targeted manual validation only when automation cannot establish the behavior.

Do not ask the user to perform mechanical validation that can reasonably be automated.

Manual validation is appropriate when the behavior is genuinely host/UI/interactive dependent and CI cannot reproduce it reliably. Record exactly what was manually verified and the observed result.

## 9. Full review before completion

After implementation and validation are green, perform a full review of the actual diff.

Review for:

- correctness against the issue/specification;
- failure and boundary behavior;
- scope discipline and unrelated changes;
- test quality and meaningful coverage;
- PowerShell/Bash idioms;
- analyzer/static-analysis cleanliness;
- documentation consistency;
- security and supply-chain implications;
- deterministic/reproducible behavior;
- cross-platform implications;
- accidental file deletion or content loss;
- unnecessary abstractions or complexity.

CI being green does not replace this review.

If the review finds gaps:

1. fix them on the same focused branch when they belong to the issue;
2. create a follow-up issue when they are unrelated;
3. rerun validation;
4. repeat the full review.

Do not recommend merge until there are no known blocking findings.

## 10. Final issue and PR evidence

Before the PR is considered complete, ensure the issue/PR contains concise durable evidence, including as applicable:

- requirements/specification links;
- test-list coverage and meaningful RED → GREEN → REFACTOR evidence for behavioral changes;
- implementation summary;
- GREEN/final CI evidence on the exact reviewed head;
- manual validation evidence, if any;
- final review result;
- follow-up issues intentionally deferred.

Avoid duplicating long specifications in comments when a repository document or issue body is already authoritative; link/reference it instead.

## 11. Ready-for-review decision

Keep the PR Draft until implementation, validation, and review confidence are sufficient.

Do **not** mark the PR ready for review on the user's behalf unless the user explicitly asks you to do so.

When the user marks it ready, verify again that:

- the PR is non-draft;
- the head SHA is the expected reviewed commit;
- required CI on that head is green;
- the final diff has no new blocking findings.

## 12. Merge

Do not merge until the user explicitly approves the merge.

Prefer **squash merge** unless the issue/repository explicitly requires another strategy.

When merging, protect against head movement by verifying/using the exact expected reviewed head where tooling supports it.

## 13. Post-merge verification

After merge, do not assume completion from the merge response alone.

Verify:

1. the PR is merged;
2. the related issue is closed/completed as expected;
3. the short-lived branch is deleted;
4. `main` points to the expected merge result;
5. post-merge `main` validation completes successfully;
6. the roadmap/tracker is updated to reflect the completed issue;
7. any acceptance criterion that depends specifically on merge is now satisfied.

If post-merge validation fails, treat that as unfinished work and investigate before moving on.

## 14. Stop at the issue boundary

After an issue is fully closed out, stop.

Do not automatically begin the next roadmap item. Report the completed state and let the user decide when to start the next issue.

## Issue structure reference pattern

Issue #9 established a useful repository pattern for a well-specified implementation issue. Use it as the default shape, adapting sections when they genuinely do not apply:

1. **Summary** — concise statement of the change and important scope boundary.
2. **Problem** — why the current state is insufficient and why the work matters.
3. **Desired changes** — the intended technical/behavioral contract, grouped by capability where useful.
4. **Tasks** — numbered meaningful implementation deliverables (`Task 1`, `Task 2`, ...), each with focused sub-items.
5. **Acceptance criteria** — observable completion requirements, including validation and merge-through-PR criteria where applicable.
6. **Non-goals** — explicit boundaries that prevent incidental cleanup or adjacent behavior from entering scope.
7. **Development guidance** — implementation principles or constraints that help preserve the intended contract without over-prescribing the solution.

Add other sections such as baseline behavior, behavioral scenarios, sequencing/dependencies, repository specification, or traceability when the issue needs them.

Issue #9 is a reference pattern, not a frozen template. Newer repository process rules override historical details when they conflict—for example, the current process opens a Draft PR as soon as there is a useful diff rather than waiting until every Task is complete.

## Issue comment title pattern

Use Markdown level-2 headings (`##`) as the first line of substantive issue comments so the issue history is easy to scan.

Use these default title patterns, modeled on Issue #9:

1. `## Kickoff — requirements review`
2. `## Implementation plan — planned tasks`
3. `## Task N complete — <concise task/capability>`
4. `## Task N supplemental — <finding>` when new evidence belongs to an existing Task without replacing its original completion record.
5. `## Task N remediation complete — <finding>` when a Task required correction after new evidence.
6. `## Full pre-PR review` for the comprehensive branch/diff review before readiness evidence is finalized. Under the current process the Draft PR may already exist; the title remains useful even though Issue #9 originally performed this before opening its Draft PR.
7. `## Draft PR opened` when recording the PR link/head and Draft status is useful traceability.
8. `## Manual validation — <behavior>` only when manual validation is genuinely required.
9. `## Final review — completion evidence` for the final exact-head CI/review/follow-up summary before the user decides readiness/merge.
10. `## Post-merge verification` for the final closure evidence after merge.

Keep the text after the em dash concise and specific. Do not invent a unique heading style for routine comments when one of these patterns applies.

Exceptional comments may use the same grammar with a precise qualifier, as Issue #9 did for supplemental findings and remediation. The title should tell a future reader **what lifecycle event occurred** and, for Task comments, **which Task it belongs to**.

## Issue comment content pattern

Use comments sparingly and intentionally. The expected content sequence is:

1. **Requirements review / kickoff** — understanding, assumptions, ambiguities, and confirmed scope.
2. **Implementation plan** — planned Tasks, likely commit boundaries, scope, validation approach, and initial test-list behaviors for behavioral work.
3. **Task completion** — one comment for each meaningful Task completed, including commit(s), changes, test-list/TDD evidence where applicable, validation, and follow-up findings.
4. **Supplemental/remediation evidence** — only when new findings materially change or extend a Task's completion record.
5. **Manual evidence** — only when manual validation is genuinely required.
6. **Full/final review evidence** — exact reviewed head, CI evidence, scope/review result, and intentional follow-ups.
7. **Post-merge verification** — merge, issue closure, branch deletion, `main` validation, and roadmap status.

Do not add generic comments for every tool call, commit, or routine status change.

## Pull request expectations

A useful PR description normally includes:

- summary and linked issue;
- behavioral/technical contract being implemented;
- test-list and RED → GREEN → REFACTOR evidence when applicable;
- implementation summary;
- validation evidence;
- manual validation evidence when applicable;
- final review status;
- focused review areas.

The PR should remain understandable to a future maintainer without requiring the original chat transcript.
