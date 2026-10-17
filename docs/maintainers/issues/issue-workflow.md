# Issue execution workflow

This document is the authoritative lifecycle for taking an implementation issue from selection through post-merge verification.

The goal is repeatable, evidence-driven delivery with clear traceability. Durable development principles and decision authority are defined in the [development operating model](../development/operating-model.md). Issue, comment, Task, and pull request formatting conventions are defined in [`issue-conventions.md`](issue-conventions.md).

## Core rules

- Work one implementation issue at a time unless an issue explicitly permits independent parallel work.
- Treat the GitHub issue as the traceability and evidence hub.
- Keep requirements, implementation, tests, documentation, and evidence aligned.
- Prefer automation and deterministic evidence over manual checks.
- Establish mechanically verifiable facts with automation/tooling rather than asking the user to re-verify them manually.
- Green CI is necessary evidence, not proof by itself that a change is correct.
- Optimize validation for distinct evidence. Do not run equivalent full validation twice on the same source SHA unless the runs serve materially different enforcement or coverage purposes.
- Do not include unrelated cleanup. For material unrelated findings, use the issue-proposal and owner-approval lifecycle below before creating any follow-up issue.
- Prefer live repository state over historical conversation context.
- When a next-release integration branch exists, use it as the normal issue base and pull-request target. `main` remains the released-production line unless an explicitly approved release/hotfix workflow says otherwise.
- Creating a new GitHub issue from a discovered finding requires explicit owner approval. Investigation and recommendation remain autonomous; backlog creation does not.
- Before drafting a proposed issue, inspect the current repository issue template and issue conventions rather than relying on remembered structure.

## Creating issues from discovered findings

When repository work discovers a material follow-up, do not create the GitHub issue automatically. This applies to findings from implementation, full review, adjacent-impact review, validation, retrospectives, architecture/testing/documentation/UX evaluations, and other repository analysis.

Use this lifecycle:

1. inspect the current `.github/ISSUE_TEMPLATE/implementation.md` and [`issue-conventions.md`](issue-conventions.md);
2. determine whether the finding materially justifies a separate issue rather than in-scope completion work, an accepted/deferred concern, or no change;
3. draft the proposed issue from the current template, adapting sections only when they genuinely do not apply;
4. present the proposed title, rationale, scope, non-goals, and meaningful dependency/sequencing implications to the owner;
5. obtain explicit owner approval to add the issue to the repository backlog; and
6. only then create the GitHub issue.

This approval gate applies to **issue creation**, not to investigation. Continue to inspect, analyze, prioritize, and recommend findings autonomously when repository contracts make that work appropriate.

Once an approved issue is created, it must be independently understandable and executable from its own body/comments and repository artifacts. Preserve genuine technical dependencies and sequencing relationships when they exist; independence does not mean pretending related work is unrelated.

## 1. Select and verify the issue

Before making changes:

1. Read `AGENTS.md`, the [development operating model](../development/operating-model.md), this document, and [`issue-conventions.md`](issue-conventions.md).
2. Review the current roadmap/tracker when one applies and verify the selected issue's dependencies are complete or intentionally revised.
3. Determine the intended integration target:
   - use the active next-release integration branch, such as `release/0.4`, for normal next-release work;
   - use `main` only when no release integration branch exists or when the issue is explicitly a released-line hotfix/release task.
4. Inspect the current integration target, released `main` state, and latest relevant repository validation.
5. Read the exact current issue body, comments, acceptance criteria, dependencies, and non-goals.
6. Inspect relevant source, tests, specifications, and documentation on the integration target.

Repository documentation, the current issue, and live repository state define the working contract. Resolve contradictions between current repository artifacts before implementation.

## 2. Review requirements and decision authority

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

If a material requirement is unclear, contradictory, or missing and the choice could change the public contract, safety, scope, architecture, compatibility, release policy, or meaningful UX/product behavior:

1. comment on the issue with the specific ambiguity and meaningful alternatives;
2. stop implementation;
3. wait for owner direction.

Owner direction is specifically required before removing/deprecating capability, materially changing user-visible workflow, changing major architecture or compatibility commitments, changing release/version policy, weakening safety/integrity guarantees, or resolving meaningful product/UX ambiguity.

Do not stop for routine implementation choices that established repository conventions already resolve. Update the issue before implementation when requirements need refinement so it remains authoritative.

## 3. Create the working branch

