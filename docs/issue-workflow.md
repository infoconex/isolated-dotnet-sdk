# Issue execution workflow

This document is the authoritative repository process for taking an implementation issue from selection through post-merge verification.

The goal is repeatable, evidence-driven delivery with clear traceability. Do not rely on chat history to reconstruct this process.

## Core rules

- Work one implementation issue at a time unless an issue explicitly permits independent parallel work.
- Treat the GitHub issue as the traceability and evidence hub.
- Keep requirements, implementation, tests, documentation, and evidence aligned.
- Prefer automation and deterministic evidence over manual checks.
- Green CI is necessary evidence, not proof by itself that a change is correct.
- Do not include unrelated cleanup. Capture material unrelated work as a follow-up issue.
- Use **workstream** for a capability-level unit of progress inside an issue. Do not call these milestones.
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

Before creating production changes, review the issue as a specification.

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

Before changing production behavior, add an issue comment stating what will be implemented next.

The comment should identify the planned workstreams or capability-level scope and the validation approach. Avoid generic status comments such as "starting work" without meaningful scope.

## 5. Specification-driven and test-driven implementation

### Behavioral changes

For behavior changes, use this sequence:

1. write or identify the repository specification;
2. add or update automated tests before production behavior changes;
3. establish a meaningful failing result (**RED**) that reaches the intended behavior under test;
4. implement the smallest correct production change;
5. reach **GREEN**;
6. refactor only while preserving the tests and contract.

A failing parser, analyzer, dependency install, or broken test harness is not meaningful RED evidence for the product behavior. Fix the harness first and establish a failure that demonstrates the missing behavior.

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

## 7. Workstream completion

When an issue contains multiple capability-level workstreams:

1. complete one workstream;
2. run the relevant validation;
3. commit the scoped change;
4. add a focused issue comment describing what was completed and the evidence;
5. then move to the next workstream.

Workstream comments should be useful traceability, not a running activity log.

A useful completion comment includes items such as:

- capability completed;
- important contract decisions;
- tests/static analysis run;
- relevant commit or CI evidence;
- newly discovered follow-up issues.

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
- TDD RED evidence for behavioral changes;
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

## Issue comment pattern

Use comments sparingly and intentionally. The expected pattern is:

1. **Requirements review / kickoff** — understanding, assumptions, ambiguities.
2. **Pre-implementation scope** — workstreams and validation approach.
3. **Workstream completion** — one comment for each meaningful capability completed, when the issue has multiple workstreams.
4. **Manual evidence** — only when manual validation is genuinely required.
5. **Final review/evidence** — exact reviewed head, CI evidence, review result, and follow-ups.

Do not add generic comments for every tool call, commit, or routine status change.

## Pull request expectations

A useful PR description normally includes:

- summary and linked issue;
- behavioral/technical contract being implemented;
- TDD RED evidence when applicable;
- implementation summary;
- validation evidence;
- manual validation evidence when applicable;
- final review status;
- focused review areas.

The PR should remain understandable to a future maintainer without requiring the original chat transcript.
