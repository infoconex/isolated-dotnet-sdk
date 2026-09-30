# Issue execution workflow

This document is the authoritative lifecycle for taking an implementation issue from selection through post-merge verification.

The goal is repeatable, evidence-driven delivery with clear traceability. Issue, comment, Task, and pull request formatting conventions are defined in [`issue-conventions.md`](issue-conventions.md).

## Core rules

- Work one implementation issue at a time unless an issue explicitly permits independent parallel work.
- Treat the GitHub issue as the traceability and evidence hub.
- Keep requirements, implementation, tests, documentation, and evidence aligned.
- Prefer automation and deterministic evidence over manual checks.
- Establish mechanically verifiable facts with automation/tooling rather than asking the user to re-verify them manually.
- Green CI is necessary evidence, not proof by itself that a change is correct.
- Optimize validation for distinct evidence. Do not run equivalent full validation twice on the same source SHA unless the runs serve materially different enforcement or coverage purposes.
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

## 3. Create the working branch

After requirements are clear:

1. create a focused short-lived branch from current `main`;
2. keep the issue open;
3. do **not** open a pull request yet.

The working branch is the implementation workspace. Creating or updating a normal working branch does not automatically run the complete Validate matrix; full pre-merge validation is normally reserved for the pull request's exact reviewed head. Use targeted deterministic checks while developing, and use the explicit/manual full branch-validation path only when it provides a distinct safety or diagnostic signal.

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

## 7. Reconcile Tasks and acceptance criteria

Follow the Task definition and comment conventions in [`issue-conventions.md`](issue-conventions.md).

Task and acceptance-criteria state must remain auditable, but routine coherent work does not require one issue mutation or completion comment after every small Task. Use one of these evidence modes:

### Consolidated reconciliation — normal coherent work

For a focused change that is proceeding continuously under one implementation plan:

1. complete the planned Tasks and scoped commits;
2. run the appropriate targeted validation while implementing;
3. preserve Task-level traceability in commits, tests, diff structure, and working evidence;
4. at the next meaningful lifecycle boundary, and **no later than before Draft PR creation**, reconcile all completed Task checkboxes and acceptance criteria in one deliberate issue update;
5. add `## Task reconciliation — implementation complete` with concise evidence mapping the completed Tasks to commits/changes/validation.

### Incremental Task evidence — when it adds value

Use `## Task N complete — <concise task/capability>` and synchronize that Task's checkbox immediately when the work is long-running, risky, interrupted, multi-contributor, independently reviewable, or otherwise benefits from durable per-Task checkpoints. Supplemental/remediation comments remain appropriate when new evidence materially changes the Task record.

Regardless of evidence mode:

- every planned Task completed before the Draft PR must be checked before the Draft PR is opened;
- check acceptance criteria as soon as the chosen lifecycle reconciliation establishes them, leaving only criteria that genuinely depend on exact-head PR validation, merge, or another later event unchecked;
- do not leave completed Tasks or already-established acceptance criteria stale at a lifecycle gate.

## 8. Validate with distinct lifecycle signals

Use repository-owned validation whenever possible. Evidence may include:

- parser/syntax validation;
- static analysis;
- automated behavioral tests;
- cross-platform CI jobs;
- deterministic version/checksum verification;
- targeted manual validation only when automation cannot establish the behavior reliably.

The normal delivery path deliberately separates validation stages by purpose:

1. **Development / pre-PR validation:** run targeted deterministic checks that give useful feedback for the files or behavior changed. Full remote branch validation is not required merely because work exists on a branch.
2. **Explicit/manual full branch validation:** the Validate workflow's `workflow_dispatch` path remains available when full cross-platform branch evidence serves a distinct purpose, such as diagnosing platform-specific risk before opening a PR or validating unusually risky infrastructure work.
3. **Authoritative pre-merge validation:** opening/updating the pull request runs the complete Validate matrix on the exact PR head. This is the normal authoritative full pre-merge signal and must be green before merge.
4. **Post-merge validation:** `push: main` runs the complete Validate matrix on the landed commit. Keep this required while the repository's current protection model still needs independent landed-state verification.

Do not run an equivalent full branch Validate and full PR Validate on the same exact source SHA solely because the SHA existed first on a working branch. Two full validations on one SHA are justified only when they provide materially different coverage, enforcement, or diagnostic evidence.

Do not ask the user to perform mechanical validation that can reasonably be automated. Establish and report that evidence directly with available tooling. Manual validation is appropriate only when automation cannot reliably establish the behavior or when the remaining question is inherently subjective, such as product intent, UX judgment, architecture/tradeoffs, policy, or risk acceptance. When manual validation is required, record exactly what was verified and the observed result.