After requirements are clear:

1. create a focused short-lived issue branch from the intended integration target;
2. keep the issue open;
3. do **not** open a pull request yet.

During an active release cycle, a normal issue branch starts from the active release integration branch and later targets that same branch. Do not branch normal next-release work from `main` merely because `main` is the default branch.

The working branch is the implementation workspace. Creating or updating a normal working branch does not automatically require the complete Validate matrix; full pre-merge validation is normally reserved for the pull request's exact reviewed head. Use targeted deterministic checks while developing, and use the explicit/manual full branch-validation path only when it provides a distinct safety or diagnostic signal.

## 4. Record the implementation plan

Before making implementation changes, add `## Implementation plan — planned tasks` to the issue.

Identify the planned Tasks, likely commit boundaries, scope, intended integration target, and validation approach. For behavioral work, include the initial test-list behaviors or scenarios that will drive the first TDD cycles.

Avoid generic status comments without meaningful scope.

## 5. Implement with specification-driven TDD

### Behavioral changes

A Task may contain multiple behaviors; the Task is not itself the TDD unit. Take one smallest meaningful behavior at a time through **RED -> GREEN -> REFACTOR**.

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

Do not bundle incidental cleanup into the active issue. For material unrelated work, use the issue-proposal and owner-approval lifecycle above; create a follow-up issue only after explicit approval.

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
4. **Post-merge integration validation:** after the issue merges, validate the landed state of the issue's integration target according to repository workflow coverage. During an active release cycle this may be the release integration branch rather than `main`.
5. **Stable-line validation:** final next-release promotion to `main` and stable publication have their own release-level validation defined by the release process. Issue-level post-merge validation does not substitute for release-candidate validation.

Do not run an equivalent full branch Validate and full PR Validate on the same exact source SHA solely because the SHA existed first on a working branch. Two full validations on one SHA are justified only when they provide materially different coverage, enforcement, or diagnostic evidence.

Do not ask the user to perform mechanical validation that can reasonably be automated. Establish and report that evidence directly with available tooling. Manual validation is appropriate only when automation cannot reliably establish the behavior or when the remaining question is inherently subjective, such as product intent, UX judgment, architecture/tradeoffs, policy, or risk acceptance. When manual validation is required, record exactly what was verified and the observed result.

## 9. Perform the full review and adjacent-impact check

After implementation and appropriate pre-PR validation are complete, review the actual diff for:

- correctness against the issue/specification;
- failure and boundary behavior;
- scope discipline and unrelated changes;
- test quality and meaningful coverage;
- PowerShell/Bash idioms and behavioral parity;
- analyzer/static-analysis cleanliness;
- documentation consistency;
- security and supply-chain implications;
- deterministic/reproducible behavior;
- cross-platform implications;
- accidental file deletion or content loss;
- unnecessary abstractions or complexity.

Then perform an explicit adjacent-impact check. Inspect whether the change creates or exposes an obvious inconsistency in the equivalent shell, adjacent command/menu behavior, tests, documentation, CI/release behavior, terminology, or product contracts.

Passing targeted checks or CI does not replace this review.

If the review finds gaps:

1. fix closely coupled in-scope findings on the same branch when they are necessary for a complete result;
2. for material unrelated findings, draft and present a follow-up issue proposal using the issue-creation lifecycle above, then create it only after explicit owner approval;
3. rerun appropriate validation;
4. repeat the full review.

Do not recommend merge while blocking findings remain.

Record the completed comprehensive review under `## Full review — implementation complete` or include the equivalent review evidence in the consolidated Task reconciliation when that remains clear and auditable.

## 10. Open the Draft PR

Open the pull request as **Draft** only after all of the following are true:

- planned implementation Tasks are complete and their issue checkboxes are reconciled;
- the linked issue has been reconciled so acceptance criteria already established by durable evidence are checked, with only criteria genuinely dependent on exact-head PR validation or merge left open;
- appropriate targeted pre-PR validation is green, plus any explicit/manual full branch validation that was justified for this change;
- the full branch diff against the intended integration target has been reviewed;
- the PR base is the intended integration target;
- no known blocking findings remain.

Opening/updating the PR is what normally obtains the authoritative complete pre-merge Validate matrix on the exact reviewed head. The Draft PR is therefore the formal review and exact-head CI artifact, not a second copy of an equivalent full branch-validation stage.

