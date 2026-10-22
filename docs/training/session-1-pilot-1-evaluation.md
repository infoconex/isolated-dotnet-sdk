# Session 1 — Pilot 1 evaluation and retest criteria

**Date:** 2026-10-20  
**Delivery:** AI-led voice conversation, Windows/PowerShell examples  
**Status:** Pilot findings recorded; second pilot pending  
**Scope:** Instructor behavior and foundational .NET concepts, not a production verification of the Isolated .NET SDK tool.

## Observed findings

| Finding | Evidence from pilot | Remediation | Retest expectation |
| --- | --- | --- | --- |
| Instructor repeatedly requested permission to continue | Learner repeatedly corrected “want to continue?”/pausing behavior | Mandatory continuity rules in AI Instructor Guide and reusable prompt | Instructor advances after explanations, clarifications and checkpoint feedback without permission-seeking |
| Assessments sometimes preceded sufficient explanation | Learner requested more teaching before questioning | Explicit teach-before-checkpoint requirement | Explain mechanism and example before canonical checkpoint |
| Checkpoint sequence drifted | Completion summary could not verify all Q1–Q8 were asked in order | Canonical checkpoint sequence emphasized, Q6 optional | Q1–Q5, Q7, Q8 completed and recorded; Q6 clearly optional |
| Meta-discussion interrupted teaching | Instructor surfaced curriculum-design notes during lesson | Record feedback separately; discuss only when requested | Learner hears teaching, not pilot-management commentary |
| Clarification interrupted momentum | Instructor stopped instead of resuming after answering | Explicit resume-at-interruption-point rule | Clarification answered and lesson resumed naturally |
| SDK version policies needed clearer examples | Feature-band and prerelease/RC questions | Added feature-band and prerelease eligibility explanation to self-paced guide | Learner can distinguish feature-band patch behavior and prerelease eligibility |
| Deployment model boundary needed explanation | Questions about apphost, self-contained vs framework-dependent launch | Added concise deployment distinction | Learner distinguishes apphost presence from runtime bundling |

## Assessment evidence and limitations

The conversation explored executable/host identity, SDK selection and runtime selection, and corrected misconceptions about SDK roll-forward and deployment models. The available conversation summary does **not** establish an ordered, individually scored Q1–Q8 result. Record required checkpoints as **not formally verified**, rather than inventing independent passes. The first pilot is evidence for instructor-design improvements, **not** proof of complete curriculum assessment.

Technical assertions about edge cases (especially invoking a self-contained DLL via a separate system `dotnet` host) should be verified against Microsoft documentation before becoming scored curriculum requirements. The core Session 1 boundary is that a framework-dependent app uses compatible installed shared frameworks, while a self-contained publication packages its runtime.

## Cross-document consistency check

- Both documents teach the three decisions in order: executable/host, SDK, application runtime.
- Both reference canonical Q1–Q8; Q6 is optional advanced, and Q1–Q5 plus Q7–Q8 are required.
- Both distinguish inventory from observed selection; examples are illustrative, not claims about the learner's machine.
- Both keep live experiments optional, non-destructive, and integrated into existing command explanations.
- Instructor Guide now explicitly controls pacing, checkpoint order, interruption recovery and separate feedback collection.
- The self-paced guide now clarifies feature bands, prerelease/RC eligibility and the deployment-model boundary.
- Session 2 remains the place for product-specific isolation guarantees and operations.

## Second-pilot protocol

Start a **new conversation** within the Isolated DotNet Sdk project. Ensure the instructor can actually access both the current AI Instructor Guide and self-paced curriculum on the curriculum branch; a URL alone is not proof of retrieval. Run Session 1 as a normal learner without coaching the instructor's pacing. Allow natural clarifications. At completion, capture the seven required checkpoint outcomes separately, identify any unassessed questions, and assess the four behavioral expectations: autonomous progression, teach-before-assess, automatic resumption, and separation of pilot notes from teaching.

**Release gate:** Do not mark the training complete or merge PR #207 solely because the revised text exists. Evaluate the fresh pilot, address any failures, then review the draft PR for release/0.5.