Merge-queue enforcement and automatic E2E merge-candidate gating are separate future protection work. This lifecycle does not assume those capabilities are already available and does not remove post-merge Validate on that assumption.

## 9. Perform the full review

After implementation and appropriate pre-PR validation are complete, review the actual diff for:

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

Passing targeted checks or CI does not replace this review.

If the review finds gaps:

1. fix in-scope findings on the same branch;
2. create follow-up issues for unrelated findings;
3. rerun appropriate validation;
4. repeat the full review.

Do not recommend merge while blocking findings remain.

Record the completed comprehensive review under `## Full review — implementation complete` or include the equivalent review evidence in the consolidated Task reconciliation when that remains clear and auditable.

## 10. Open the Draft PR

Open the pull request as **Draft** only after all of the following are true:

- planned implementation Tasks are complete and their issue checkboxes are reconciled;
- the linked issue has been reconciled so acceptance criteria already established by durable evidence are checked, with only criteria genuinely dependent on exact-head PR validation or merge left open;
- appropriate targeted pre-PR validation is green, plus any explicit/manual full branch validation that was justified for this change;
- the full branch diff against current `main` has been reviewed;
- no known blocking findings remain.

Opening/updating the PR is what normally obtains the authoritative complete pre-merge Validate matrix on the exact reviewed head. The Draft PR is therefore the formal review and exact-head CI artifact, not a second copy of an equivalent full branch-validation stage.

Link the PR to the issue, normally with `Closes #<issue>` when appropriate. Record `## Draft PR opened` when the PR link, reviewed head, and Draft status add useful traceability.

Do not mark the Draft PR ready automatically. The user decides when it becomes ready for review. Do not merge without explicit user approval.

## 11. Record final evidence

Before the PR is considered complete, record concise durable evidence, including as applicable:

- requirements/specification references;
- test-list and RED → GREEN → REFACTOR evidence for behavioral changes;
- implementation summary;
- targeted pre-PR validation and any justified manual full branch validation;
- final complete Validate evidence on the exact reviewed PR head;
- manual validation evidence;
- final review result;
- intentionally deferred follow-up issues.

After exact-head PR validation and final PR verification, reconcile the linked issue again. Check every acceptance criterion now established by durable evidence. Any criterion left unchecked at the Ready-for-Review decision must genuinely depend on merge or another later lifecycle event.

Use `## Final review — completion evidence` for the final exact-head summary. Avoid duplicating long specifications when the issue or repository document is already authoritative.

The completion handoff to the user must clearly separate:

- **Programmatically verified evidence** — facts already established by repository inspection, tests, static analysis, CI, API/tool queries, or exact diff/head review. Report these as completed evidence; do not present them as work the user needs to repeat.
- **User judgment or approval still required** — decisions that genuinely require the user's authority or subjective judgment, including the explicit Ready for Review and merge gates, policy/product choices, architecture/tradeoffs, UX judgment, risk acceptance, or validation that cannot reasonably be automated.

If no user judgment remains other than an explicit lifecycle approval gate, say so directly.

## 12. Ready for review

The PR should already be Draft only after implementation, appropriate targeted pre-PR validation, issue reconciliation, and full diff review reached the quality threshold in the previous steps. Use complete PR CI and exact-head verification to confirm that reviewed state before readiness.

Do not mark the PR ready unless the user explicitly directs it.

When the user marks it ready, verify:

- the PR is non-draft;
- the head SHA is the expected reviewed commit;
- required CI on that head is green;
- the final diff has no new blocking findings.

## 13. Merge

Do not merge until the user explicitly approves the merge.

Prefer **squash merge** unless the repository or issue requires another strategy. Protect against head movement by verifying/using the exact expected reviewed head where tooling supports it.

## 14. Post-merge verification

After merge, verify:

1. the PR is merged;
2. the related issue is closed/completed as expected;
3. the short-lived branch is deleted;
4. `main` points to the expected merge result;
5. post-merge `main` validation completes successfully;
6. the roadmap/tracker is updated when applicable;
7. acceptance criteria that depend on merge are satisfied and checked;
8. no completed Task or satisfied acceptance criterion remains unchecked in the issue.

Reconcile the issue checkbox state before declaring the issue fully closed out. A stale unchecked completed Task or satisfied acceptance criterion is unfinished lifecycle bookkeeping and must be corrected.

Record the result under `## Post-merge verification`.

If post-merge validation fails, treat the issue as unfinished and investigate before moving on.

## 15. Stop at the issue boundary

After the issue is fully closed out, stop. Report the completed state and let the user decide when to begin the next issue.