Reference the issue according to [`issue-conventions.md`](issue-conventions.md): use `Closes #<issue>` when the PR targets `main` and should auto-close the issue, but use `Refs #<issue>` for a PR targeting a non-default release integration branch. An integration-branch issue remains open until post-merge verification succeeds, then it is closed explicitly.

Record `## Draft PR opened` when the PR link, reviewed head, base branch, and Draft status add useful traceability.

Do not mark the Draft PR ready automatically. The user decides when it becomes ready for review. That Ready-for-Review approval also authorizes merge of the reviewed state after the final verification in the next steps; do not request a separate merge approval unless the approved state materially changes or new blocking evidence appears.

## 11. Record final evidence

Before the PR is considered complete, record concise durable evidence, including as applicable:

- requirements/specification references;
- test-list and RED -> GREEN -> REFACTOR evidence for behavioral changes;
- implementation summary;
- targeted pre-PR validation and any justified manual full branch validation;
- final complete Validate evidence on the exact reviewed PR head;
- manual validation evidence;
- final review and adjacent-impact result;
- intentionally deferred follow-up issues.

After exact-head PR validation and final PR verification, reconcile the linked issue again. Check every acceptance criterion now established by durable evidence. Any criterion left unchecked at the Ready-for-Review decision must genuinely depend on merge or another later lifecycle event.

Use `## Final review — completion evidence` for the final exact-head summary. Avoid duplicating long specifications when the issue or repository document is already authoritative.

The completion handoff to the user must clearly separate:

- **Programmatically verified evidence** — facts already established by repository inspection, tests, static analysis, CI, API/tool queries, or exact diff/head review. Report these as completed evidence; do not present them as work the user needs to repeat.
- **User judgment or approval still required** — decisions that genuinely require the user's authority or subjective judgment, including the Ready-for-Review gate, policy/product choices, architecture/tradeoffs, UX judgment, risk acceptance, or validation that cannot reasonably be automated. Ready-for-Review approval includes merge authorization for the reviewed state.

If no user judgment remains other than an explicit lifecycle approval gate, say so directly.

## 12. Ready for review

The PR should already be Draft only after implementation, appropriate targeted pre-PR validation, issue reconciliation, and full diff review reached the quality threshold in the previous steps. Use complete PR CI and exact-head verification to confirm that reviewed state before readiness.

Do not mark the PR ready unless the user explicitly directs it.

When the user approves Ready for Review, mark the PR ready and verify:

- the PR is non-draft;
- the base branch is still the intended integration target;
- the head SHA is the expected reviewed commit;
- required CI on that head is green;
- the final diff has no new blocking findings.

Ready-for-Review approval authorizes merge of that exact reviewed state after these checks. If the head or material scope changes, required CI regresses, the base/integration target changes, or a new blocking finding appears, stop and obtain renewed owner approval before merging.

## 13. Merge

After Ready-for-Review approval and successful final verification, proceed to merge without a second owner approval prompt.

Prefer **squash merge** unless the repository or issue requires another strategy. Protect against head movement by verifying/using the exact expected reviewed head where tooling supports it.

Normal next-release issue PRs merge into the active release integration branch. They do not merge to `main` individually while that integration model is active.

## 14. Post-merge verification

After merge, verify:

1. the PR is merged into the intended integration target;
2. the short-lived issue branch is deleted;
3. the integration target points to the expected merge result;
4. required post-merge validation for that integration target completes successfully, where repository workflow triggers provide it;
5. the roadmap/tracker is updated when applicable;
6. acceptance criteria that depend on merge are satisfied and checked;
7. no completed Task or satisfied acceptance criterion remains unchecked in the issue;
8. the related issue is closed/completed as expected. When the PR targeted a non-default integration branch, close the issue explicitly only after the preceding post-merge checks succeed.

Reconcile the issue checkbox state before declaring the issue fully closed out. A stale unchecked completed Task or satisfied acceptance criterion is unfinished lifecycle bookkeeping and must be corrected.

Record the result under `## Post-merge verification`.

If post-merge validation fails, treat the issue as unfinished and investigate before moving on; do not close the issue merely because the integration PR merged.

Merging an issue to the release integration branch is not a stable release. Final integration-branch review, merge to `main`, release documentation, publication, and public verification are governed separately by the stable release process.

## 15. Stop at the issue boundary

After the issue is fully closed out, stop. Report the completed state and let the user decide when to begin the next issue.
