# Session 1 — Pilot 2 voice evaluation and retest

**Date:** October 20, 2026  
**Mode:** ChatGPT voice; Windows and PowerShell instructional examples  
**Status:** Observations and revised instructor requirements committed; fresh-run validation still pending.  
**Evidence:** Learner-supplied voice conversation transcript, not a verbatim audio recording.

## Pilot 2 findings (distinct from Pilot 1)

The instructor started Concept 1 (host/executable resolution). The learner objected to questions that required rules not yet taught and to premature assessment after a brief explanation. The lesson was paused, then explicitly replaced by a request to revise repository documentation and restart training in a new chat. No canonical checkpoint was completed or independently scored.

| Observed pattern | What the learner requested | Corrected training behavior |
| --- | --- | --- |
| Asked whether a new SDK install guarantees a new executable before explaining command lookup | Teach outcomes and rules first; test understanding later | Full Concept 1 teaching phase precedes Q1–Q3 |
| Answered “Should I know that by now?” with a request for a best guess | Don't expect preexisting knowledge | Treat unprepared responses as instruction-sequencing defects; explain and demonstrate instead |
| Used “does that make sense?” / “want an example?” as a pause after teaching a rule | Instructor should continue unless a formal checkpoint requires an answer | Give the planned examples without asking permission |
| Asked a full-path-versus-SDK question before demonstrating the distinction | Show contrasting executable and SDK-resolution cases first | Teach, work examples, interpret, consolidate, then assess |
| Immediately asked the learner to restate the preceding explanation | Separate teaching from evidence of learning | Only the canonical scenario-based Q1–Q8 are assessments; do not invent quick checks |
| Stopped at instructional boundaries | Instructor owns progression | Resume automatically after ordinary acknowledgments; stop for explicit learner pauses and checkpoint responses |

**Assessment status:** Q1–Q8 **not assessed**. These findings evaluate instructor delivery, not .NET product functionality or curriculum mastery.

## OpenAI voice guidance review (October 20, 2026)

Sources reviewed:
- [ChatGPT Voice — OpenAI Help Center](https://help.openai.com/en/articles/20001274-chatgpt-voice): Live supports interruptions, typed material alongside audio and spoken pacing requests. Overlapping speech and background noise can affect recognition. Post-conversation transcripts are not guaranteed verbatim.
- [Prompting GPT-Live — OpenAI developer guidance](https://developers.openai.com/api/docs/guides/live-prompting): prefer short conversational instructions, explicit interruption/backchannel policies, and progress updates only when useful. Its session/backend configuration applies to **custom applications** and cannot be assumed controllable by an instructor prompt in consumer ChatGPT.
- [Prompting Realtime models — OpenAI developer guidance](https://developers.openai.com/api/docs/guides/voice-prompting): use short, labeled guidance, clear boundaries, representative sample conversations and iteration based on observed failures.

**Decisions for our curriculum:** Add explicit speaking cadence and interruption/backchannel handling to the instructor guide and its ready-to-use prompt. Deliver short connected explanations **without** inserting check-in pauses. Keep full code and JSON as text, explain spoken meaning before syntax, and avoid reading tables line by line. Don't misinterpret a hesitation during an actual checkpoint as completion; do continue through a teaching-phase pause that is not an explicit user instruction. Avoid repeated “checking” or “thinking” updates. Evaluate transcript evidence cautiously. No changes to ChatGPT app settings, microphone/VAD configuration, or the learner's own machine are implied.

These instructions are a reasoned **application** of product and developer guidance to the Session 1 teaching scenario, not an official OpenAI requirement to teach this particular sequence.

## Fresh pilot acceptance checklist

1. Start a brand-new chat in the Isolated DotNet Sdk project; **retrieve** both Session 1 guides from `docs/206-training-curriculum-session-1`, rather than assuming a link guarantees access.
2. Teach the whole of Concept 1 first: host responsibility, shell precedence/`PATH`, PowerShell `Get-Command`, explicit executable path, SDK selection remaining independent, and `dotnet --version` reporting the selected SDK. Include contrasted worked examples and their interpretation before **Q1**, **Q2** and **Q3**, separately.
3. Verify autonomous teaching through ordinary transitions and “okay,” while respecting actual interruption requests, a genuine explicit pause and the time needed to answer scored questions.
4. Complete Concepts 2 and 3 with their worked examples before Q4–Q5, optional Q6, and Q7–Q8 respectively. Don't presume runtime or SDK facts about the learner's machine.
5. Record each required checkpoint's individual result and any delivery defects as a separate pilot evaluation; leave [PR #207](https://github.com/infoconex/isolated-dotnet-sdk/pull/207) in Draft and unmerged pending owner review.

Related: [Pilot 1](session-1-pilot-1-evaluation.md), [Instructor Guide](isolated-dotnet-sdk-session-1-ai-instructor.md), [Self-Paced Lesson](isolated-dotnet-sdk-session-1-self-paced.md), [Issue #206](https://github.com/infoconex/isolated-dotnet-sdk/issues/206).
