# Post-v0.3.0 project retrospective — October 2026

This retrospective records the reasoning and observations that led to the v0.4.0 evaluation and hardening phase. It is intentionally descriptive: it explains why the project is changing how it works. Durable rules derived from these conclusions live in [Development operating model](operating-model.md).

## Original problem and product evolution

The project began with a concrete testing problem in the Continuous .NET Upgrade work.

The inventory application itself required .NET 10, while the application being evaluated could target another .NET version. With multiple SDKs present in the container, evaluation could silently use the .NET 10 SDK rather than the SDK intended for the target application. Understanding `global.json` and .NET SDK resolution led to the need for a simple way to install a known SDK in isolation and invoke it explicitly during testing.

The first product idea was an interactive wrapper around Microsoft's `dotnet-install` tooling so a version could be selected easily. The scope also included practical isolated-SDK lifecycle operations such as seeing what was installed and removing isolated SDKs.

The audience then expanded. What began as a personal utility became a tool that could help other developers and support the Continuous .NET Upgrade project. That shift justified a higher bar for standards, portability, documentation, validation, release integrity, and user experience.

The product subsequently stopped depending on `dotnet-install` and evolved into its own isolated-SDK management experience. That architectural change reinforced an important distinction: the product's value is deterministic, explicit SDK isolation and management, not the mechanism originally used to acquire SDKs.

## Product state at v0.3.0

v0.3.0 is considered a natural point to pause feature expansion and evaluate the product through real use.

Install and Remove currently feel effective. List, Verify, and Audit perform distinct jobs but do not yet feel equally polished. In particular, the current separation of List, Verify, and Audit should not be treated as permanent merely because an earlier engineering evaluation favored keeping them separate. Hands-on use should determine whether the current boundaries are the best user experience and whether a richer List could answer more normal questions without unacceptable performance, network coupling, fragility, or cognitive load.

The most important product conclusion is that additional speculative features are not the next priority. The next source of truth should be actual use of the released product.

## Process observations

The strongest process improvement has been consistency. A repeatable issue -> implementation -> validation -> pull request -> merge -> verification loop has materially improved reliability and predictability.

The process becomes expensive when it is not followed consistently. Recovery from skipped or reordered steps can take much longer than following the process in the first place.

Another recurring cost has been excessive context carried from one issue into the next. Historical chat context can preserve stale assumptions and compete with the live repository state. Repository documentation, the current issue, and the current code should therefore remain authoritative, with handoffs carrying only the minimum context needed to continue work.

Most issues have been appropriately sized. The larger problem is avoidable follow-up work discovered immediately after an issue has merged. Some follow-ups are legitimate integration findings, but others indicate that the original implementation, review, or acceptance criteria did not inspect adjacent behavior deeply enough. A deliberate adjacent-impact check should therefore be part of completion review without becoming an excuse for uncontrolled scope expansion.

Automated validation has been valuable primarily as a guardrail against breaking behavior. The owner has not independently reviewed the full test suite recently, so test quantity and green CI should not be treated as proof that the test strategy is optimal. The test suite itself needs periodic review against product risks and behaviors.

Ready-for-Review handoffs should also be optimized for owner judgment rather than internal process detail. When a pull request reaches the Ready-for-Review gate, the handoff should begin with a short TL;DR that explains what changed, why it matters, any notable findings or corrections made during implementation, the current validation state, and any remaining owner judgment. The pull request link and deeper implementation evidence should follow that summary rather than forcing the owner to reconstruct the outcome from issue history or CI details.

A second merge-approval prompt after Ready-for-Review approval adds ceremony without adding useful owner control when the reviewed state has not changed. Ready-for-Review approval should therefore authorize merge after final verification. If the approved head or material scope changes, validation regresses, the integration target changes, or new blocking evidence appears, the approval no longer covers that altered state and owner direction is required again.

## Autonomy and decision quality

Greater implementation autonomy is desired, but the project has exposed an important boundary between technical autonomy and product authority.

Two examples motivated this conclusion:

- removing the prior `dotnet-install`-based behavior was a meaningful product/architecture decision that was not sufficiently visible to the owner before it landed;
- exposing the tool version involved multiple reasonable UX interpretations, and an ambiguous product choice was resolved without first confirming intent.

The lesson is not to reduce autonomy across the board. Routine implementation, refactoring, tests, CI work, documentation consistency, straightforward defect fixes, and dependency-ready sequencing should continue autonomously when repository contracts make the intended outcome clear.

The owner must be involved before decisions that remove capabilities, materially change user-visible behavior, change architecture or compatibility commitments, alter release/version policy, or choose among meaningfully different UX/product interpretations.

## Engineering quality expectations

The desired quality bar is not simply that the scripts work.

Maintainability, self-documentation, easy onboarding, idiomatic implementation, and industry best practices are first-class goals. The project should be understandable and respectable to capable developers who were not present for its history.

PowerShell/Bash behavioral parity is a non-negotiable product requirement. Maintaining two shell implementations has a real cost, but silent divergence is not an acceptable response to that cost. If parity ever becomes disproportionately expensive, the architecture should be reconsidered explicitly rather than allowing the implementations to drift.

Strong architecture is preferred over simplicity for its own sake. Complexity is justified when it protects concrete requirements such as parity, reliability, deterministic behavior, maintainability, testability, security, or portability. Complexity added mainly for hypothetical future extensibility should be challenged.

Established industry conventions should be the default. A custom approach can be appropriate when it materially improves portability, dependency posture, parity, or another real project constraint, but the tradeoff should be explicit rather than accidental.

Performance has not been a material concern so far. It should remain evidence-driven. Explicit performance expectations can be introduced if real usage identifies a need rather than through premature optimization.

## Documentation and credibility

Documentation is part of the product's credibility, not ancillary material.

The desired first impression is that a capable developer should be impressed after a short encounter with the repository and tool. That requires more than technical accuracy. Documentation should be reviewed from multiple perspectives because each role asks different questions.

The v0.4.0 hardening phase should include independent reviews from the perspectives of:

- CTO;
- development manager;
- principal-level engineer;
- junior developer;
- onboarding engineer;
- security;
- compliance;
- DevOps; and
- SRE.

Those reviews should examine value, adoption risk, architecture, tradeoffs, onboarding, trust boundaries, operational behavior, automation, troubleshooting, and long-term maintainability.

## v0.4.0 direction

The project is entering an evaluation and hardening phase rather than a normal feature-development phase.

The priorities are:

1. use the product directly and evaluate the workflows it already provides;
2. review maintainability and architecture as though a new experienced maintainer were inheriting the repository;
3. review the test strategy against product behavior and risk rather than test count;
4. conduct the persona-based documentation review;
5. evaluate List, Verify, and Audit through hands-on use before changing their boundaries;
6. fix confirmed defects and strengthen existing behavior;
7. avoid new capability unless an explicit review establishes a material omission or important requirement; and
8. challenge backlog items that do not provide enough value to justify their complexity, risk, or maintenance cost.

The evaluation is tracked in [v0.4.0 hardening and evaluation tracker](https://github.com/infoconex/isolated-dotnet-sdk/issues/133).

## Completion signal

The hardening phase does not end merely because an issue list is empty.

It ends when hands-on use and the planned reviews stop exposing material unresolved concerns, confirmed findings have been resolved or intentionally accepted, the product and repository feel coherent as a whole, and the owner is impressed with the resulting state.

At that point, the correct next action may be another development phase or simply using the product for a period of time. Producing more code is not itself a success criterion.
