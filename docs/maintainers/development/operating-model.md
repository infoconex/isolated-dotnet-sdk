# Development operating model

This document defines the durable development and decision-making rules for the repository after the v0.3.0 release. The reasoning that produced these rules is recorded in the [October 2026 retrospective](retrospective-2026-10.md).

## Product phase

The project is currently in a v0.4.0 evaluation and hardening phase.

Default to strengthening the product that already exists:

- correct confirmed defects;
- improve reliability and failure handling;
- improve maintainability and onboarding;
- improve documentation and validation quality;
- improve the usability of existing workflows when real use establishes a problem.

Do not add new capability merely because it is plausible or interesting. New capability requires explicit owner agreement and evidence that it is a material omission or important requirement.

The current evaluation is tracked in [v0.4.0 hardening and evaluation tracker](https://github.com/infoconex/isolated-dotnet-sdk/issues/133).

## Engineering principles

### PowerShell/Bash parity is required

The supported PowerShell and Bash implementations must remain behaviorally equivalent for the product contracts they share.

Parity must be protected through specifications, tests, review, and deliberate implementation. If maintaining two implementations becomes disproportionately expensive, raise an architectural decision rather than accepting silent divergence.

### Prefer strong architecture over accidental simplicity

Complexity is acceptable when it protects a concrete requirement such as:

- cross-shell parity;
- deterministic behavior;
- reliability;
- maintainability;
- testability;
- security or supply-chain integrity; or
- portability.

Complexity introduced mainly for hypothetical future extension should be challenged.

### Prefer industry conventions

Use idiomatic Bash, PowerShell, GitHub Actions, Git, Markdown, and repository practices by default.

A custom approach is justified only when a concrete project constraint makes it materially better. When deviating from a common convention, make the reason discoverable in code, tests, documentation, or the governing issue as appropriate.

### Optimize from evidence

Do not optimize performance, architecture, CI, or UX merely because an improvement is theoretically possible. Measure or observe a real cost first unless a correctness, safety, or standards requirement already makes the change necessary.

Green CI is necessary evidence, not proof that the design, tests, or user experience are correct.

## Decision authority

The goal is high implementation autonomy with a narrow, explicit owner-decision boundary.

### Autonomous decisions

A developer or agent may proceed without separate owner approval when established repository contracts make the intended outcome clear, including:

- routine implementation details;
- focused refactoring that preserves behavior;
- test additions and test maintenance;
- CI maintenance within established policy;
- documentation consistency and link repair;
- straightforward defect fixes;
- dependency-ready issue sequencing; and
- mechanical or standards-conformance cleanup that does not change the product contract.

### Owner decision required

Stop and obtain owner direction before:

- removing or deprecating a capability;
- materially changing user-visible behavior or workflow;
- changing architecture in a way that alters major product boundaries or maintenance strategy;
- changing supported platforms or compatibility commitments;
- changing release or versioning policy;
- weakening an integrity, validation, or safety guarantee; or
- choosing among meaningfully different product or UX interpretations when the requirement is ambiguous.

Do not silently reinterpret an issue to make implementation easier when the reinterpretation crosses one of these boundaries.

When a decision is required, present the ambiguity and the meaningful alternatives concisely. Do not ask for approval on routine implementation choices that are already governed by repository standards.

## Hands-on product validation

Automated validation protects observable contracts but cannot determine whether a user-facing workflow actually feels coherent, clear, or polished.

Meaningful new user-visible behavior or material UX changes should receive hands-on owner evaluation before the product decision is considered fully validated. Record manual evaluation only for the subjective behavior automation cannot establish; do not ask the owner to repeat mechanical checks that automation already proves.

During the current hardening phase, hands-on use of Install, Remove, List, Verify, Audit, interactive mode, and representative automation scenarios is itself a planned product evaluation activity.

## Adjacent-impact review

Before declaring an implementation complete, inspect the nearby behavior affected by the change.

Ask whether the change creates or exposes an obvious inconsistency in:

- the equivalent shell implementation;
- adjacent command or menu behavior;
- tests;
- documentation;
- release or CI behavior; or
- terminology and product contracts.

Fix closely coupled in-scope inconsistencies in the same issue when they are necessary for a complete result. Do not use adjacent-impact review to absorb unrelated cleanup or expand an issue indefinitely. Material unrelated findings become separate issues.

## Context discipline

The repository is the durable source of truth.

For new issue work:

- prefer current repository files, current issues, current comments, and current validation state over historical chat summaries;
- carry only the minimum handoff context needed to locate the intended work;
- re-inspect live dependencies and repository state rather than assuming an old sequence is still correct; and
- persist durable decisions in repository documentation instead of repeatedly copying large historical context into new conversations.

Historical conversation context can explain intent, but it must not override current repository contracts silently.

## Ready-for-Review handoff

When work reaches the Ready-for-Review gate, lead the owner handoff with a concise TL;DR before deeper evidence.

The TL;DR should answer, in this order:

- what changed;
- why the change matters;
- any notable findings, corrections, or adjacent issues resolved while implementing it;
- validation status on the exact reviewed head; and
- any remaining owner judgment or approval required.

Then provide the pull request link and only the additional detail needed for informed review. Do not make the owner reconstruct the result from raw issue history, commit history, or CI logs when the mechanically verifiable evidence is already known.

Ready-for-Review approval is also the owner's authorization to merge that reviewed state after final exact-head verification. Do not ask for a second merge approval when nothing material has changed. Seek renewed owner approval only if the approved head or material scope changes, required validation regresses, the intended integration target changes, or a new blocking finding appears.

## Backlog discipline

An issue or idea is not automatically worth implementing because it exists.

Before starting work, consider whether it:

- solves a demonstrated problem;
- strengthens the current product phase;
- duplicates an existing capability;
- introduces disproportionate complexity or maintenance cost;
- weakens architectural clarity; or
- represents speculative feature expansion.

During v0.4.0 hardening, prefer evaluation first and create implementation follow-ups only for findings that justify action.

## Release integration model

`main` is the released-production line.

When a next-release integration branch exists, such as `release/0.4`:

- focused issue branches start from the active release integration branch;
- pull requests for next-release work target the active release integration branch;
- merging one issue into the integration branch does not by itself constitute a stable release;
- the release candidate is evaluated as an integrated whole before it is merged to `main`; and
- the integration branch is temporary and deleted after the release is completed.

Do not add a permanent `develop` branch or full GitFlow lifecycle without a separately approved reason.

For an urgent fix to the currently released production line:

1. branch from `main`;
2. land the fix back to `main` through the normal review process;
3. publish the appropriate patch release when required; and
4. forward-port the fix into the active next-release integration branch so the upcoming release does not lose it.

Detailed issue execution is defined in [Issue execution workflow](../issues/issue-workflow.md). Stable publication remains defined in [Stable release publication and verification](../releases/release-process.md).

## Quality target and hardening exit

The project should be maintainable, self-documenting, easy to onboard into, idiomatic, and professionally credible to experienced developers.

The current hardening phase is complete when hands-on use and the planned engineering, testing, documentation, and UX reviews no longer reveal material unresolved concerns, confirmed findings are resolved or explicitly accepted, and the owner is impressed with the state of the product and repository.

An empty backlog is not the completion criterion, and producing additional code is not inherently progress.
