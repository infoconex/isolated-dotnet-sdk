# Issue execution workflow

This document is the authoritative lifecycle for taking an implementation issue from selection through post-merge verification.

The goal is repeatable, evidence-driven delivery with clear traceability. Issue, comment, Task, and pull request formatting conventions are defined in [`issue-conventions.md`](issue-conventions.md).

## Core rules

- Work one implementation issue at a time unless an issue explicitly permits independent parallel work.
- Treat the GitHub issue as the traceability and evidence hub.
- Keep requirements, implementation, tests, documentation, and evidence aligned.
- Prefer automation and deterministic evidence over manual checks.
- Green CI is necessary evidence, not proof by itself that a change is correct.
- Do not include unrelated cleanup. Capture material unrelated work as a follow-up issue.

## 1. Select and verify the issue

Before making changes:

1. Read `AGENTS.md`, this document, and [`issue-conventions.md`](issue-conventions.md).
2. Review the current roadmap/tracker when one applies and verify the selected issue's dependencies are complete or intentionally revised.
3. Inspect current `main` and confirm the latest repository validation state.
4. Read the exact current issue body, comments, acceptance criteria, dependencies, and non-goals.
5. Inspect relevant source, tests, specifications, and documentation on current `main`.

Repository documentation and the current issue define the working contract. Resolve contradictions between current repository artifacts before implementation.

## 2. Review requirements

Review the issue as a specification before implementation.

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

Add a `## Kickoff — requirements review` comment summarizing the review and intended scope.

If a material requirement is unclear, contradictory, or missing and the choice could change the public contract, safety, scope, or architecture:

1. comment on the issue with the specific ambiguity;
2. stop implementation;
3. wait for user feedback.

Do not stop for routine implementation choices that can be resolved from established repository conventions. Update the issue before implementation when requirements need refinement so it remains authoritative.

## 3. Create the working branch and Draft PR

After requirements are clear:

1. create a focused short-lived branch from current `main`;
2. keep the issue open;
3. create the pull request as **Draft** as soon as there is a useful diff to review;
4. link the PR to the issue, normally with `Closes #<issue>` when appropriate.

The user decides when the Draft PR becomes ready for review. Do not mark it ready automatically.

Do not merge without explicit user approval.

## 4. Record the implementation plan

Before making implementation changes, add `## Implementation plan — planned tasks` to the issue.

Identify the planned Tasks, likely commit boundaries, scope, and validation approach. For behavioral work, include the initial test-list behaviors or scenarios that will drive the first TDD cycles.

Avoid generic status comments without meaningful scope.

## 5. Implement with specification-driven TDD

### Behavioral changes

A Task may contain multiple behaviors; the Task is not itself the TDD unit. Take one smallest meaningful behavior at a time through **RED → GREEN → REFACTOR**.

For each behavior:

1. **Identify the specification and observable outcome.**
2. **Create or update the test list.** Include relevant happy-path, boundary, invalid-input, unavailable-dependency, failure, recovery, and cross-platform cases. Keep the list lightweight and allow it to evolve.
3. **Select the next smallest behavior.** Do not implement an entire Task and backfill tests afterward.
4. **RED — write the smallest test that expresses the behavior.** Run it and confirm it fails for the expected behavioral reason.
5. **GREEN — implement the smallest correct production change** needed to satisfy that behavior.
6. **Run relevant broader tests** to detect regressions in existing contracts or adjacent behavior.
7. **REFACTOR while green.** Improve production and/or test code without changing behavior, then rerun relevant tests.
8. **Update the test list** and select the next behavior.
9. Repeat until the Task's specified behavior and relevant test-list items are complete.

Then run final repository validation and review the completed Task against the specification, not merely against passing tests.

A parser, analyzer, dependency-install, broken-harness, or unrelated existing failure is not meaningful RED evidence. Fix the environment/harness first and establish a failure caused by the missing or incorrect behavior.

The test list is a working design aid, not a fixed up-front test specification. Refactoring is part of TDD, including refactoring test code when it improves clarity without hiding the behavioral contract behind unnecessary abstraction.

BDD-style Given/When/Then scenarios are useful for externally observable behavior where they improve clarity. Do not force BDD syntax onto low-level tests.

### Mechanical or documentation-only changes

Do not manufacture RED evidence when it provides no meaningful behavioral evidence, such as for:

- documentation-only changes;
- dependency pin changes that preserve behavior;
- purely mechanical formatting;
- narrowly scoped non-behavioral refactors.

State the TDD exception explicitly in the issue/PR and rely on appropriate static checks, existing tests, diff review, and CI evidence.

## 6. Commit discipline

Use small, scoped Conventional Commits containing only related changes. Follow <https://www.conventionalcommits.org/en/v1.0.0/>.

Do not bundle incidental cleanup into the active issue. Create a follow-up issue for unrelated work.

## 7. Complete each Task

Follow the Task definition and comment conventions in [`issue-conventions.md`](issue-conventions.md).

For each Task:

1. complete the scoped implementation;
2. run relevant validation;
3. commit the scoped change;
4. add `## Task N complete — <concise task/capability>` with durable evidence;
5. then move to the next Task.

Task evidence should include material contract decisions, TDD evidence for behavioral work, validation performed, relevant commit/CI evidence, and follow-up findings when applicable. Use supplemental or remediation comments only when new evidence materially changes or extends the Task record.

## 8. Validate

Use repository-owned validation whenever possible. Evidence may include:

- parser/syntax validation;
- static analysis;
- automated behavioral tests;
- cross-platform CI jobs;
- deterministic version/checksum verification;
- targeted manual validation only when automation cannot establish the behavior reliably.

Do not ask the user to perform mechanical validation that can reasonably be automated. When manual validation is required, record exactly what was verified and the observed result.

## 9. Perform the full review

After implementation and validation are green, review the actual diff for:

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

1. fix in-scope findings on the same branch;
2. create follow-up issues for unrelated findings;
3. rerun validation;
4. repeat the full review.

Do not recommend merge while blocking findings remain.

Record the completed comprehensive review under `## Full review — implementation complete`.

## 10. Record final evidence

Before the PR is considered complete, record concise durable evidence, including as applicable:

- requirements/specification references;
- test-list and RED → GREEN → REFACTOR evidence for behavioral changes;
- implementation summary;
- final CI evidence on the exact reviewed head;
- manual validation evidence;
- final review result;
- intentionally deferred follow-up issues.

Use `## Final review — completion evidence` for the final exact-head summary. Avoid duplicating long specifications when the issue or repository document is already authoritative.

## 11. Ready for review

Keep the PR Draft until implementation, validation, and review confidence are sufficient.

Do not mark the PR ready unless the user explicitly directs it.

When the user marks it ready, verify:

- the PR is non-draft;
- the head SHA is the expected reviewed commit;
- required CI on that head is green;
- the final diff has no new blocking findings.

## 12. Merge

Do not merge until the user explicitly approves the merge.

Prefer **squash merge** unless the repository or issue requires another strategy. Protect against head movement by verifying/using the exact expected reviewed head where tooling supports it.

## 13. Post-merge verification

After merge, verify:

1. the PR is merged;
2. the related issue is closed/completed as expected;
3. the short-lived branch is deleted;
4. `main` points to the expected merge result;
5. post-merge `main` validation completes successfully;
6. the roadmap/tracker is updated when applicable;
7. acceptance criteria that depend on merge are satisfied.

Record the result under `## Post-merge verification`.

If post-merge validation fails, treat the issue as unfinished and investigate before moving on.

## 14. Stop at the issue boundary

After the issue is fully closed out, stop. Report the completed state and let the user decide when to begin the next issue.
