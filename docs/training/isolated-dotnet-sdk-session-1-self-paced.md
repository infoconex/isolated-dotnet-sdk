# Isolated .NET SDK — Session 1: How `dotnet` Is Resolved, and Why Isolation Matters

**Audience:** Developers, technical leads, and maintainers who have used .NET but may not know how a specific SDK is chosen.  
**Format:** Self-paced; an AI instructor is not required.  
**Estimated time:** 30–45 minutes (longer with hands-on exploration).  
**Status:** Curriculum pilot draft v0.1 — October 18, 2026.  
**Companion:** [Session 1 AI Instructor Guide](isolated-dotnet-sdk-session-1-ai-instructor.md).

> **Safety and scope:** All required commands in this lesson are read-only. Do not install/remove SDKs, edit `PATH`, replace `global.json`, or alter your current environment merely to complete Session 1. Any paths and versions in scenarios are illustrative, not claims about what is installed on your machine.

## Why start here?

You might install a newer .NET SDK to evaluate it, only to discover that an unrelated command now uses a different SDK than before. Or you might install an SDK in a separate folder and find that typing `dotnet` doesn't use it. Both outcomes make sense once you separate **which executable runs** from **which SDK that executable selects**.

Our project, [Isolated .NET SDK](https://github.com/infoconex/isolated-dotnet-sdk), helps you install specific SDK versions outside the usual system-wide .NET installation and invoke them intentionally. To understand its value, first understand Microsoft's normal behavior.

### Learning outcomes

By the end, you should be able to:

1. Explain the difference between executable, SDK, and runtime resolution without using those terms interchangeably.
2. Determine which `dotnet` command your shell would invoke and recognize that shell-specific resolution can override `PATH` assumptions.
3. Explain why `dotnet --version` can change even when the executable path does not.
4. Describe how `global.json`, roll-forward policy, installed SDKs, current directory, architecture, and (for .NET 10+) `sdk.paths` can affect SDK selection.
5. Explain why isolated installations don't automatically become the default and what direct executable invocation *does* and *does not* guarantee.
6. Describe the benefit and limits of our tool's isolation model.

## 1. First, three different decisions

When you enter `dotnet --version`, it is tempting to think there's a single step called “find .NET.” There isn't.

| Decision | Question being answered | Influenced by (examples) | Inspect with |
| --- | --- | --- | --- |
| **Executable resolution** | Which `dotnet` or `dotnet.exe` starts? | Shell commands/functions/aliases, `PATH`, explicitly typed path, platform and process environment | PowerShell: `Get-Command dotnet -All`; Bash: `type -a dotnet` |
| **SDK resolution** | Which SDK does that host use for SDK commands? | SDKs visible to that host, nearest applicable `global.json`, roll-forward/prerelease rules, working directory, architecture, .NET 10+ `sdk.paths` | `dotnet --version`, `dotnet --list-sdks`, `dotnet --info` |
| **Runtime resolution** | Which .NET runtime runs a particular app? | Application deployment and runtime configuration, available runtimes, architecture, runtime roll-forward behavior | `dotnet --list-runtimes`; app-specific diagnostics |

**Remember:** `dotnet --version` shows the **selected SDK version**, not the pathname of the executable and not necessarily the runtime that a particular application uses.

Runtime resolution is deliberately a preview only. We'll explore it in another session rather than loading three mechanisms into the first lesson.

### Checkpoint 1 — Explain it in your own words

**Q1.** A colleague says, “`dotnet --version` tells us exactly which `dotnet.exe` Windows ran.” Is that correct? What does that command actually reveal?

Not sure? Revisit the table above, especially the difference between the first and second rows. Compare your answer with [A1](#a1).

## 2. Executable resolution: which program launches?

When you type `dotnet`, **the shell** first decides what that name means. That is not yet an SDK selection decision.

- In ordinary cases, the shell finds an executable through entries on `PATH` in its environment.
- In PowerShell, a command alias or function can take precedence over a native executable; inspect the actual command category and location rather than assuming every match is `dotnet.exe`.
- In Bash, an alias or function may take precedence; shell lookup details (including remembered command locations) can matter. `type -a` helps expose how the shell currently interprets the name.
- An **explicit executable path** removes ambiguity about which file you are asking the shell to launch.
- Your IDE, build task, terminal, and CI runner can each have a different environment or specify an executable path directly. Resolving `dotnet` in your interactive terminal does not prove what another process launches.

### Read-only inspection exercise

Use the command for your terminal. If `dotnet` is not installed or not on `PATH`, that is a valid observation; the exercise still illustrates how discovery works.

**Windows — PowerShell 7**

```powershell
Get-Command dotnet -All | Format-Table CommandType, Name, Source, Definition -AutoSize
where.exe dotnet
```

`Get-Command` shows PowerShell's command candidates, potentially including functions or aliases. `where.exe` searches executable paths; it is a supplementary view, not a substitute for PowerShell's actual command-precedence rules. Neither command changes an installation.

**Linux or macOS — Bash**

```bash
type -a dotnet
command -v dotnet
```

`type -a` is more informative about the shell's interpretation of the command name; `command -v` provides a compact result. They may report a missing command on systems without .NET installed.

**Observe:** What pathname or kind of command is first? Are there multiple candidates? If you have both system and isolated installations, do the isolated folders appear among the candidates? They normally should not unless *you* added them to `PATH`.

### Checkpoint 2

**Q2.** A computer has two `dotnet.exe` files in different directories. Does the newer SDK installation automatically guarantee that its executable is the one launched by `dotnet`? Explain.

**Q3.** Why is an explicit path such as `& "$HOME\dotnet-sdks\10.0.401\dotnet.exe" --version` more predictable than typing `dotnet --version`? What does it *not* guarantee by itself?

Need a hint? Revisit [Section 2](#2-executable-resolution-which-program-launches), then [A2](#a2) and [A3](#a3).

## 3. SDK resolution: which installed SDK is selected?

Once a `dotnet` executable is running and you invoke an SDK-related command, .NET's SDK resolver selects an SDK it can find and that satisfies the active policy.

In a typical terminal invocation:

- Without an applicable `global.json`, the resolver normally selects the highest installed SDK version visible to that host; prerelease visibility depends on the invocation context and related settings.
- With a `global.json`, SDK selection is constrained by the file's version and policy. For the CLI, the search starts in the **current working directory** and walks upward through parent directories.
- A `global.json` version is a full SDK version, e.g. `10.0.401`; it isn't just `10` or `10.0`.
- The `rollForward` policy governs which alternatives are acceptable. `"rollForward": "disable"` means that exact SDK version must be available.
- A different SDK version may be selected — or resolution may fail — without the shell choosing a different executable.

**Important nuance:** The MSBuild project SDK resolver can start its search from a solution/project directory rather than the CLI's current directory. Thus, do not casually generalize every build-related resolver as “always starts where the shell is.”

### A worked example

Assume the shell launched the *same* executable in both cases: `C:\Program Files\dotnet\dotnet.exe`. Assume that host can find SDKs `8.0.408` and `10.0.401`.

| Situation | Illustrative result of `dotnet --version` | Reason |
| --- | --- | --- |
| No applicable `global.json`, prerelease concerns absent | `10.0.401` | Highest visible SDK |
| In a directory with an applicable `global.json` requiring `8.0.408` and `"rollForward": "disable"` | `8.0.408` | Exact project-specific SDK requirement |
| `global.json` requires an unavailable exact version | SDK resolution error | Resolver must not silently substitute an incompatible SDK |

**The executable did not have to change between these cases.** The chosen SDK or the outcome changed.

Here is an **example**, not a file you need to create:

```json
{
  "sdk": {
    "version": "8.0.408",
    "rollForward": "disable"
  }
}
```

### Read-only inspection exercise

Where `dotnet` is available, run:

```text
dotnet --version
dotnet --list-sdks
dotnet --info
```

Look for (a) the selected SDK, (b) visible SDK versions/locations, and (c) any `global.json` information. You may see an SDK in `--list-sdks` that is not selected by `--version`. The commands report facts **from the host that actually ran**; they are not a complete inventory of every SDK folder on your computer.

If you already have two safe working directories — one inside a project with `global.json`, one outside it — you can repeat `dotnet --version` in each and compare results. **Do not create or edit `global.json` just for this exercise.**

### Checkpoint 3

**Q4.** Can `dotnet --version` report different values in two directories even if `Get-Command dotnet` identifies the same executable in both? Why?

**Q5.** A `global.json` specifies `8.0.408` with `"rollForward": "disable"`, but the current host cannot find that SDK. Should .NET pick `10.0.401` anyway? Why or why not?

Need a hint? Revisit [Section 3](#3-sdk-resolution-which-installed-sdk-is-selected), then [A4](#a4) and [A5](#a5).

## 4. Additional influences to recognize, not memorize yet

These factors are worth recognizing when behavior seems unexpected:

| Factor | Why it matters | Depth in this session |
| --- | --- | --- |
| `PATH` and shell command precedence | Changes which executable launches | Core |
| Current working directory and applicable `global.json` | Can change the SDK selected by a host | Core |
| SDK roll-forward rules | Determine whether a newer installed SDK may satisfy a request | Core idea; defer all individual policy variations |
| Prerelease SDK settings | A preview SDK might or might not be considered, depending on context | Awareness |
| Architecture | An x86, x64, or Arm64 host may see different installations | Awareness |
| IDE, process, or CI execution settings | Tools may not use your interactive terminal's chosen executable | Awareness |
| .NET 10+ `global.json` `sdk.paths` | Explicitly changes where SDK resolution searches; it **does not** redirect the shell's executable lookup | Awareness |
| `DOTNET_ROOT` / runtime host environment | Can matter for .NET hosting and controlled operations; it is **not** a PowerShell/Bash command alias or automatic `PATH` change | Awareness; defer detailed behavior |

For .NET 10+ hosts, `global.json` can include an ordered `sdk.paths` list of SDK search locations. This is another reason to avoid teaching the oversimplification that **an explicit host path always guarantees the exact SDK version**. An explicit path guarantees which *host file* you invoke; SDK selection still has its own rules. Our product's Verify operation does more than merely run a host: it checks version and origin in a controlled context.

### Checkpoint 4

**Q6.** Which layer does `sdk.paths` influence: shell executable lookup, SDK selection, or application runtime selection?

Need a hint? Read [Section 4](#4-additional-influences-to-recognize-not-memorize-yet) and [A6](#a6).

## 5. So why have an isolated SDK?

When you install a newer SDK into a conventional shared .NET installation, commands that aren't pinned can begin selecting it. That can change builds or tooling unexpectedly even if you never intended to switch a specific project.

Our [Isolated .NET SDK project](https://github.com/infoconex/isolated-dotnet-sdk) offers another workflow:

1. Install a **specific** SDK into a separate, user-owned folder, conventionally `~/dotnet-sdks/<version>`.
2. Do **not** permanently add that installation to the normal system `PATH`.
3. Invoke its `dotnet` host explicitly when you want to test or work with it.
4. Verify that the intended version and isolated installation origin are actually selected; do not treat an executable pathname or version text alone as complete proof.
5. Leave the regular system SDK installation and normal command resolution alone.

For example, if you **already installed** isolated `10.0.401`, you could inspect it directly:

**PowerShell 7 / Windows**

```powershell
& "$HOME\dotnet-sdks\10.0.401\dotnet.exe" --version
& "$HOME\dotnet-sdks\10.0.401\dotnet.exe" --info
```

**Bash / Linux or macOS**

```bash
"$HOME/dotnet-sdks/10.0.401/dotnet" --version
"$HOME/dotnet-sdks/10.0.401/dotnet" --info
```

Substitute your *actually installed* version; if none is installed, treat the examples as reading material. These commands do not install anything. Their observed SDK selection can still be influenced by SDK-selection policy, including an applicable `global.json`.

**What isolation does not mean:** It is **not** a security sandbox, a guarantee that an application can't write user data, a promise that all editors automatically use the SDK, or proof that a project compiles correctly. The tool separates installation locations and provides controlled installation/verification workflows.

### Checkpoint 5

**Q7.** Why doesn't installing a version into `~/dotnet-sdks/<version>` normally make that version the default when you type `dotnet`?

**Q8.** A Verify command confirms that an isolated SDK has the intended version and origin. What important conclusions **can't** you draw from that success?

Need a hint? Revisit [Section 5](#5-so-why-have-an-isolated-sdk) and the [product Verify contract](../commands/verify.md), then [A7](#a7) and [A8](#a8).

## 6. Integrative challenge: diagnose the right layer

A developer reports this situation:

> “I installed the .NET 10 SDK for experimentation. Yesterday my `dotnet --version` command reported `8.0.408`. Today, from an unrelated directory, it reports `10.0.401`. I thought installing it separately would protect the old default.”

Without changing anything on their computer, explain:

1. What would you inspect to learn which executable the shell launched?
2. What would you inspect to learn which SDK was selected and which SDKs are visible to that host?
3. Which question would you ask about `global.json` and the working directory?
4. What distinction would you make between a conventional system SDK installation and one managed by our isolated SDK tool?

Compare your explanation with [integrative challenge guidance](#integrative-challenge-guidance).

## Answer key and self-check

**Use this after attempting each question.** A useful answer explains *why*, not just yes/no. Exact wording is not required.

### A1

No. `dotnet --version` shows the selected **SDK version** for that invocation. To learn which executable the shell would launch, inspect command resolution in the shell (for example, `Get-Command dotnet -All` or `type -a dotnet`). Also remember that an external editor/task might launch a different file directly.

### A2

No. Installing an SDK is not the same operation as changing how the shell resolves `dotnet`. `PATH`, command precedence, explicit command paths, architecture, and other process-specific details can influence which executable starts. “Newest SDK installed” is more closely related to default **SDK** selection *after a host has started*, subject to visibility and policy.

### A3

A full path identifies the host file you intend to launch, bypassing name-based shell lookup. It **does not by itself guarantee** which SDK an SDK-related command selects or whether the host can find an SDK compatible with `global.json`; and it does not guarantee which runtime a separately launched application uses.

### A4

Yes. The same host can select different SDK versions when the applicable `global.json` or SDK resolution policy differs by working directory. The SDK selection changes; shell executable resolution need not change.

### A5

No. With `"rollForward": "disable"`, the specified exact SDK must be available to that host. A missing required SDK should produce an SDK-resolution failure, not a silent substitution of an unrelated version.

### A6

**SDK selection.** The .NET 10+ `sdk.paths` feature tells supported hosts which SDK search locations to examine when resolving SDK-dependent commands; it doesn't tell the shell which executable to launch and doesn't govern normal app runtime resolution.

### A7

The tool deliberately does not add isolated SDK paths to the normal system `PATH`. Typing `dotnet` uses the shell's usual command resolution. To select the isolated host predictably, invoke its exact path; then consider SDK-selection constraints separately.

### A8

It doesn't demonstrate that your application builds or tests successfully, that the SDK is vulnerability-free, that the installation is a security sandbox, or that editors/other processes will select it by default. Verify checks its documented local installation, host, SDK version, and origin behavior; optional lifecycle/component data is informational and can be unavailable.

### Integrative challenge guidance

A strong answer separates the investigations. Inspect `Get-Command dotnet -All` (PowerShell) or `type -a dotnet` (Bash) for the command being launched; use `dotnet --version`, `dotnet --list-sdks`, and `dotnet --info` to inspect SDK state; check for an applicable `global.json`, directory-specific differences, architecture, and tool-specific invocation. Explain that a conventional shared installation can change default SDK selection, while our isolated installs are placed under a separate user-owned root and do not alter normal `PATH` automatically. Do not assume the original developer's claim proves how the SDK was actually installed.

### Pass criteria

You understand Session 1 if you can, without referring to the answer key:

- State what selects the **executable** and what selects the **SDK**.
- Explain how the **same executable** can produce two different `dotnet --version` results.
- Identify at least two read-only commands for diagnosing resolution on your platform.
- Explain what the isolated tool changes and what it intentionally leaves unchanged.
- Avoid claiming that explicit host selection alone guarantees a particular SDK, or that “isolation” means sandboxing.

If any item is uncertain, return to the linked section and Microsoft/product references below, then try again. Completing every command is not required on machines without .NET installed.

## Authoritative references

**Microsoft (platform behavior)**

- [The `dotnet` command](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet) — particularly `--version`, `--list-sdks`, and `--info`.
- [`global.json` overview](https://learn.microsoft.com/en-us/dotnet/core/tools/global-json) — search starting points, versions, roll-forward, prerelease settings, and .NET 10+ `sdk.paths`.
- [Check installed .NET versions](https://learn.microsoft.com/en-us/dotnet/core/install/how-to-detect-installed-versions) — visibility and inspection commands.
- [Test prerelease SDKs locally using `sdk.paths`](https://learn.microsoft.com/en-us/dotnet/core/tools/test-prerelease-sdk-locally) — optional advanced reading.

**Our product (what the tool does and guarantees)**

- [Project overview](../../README.md) — motivation, installation location, isolation boundaries.
- [Project and editor use](../guides/project-editor-usage.md) — direct host vs SDK selection, `global.json`, IDE limitations.
- [Verify command contract](../commands/verify.md) — actual checks and what Verify does not test.
- [Windows / PowerShell getting started](../getting-started/windows-powershell.md) and [Linux/macOS / Bash getting started](../getting-started/linux-macos-bash.md).

## Coming next

**Session 2 (proposed):** What isolated installation does step by step — download, integrity validation, staging, version/origin verification, promotion, inventory, and safe failure handling. A separate later session will study runtime selection and application execution.

---

*Pilot design note: This lesson deliberately uses stable question IDs Q1–Q8 and answer IDs A1–A8. The instructor guide shares these IDs so we can compare how well learners understand the same concepts with and without AI assistance.*