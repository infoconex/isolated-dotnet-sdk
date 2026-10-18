# Isolated .NET SDK training curriculum

This curriculum builds understanding of Microsoft's normal .NET behavior **before** explaining how Isolated .NET SDK manages SDK installations. Start with the self-paced lesson if you prefer to read independently, or use the same lesson together with the AI instructor guide for voice/text tutoring.

## Session 1 — How `dotnet` is resolved, and why isolation matters

**Status:** Pilot draft; ready for learner review, not yet pedagogically validated. **Estimated learner time:** 30–45 minutes for the self-paced lesson.

- **[Self-paced Session 1](isolated-dotnet-sdk-session-1-self-paced.md):** Definitions, practical read-only inspections, Q1–Q8 checkpoints, answer key, and a troubleshooting-style scenario. No AI required.
- **[Session 1 AI instructor guide](isolated-dotnet-sdk-session-1-ai-instructor.md):** Copy-ready teaching prompt, one-question-at-a-time sequence, matching Q1–Q8 hint/evaluation guidance, and a session-summary template.

The self-paced lesson owns the technical explanations and canonical answer key. The instructor guide owns the teaching procedure. If there is a factual conflict, current Microsoft documentation and this repository's command/concept contracts take precedence; log the discrepancy rather than inventing a new guarantee.

### Choosing a format

**Reading on your own:** Work through the self-paced lesson, attempt each question before opening its answer, and use linked sections and references to resolve confusion. Exercises are deliberately read-only; a local .NET installation is optional.

**Learning with an AI instructor:** Supply both lesson and instructor guide to the AI presenter (for example, as attached documents), use its opening prompt, and let the instructor pause for each response. Voice or text both work. Do not claim that an AI can inspect local machine state or verify learner answers without evidence; paste actual command output when interpretation is needed.

**Evaluating the pilot:** Compare learning outcomes with the same Q1–Q8 checkpoints, independent answers, an integrative diagnostic exercise, and recorded misconceptions. Use the instructor guide's feedback template to propose revisions **before** expanding the training series.

## Future sessions

The next proposed session covers installing and verifying isolated SDKs, including archive integrity, staging, promotion, and the exact-version/origin guarantees. Further sessions may cover runtime selection, removal/recovery, audit, and implementation internals. These are planning ideas, not published lessons or an approved full curriculum.

## Related documentation

- [Documentation home](../README.md)
- [Project and editor use](../guides/project-editor-usage.md)
- [Verify command contract](../commands/verify.md)
- [Project overview](../../README.md)
