# Draft — Session 1: Try it yourself on your .NET installation

> **Draft for owner review — NOT included in the Session 1 pilot yet.**
>
> **Proposed placement:** An optional follow-on activity after the learner has worked through Concepts 1–3 and checked Q1–Q8 against their answers. No new required checkpoint or pass criterion. Expected time: about 5–10 minutes if .NET is already installed.
>
> **Scope:** Apply the three decisions already taught; do not teach the commands again or expect a specific version number. Learners may skip this activity or use the examples in the [main lesson](isolated-dotnet-sdk-session-1-self-paced.md) instead.

## Try it yourself: Which .NET components does your computer use?

The lesson distinguished **(1) which executable starts**, **(2) which SDK is selected**, and **(3) which runtime a framework-dependent application requests and uses**. Now gather a few observations from your own environment and decide what they do—and do not—establish.

This is an optional inspection exercise. Do not install, uninstall, configure or build anything for it. If a command fails or .NET is not installed, that's a valid finding, not a reason to change your computer. Some .NET CLI invocations can create normal first-run state or send telemetry according to [Microsoft's documented settings](https://learn.microsoft.com/en-us/dotnet/core/tools/telemetry).

**Use the terminal you normally develop in.** If you share your findings with an instructor, remove personal usernames, project paths and other private information first.

### 1. Find the executable your shell resolves

**Windows / PowerShell:**

\`\`\`powershell
Get-Command dotnet -All | Select-Object CommandType, Name, Source, Definition
\`\`\`

**Linux or macOS / Bash:**

\`\`\`bash
type -a dotnet
\`\`\`

**Record and interpret:**

- What does the shell find first? Is it a native application, alias, function or something else?
- If multiple executable candidates appear, can you explain which one the *current shell* would invoke?
- What can this inspection **not** establish about hosts that might exist elsewhere on disk or commands launched by an IDE?

If the shell can't find \`dotnet\`, record that result. You do not need to install anything. Continue by reasoning from the [worked example in Concept 1](isolated-dotnet-sdk-session-1-self-paced.md#worked-example-resolving-dotnet-on-windows).

**Optional comparison:** If your command actually resolves a native \`dotnet\` executable, you can invoke *that file* by its full path with \`--version\`. This tests explicit executable selection, not whether it must use an exact SDK. Use the path you observed, not a path copied from this lesson.

### 2. See which SDK the host selects

If \`dotnet\` is available, run:

\`\`\`text
dotnet --version
dotnet --list-sdks
dotnet --info
\`\`\`

**Record and interpret:**

- Which SDK, if any, is selected by \`dotnet --version\` in this working directory?
- Which SDKs are listed as available to this host? Is the selected one among them?
- What do the relevant \`Host\` and SDK \`Base Path\` fields in \`dotnet --info\` report? Are these the same kind of version or location?
- Does the output establish which SDK a command run from *another directory* would select? Why not?

If SDK selection fails, inspect any reported \`global.json\` constraint and distinguish a **resolution failure** from "no .NET components are installed." Do not change the file to make the example work.

**Optional comparison:** Only if you already have safe directories with different applicable \`global.json\` conditions, compare \`dotnet --version\` from those directories. The host might stay the same while SDK selection changes. Don't create or edit project files for this exercise.

### 3. Identify runtimes the host can see

If \`dotnet\` is available, run:

\`\`\`text
dotnet --list-runtimes
\`\`\`

**Record and interpret:**

- Which shared-framework families and versions are visible? For example, do you see \`Microsoft.NETCore.App\` or \`Microsoft.AspNetCore.App\`?
- Are there runtime versions for which you don't see a corresponding SDK version? Would that necessarily be a problem?
- Can this output tell you which runtime a particular application **actually loaded**?

**Important boundary:** \`dotnet --list-runtimes\` shows an inventory. It does *not* establish app-specific runtime selection. To investigate that, you'd need a particular application's runtime requirements, launch context, effective policy, and evidence of what executed. No application launch is required in this activity.

### Your findings

Use these prompts as informal notes; there is no expected set of numbers to match.

| Question | My observation | What it establishes / does not establish |
| --- | --- | --- |
| Which \`dotnet\` command does my shell resolve? | | |
| Which SDK is selected in my current directory? | | |
| Which SDK versions are visible to the host? | | |
| What host version and SDK base path are reported? | | |
| Which runtime frameworks are visible? | | |
| Which runtime did a particular app load? | **Not measured in this activity** | Runtime inventory alone cannot answer this |

**Wrap-up:** Explain in your own words which findings are about the **executable**, which are about the **SDK**, and which are only about **available runtimes**. If two version numbers differ, identify the components before deciding whether there is a problem. For explanations, revisit [Concept 1](isolated-dotnet-sdk-session-1-self-paced.md#concept-1-understanding-the-net-host), [Concept 2](isolated-dotnet-sdk-session-1-self-paced.md#concept-2-understanding-how-net-selects-an-sdk), or [Concept 3](isolated-dotnet-sdk-session-1-self-paced.md#concept-3-understanding-application-runtime-selection).

---

## Integration notes — for curriculum review, not learner instructions

- **Avoid duplication:** If this activity is adopted, consider removing or shortening the current Concept 1 "Optional shell inspection exercise" and Concept 2 "Optional inspection exercise." Keep the explanatory worked examples; the activity should be the one coherent opportunity to inspect the learner's own environment.
- **Do not add required checkpoints.** Q1–Q8 and A1–A8 remain the assessed learning sequence. The AI instructor may offer this activity *after* teaching/assessment, ask the learner to share sanitized output, and help interpret it without pretending to inspect their machine.
- **Keep the archive independent:** [Windows installation observations](windows-dotnet-installation-observations.md) remain preserved source data. Their current organization is not endorsed as a teaching case study. Do not make the learner match the owner's machine.
- **Unfilled evidence gap (not required for this activity):** The owner supplied executable, SDK-selection and runtime-*inventory* evidence, but no captured launch proving which shared runtime a **particular application** loaded. If an optional future exercise should demonstrate actual runtime selection, first design a tiny harmless framework-dependent test app and capture its \`runtimeconfig.json\`, observed launch, and a trustworthy app-reported/runtime-host-traced runtime version. Keep that extension separate from the 5–10 minute inspection activity. Do not infer loaded runtime from \`--list-runtimes\`.
- **Review questions:** Does this produce new applied learning rather than repeat commands? Is it useful for people who have no SDK or only a runtime installed? Does it fit both PowerShell and Bash? Is the distinction between the reported \`Host\` version and the executable's Windows File Version clear enough? Decide the final placement only after reviewing the draft.
