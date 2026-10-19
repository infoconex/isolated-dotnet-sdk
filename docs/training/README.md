# Isolated .NET SDK training curriculum

This curriculum builds understanding of Microsoft's normal .NET behavior **before** explaining how Isolated .NET SDK manages SDK installations. Start with the self-paced lesson if you prefer to read independently, or use the same lesson together with the AI instructor guide for voice/text tutoring.

## Session 1 — How `dotnet` is resolved, and why isolation matters

**Status:** Pilot draft (example-first revision); ready for learner review, not yet pedagogically validated. **Estimated learner time:** Approximately 60–90 minutes for the expanded self-paced lesson, which can be divided into shorter sessions.

- **[Self-paced Session 1](isolated-dotnet-sdk-session-1-self-paced.md):** A deeper explanation of the **host, SDK, and runtime** (including why their versions differ), Windows PowerShell and Bash examples with **illustrative output explained line by line**, a .NET 10 SDK building an app that runs on .NET 8, unexpected-result troubleshooting, and Q1–Q8 reinforcement questions with an answer key. No AI required.
- **[Session 1 AI instructor guide](isolated-dotnet-sdk-session-1-ai-instructor.md):** Copy-ready teaching prompt, one-question-at-a-time sequence, matching Q1–Q8 hint/evaluation guidance, and a session-summary template.

**Teaching order:** Open with an optional rhetorical *“What do you think?”* hook (no answer required), **show and explain the correct behavior immediately**, demonstrate commands and representative output, interpret expected/unexpected results, **then** ask a separate question to reinforce understanding. For version-related commands, explicitly identify whether the number refers to our management tool, Microsoft's selected SDK, the .NET host, or an application runtime. The questions are not a substitute for instruction.

**Pending owner-output review:** [Review the proposed Windows PowerShell walkthrough and six output placeholders](isolated-dotnet-sdk-session-1-self-paced.md#7-real-windows-powershell-walkthrough--pending-observed-output) before running anything. The capture slots are intentionally empty; no results have been inferred from your computer. Once reviewed, we'll replace them with sanitized actual outputs and line-by-line commentary.

The self-paced lesson owns the technical explanations and canonical answer key. The instructor guide owns the teaching procedure. If there is a factual conflict, current Microsoft documentation and this repository's command/concept contracts take precedence; log the discrepancy rather than inventing a new guarantee.

### Choosing a format

**Reading on your own:** Work through the self-paced lesson, attempt each question before opening its answer, and use linked sections and references to resolve confusion. Exercises do not require installing or changing SDKs; invoking the .NET CLI can still produce normal first-run state or telemetry. A local .NET installation is optional.

**Learning with an AI instructor:** Supply both lesson and instructor guide to the AI presenter (for example, as attached documents), use its opening prompt, and let the instructor pause for each response. Ensure the trainer can actually access the full learner lesson and answer key; merely sending a link may not provide the contents. Voice or text both work. Do not claim that an AI can inspect local machine state or verify learner answers without evidence; paste actual command output when interpretation is needed.

**Evaluating the pilot:** Compare learning outcomes with the same Q1–Q8 checkpoints, independent answers, an integrative diagnostic exercise, and recorded misconceptions. Use the instructor guide's feedback template to propose revisions **before** expanding the training series.

## Future sessions

The next proposed session covers installing and verifying isolated SDKs, including archive integrity, staging, promotion, and the exact-version/origin guarantees. Further sessions may cover runtime selection, removal/recovery, audit, and implementation internals. These are planning ideas, not published lessons or an approved full curriculum.

## Related documentation

- [Documentation home](../README.md)
- [Project and editor use](../guides/project-editor-usage.md)
- [Verify command contract](../commands/verify.md)
- [Project overview](../../README.md)
