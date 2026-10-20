# Isolated .NET SDK training curriculum

This curriculum first teaches **Microsoft .NET's normal behavior**, then applies that understanding to **Isolated .NET SDK**. Each session has two aligned delivery tracks: a self-paced learner document with delayed answers, and an AI instructor guide for conversational teaching.

## Session 1 — Understanding .NET and how it selects components

**Status:** Reorganized pilot draft, pending a fresh learner and technical review. The lesson can be studied in shorter sittings; timing should be reassessed in the pilot.

- **[Self-paced Session 1](isolated-dotnet-sdk-session-1-self-paced.md):** Start with [six key terms](isolated-dotnet-sdk-session-1-self-paced.md#key-terms). Learn [Concept 1: the host and executable lookup](isolated-dotnet-sdk-session-1-self-paced.md#concept-1-understanding-the-net-host), [Concept 2: SDK selection](isolated-dotnet-sdk-session-1-self-paced.md#concept-2-understanding-how-net-selects-an-sdk), and [Concept 3: application runtime selection](isolated-dotnet-sdk-session-1-self-paced.md#concept-3-understanding-application-runtime-selection). Understand why the components exist, how they work, common misconceptions, and what command output really proves. Attempt Q1–Q8 **before** checking the [separate answer key](isolated-dotnet-sdk-session-1-self-paced.md#answer-key-and-self-assessment). **Q6 is advanced and optional**; the other seven checkpoints assess foundational concepts.
- **[Session 1 AI instructor guide](isolated-dotnet-sdk-session-1-ai-instructor.md):** A complete ready-to-use presenter prompt, one-question-at-a-time instruction, shared Q1–Q8 hints and scoring, voice-friendly examples, owner-observation safeguards, and a session notes template.

**Optional experimentation:** The learner guide includes brief invitations alongside relevant command examples to inspect your own shell, SDK selection and runtime inventory. Run any commands that interest you, or simply study the illustrative outputs. There are **no separate hands-on exercises**, additional checkpoints, or expectations to install .NET, build or run an application, or change configuration. Command execution never affects session completion.

**Preserved source observations (not assigned reading):** [Windows .NET installation observations](windows-dotnet-installation-observations.md) retain the owner-supplied PowerShell output, Windows screenshots transcriptions, host/SDK/runtime inventories, and filesystem notes formerly embedded in Session 1. The material is **not currently approved as a teaching case study**; its potential educational use and presentation are undecided. It is not required for Q1–Q8 or the AI-led pilot.

**Teaching principle:** Organize around the why, components, mechanisms, misconceptions, and evidence—not a tour of CLI commands. Commands support the concept when they answer a real question. Keep Microsoft's SDK selection and application runtime selection separate; inventory is not proof of actual selection.

### Choosing a format

**Self-paced:** Read in sequence, answer each checkpoint before viewing its A-numbered response, and return to the linked explanation when uncertain. Exercises do not require installing .NET or editing environment settings. Even read-only-looking CLI invocations may produce normal first-run state or telemetry.

**AI-led:** Supply the full learner guide and instructor guide to the presenter. Start with the [ready-to-use AI prompt](isolated-dotnet-sdk-session-1-ai-instructor.md#ready-to-use-instructor-prompt). The instructor must actually have access to the source material; a URL alone does not establish access. Voice and text are supported. Do not claim to have observed a learner's computer without actual provided evidence.

**Pilot evaluation:** Compare the same Q1–Q8 concept checks between self-paced and instructor-led learning, distinguishing independent explanations from answers requiring hints. Capture teaching defects and fatigue before deciding how to expand the curriculum.

## Future sessions

**[Session 2 — Understanding Isolated .NET SDK (Issue #213)](https://github.com/infoconex/isolated-dotnet-sdk/issues/213)** is planned, not yet written. It will explain why separate installation roots help, how product installation and host invocation work, what Verify checks about version and origin, the limits of isolation, and lifecycle operations. The product-specific examples removed from the original Session 1 pilot are preserved through pinned historical sources in that issue.

Additional later sessions may cover advanced deployment, editor integration, SDK lifecycle, recovery, auditing, and implementation internals. No full sequence is yet committed.

## Related documentation

- [Documentation home](../README.md)
- [Microsoft .NET SDK selection](https://learn.microsoft.com/en-us/dotnet/core/tools/global-json)
- [Product overview](../../README.md)
- [Verify command contract](../commands/verify.md)
