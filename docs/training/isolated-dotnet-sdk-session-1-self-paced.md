# Isolated .NET SDK — Session 1: How `dotnet` Is Resolved, and Why Isolation Matters

**Audience:** Developers, technical leads, and maintainers who have used .NET but may not know how a specific SDK is chosen.  
**Format:** Self-paced; an AI instructor is not required.  
**Estimated time:** 60–90 minutes for the expanded lesson (longer when exploring your own machine); sections can be studied separately.  
**Status:** Curriculum pilot draft v0.5 — October 18, 2026; glossary and observed .NET installation structure now precede Section 1.  
**Companion:** [Session 1 AI Instructor Guide](isolated-dotnet-sdk-session-1-ai-instructor.md).

> **Safety and scope:** The exercises inspect command resolution and SDK information; they do not ask you to install/remove SDKs, build a project, edit `PATH`, replace `global.json`, or change your project. Running the .NET CLI can still create ordinary per-user first-run state or produce telemetry under Microsoft's settings; “inspection” does **not** mean zero side effects. You may skip all live commands and use the hypothetical examples instead. Early worked scenarios are illustrative. A separately labeled owner-supplied Windows walkthrough and the opening folder-layout examples contain observed data from provided screenshots and terminal output; they are not claims about your machine. See [Microsoft's CLI telemetry documentation](https://learn.microsoft.com/en-us/dotnet/core/tools/telemetry).

## Why start here?

You might install a newer .NET SDK to evaluate it, only to discover that an unrelated command now uses a different SDK than before. Or you might install an SDK in a separate folder and find that typing `dotnet` doesn't use it. Both outcomes make sense once you separate **which executable runs** from **which SDK that executable selects**.

Our project, [Isolated .NET SDK](https://github.com/infoconex/isolated-dotnet-sdk), helps you install specific SDK versions outside the usual system-wide .NET installation and invoke them intentionally. To understand its value, first understand Microsoft's normal behavior.

### How to study this lesson

For each section, start with the **curiosity question** as something to think about; it is **not a quiz and does not require an answer**. Read the explanation, work through the example command and output, and study what unexpected results mean. **Only after that** answer the numbered checkpoint questions before looking at the matching A-numbered answers. Explain *why* you chose each answer. If uncertain, follow the section hint, try again, and then compare with the answer key. You can mark each checkpoint **independent**, **after hint**, or **after reading the explanation**. The goal is an accurate explanation, not a perfect first guess. You do not need a local .NET installation to complete the lesson.

### Learning outcomes

By the end, you should be able to:

1. Explain **what the host, SDK, and runtime do**, when each is involved, why their version numbers differ, and how their separate resolution decisions work.
2. Determine which `dotnet` command your shell would invoke and recognize that shell-specific resolution can override `PATH` assumptions.
3. Explain why `dotnet --version` can change even when the executable path does not.
4. Describe how `global.json`, roll-forward policy, installed SDKs, current directory, architecture, and (for .NET 10+) `sdk.paths` can affect SDK selection.
5. Explain why isolated installations don't automatically become the default and what direct executable invocation *does* and *does not* guarantee.
6. Describe the benefit and limits of our tool's isolation model.

## Before Section 1: Components and folders

We will distinguish **a program you execute**, **the developer tools it may select**, **the components that run apps**, and **metadata used by optional development workloads**. Understanding what each one *is* will make the later resolution rules much easier to follow.

Before we discuss *resolution*, here are the terms we'll use:

| Term | Plain-language meaning |
| --- | --- |
| **`dotnet` executable / host** | The actual program (`dotnet.exe` on Windows, `dotnet` on Linux/macOS) that starts when you run a .NET CLI command. A *host* is not the same as an SDK version. |
| **SDK** | Software Development Kit: the .NET tools needed to build, test, and publish software. Different SDK versions may coexist. |
| **Runtime** | The components needed to execute a .NET application. An app's runtime selection is different from selecting an SDK to build it. |
| **Resolution** | The process of deciding which executable, SDK, or runtime to use. The answer depends on *which one* is being resolved. |
| **`PATH`** | A list of directories consulted when locating commands by name. Shell aliases/functions and explicit paths can take precedence. |
| **`global.json`** | An optional file that tells .NET which SDK version or range of SDK versions to accept. It does not rename or redirect the shell's `dotnet` command. |
| **Roll-forward** | The rules controlling whether a different installed version is an acceptable substitute for a requested version. |

Three extra terms help us interpret actual .NET installation folders:

| Additional term | Plain-language meaning |
| --- | --- |
| **`hostfxr` (host framework resolver)** | A native .NET hosting component stored under `host/fxr`. It helps resolve SDKs and shared runtimes after a `dotnet` host starts. It is **not** an SDK, not an app runtime, and not another `dotnet.exe` for every folder. |
| **SDK feature band** | A grouping of related SDK releases, reflected in versions such as `10.0.400` (the feature band for SDK `10.0.402`). Feature-band names can appear in workload-related metadata; they are **not** a list of installed SDK patch versions. |
| **Workload / workload manifest** | An optional development capability (such as platform-specific tooling), and metadata describing the assets needed for those workloads. A manifest folder alone **does not** mean a workload is installed. |

### A real Windows installation: three folders that look similar but mean different things

The project owner supplied **three File Explorer screenshots** of the x64 system .NET installation under `C:\Program Files\dotnet`. The folder names below are **transcribed from those screenshots**, not inferred from SDK version strings. They show one observed machine; Linux/macOS layouts and other Windows installations may differ.

```text
C:\Program Files\dotnet\
  dotnet.exe            <-- CLI host executable (shown separately in its Properties screenshot)
  host\
    fxr\
      6.0.36
      7.0.20
      8.0.32
      9.0.21
      10.0.12
      10.0.13
  sdk\
    8.0.426
    9.0.319
    10.0.401
    10.0.402
  sdk-manifests\
    8.0.100
    9.0.100
    10.0.100
  shared\                <-- runtime frameworks (studied in Section 7)
```

**First, look at `host\fxr`.** Each numbered folder contains a version of the **host framework resolver** (`hostfxr`), which participates in choosing compatible .NET components. The folders **6.0.36**, **7.0.20**, **8.0.32**, **9.0.21**, **10.0.12**, and **10.0.13** do **not** mean six different SDKs are installed or that every application loads all six hostfxr versions. Microsoft's host typically selects an appropriate hosting component during startup. The screenshot itself **does not prove which hostfxr DLL was loaded by a particular process**.

**Next, look at `sdk`.** These four directories are the actual installed **SDK versions**: **8.0.426**, **9.0.319**, **10.0.401**, and **10.0.402**. Compare them with the owner's later `dotnet --list-sdks` result in [Section 7](#7-real-windows-powershell-walkthrough): all four appear there. An SDK directory is a collection of build/development tooling, not another hostfxr version or a shared application runtime.

**Finally, look at `sdk-manifests`.** Its folders **8.0.100**, **9.0.100**, and **10.0.100** belong to **workload manifest feature-band metadata**, not the installed-SDK inventory. **SDK 10.0.100 does not appear in `sdk` or `dotnet --list-sdks`**, even though `sdk-manifests\10.0.100` exists. Conversely, SDK **10.0.402** is installed even though the screenshot does not show a folder named `sdk-manifests\10.0.402`. **The two directory trees do not have a one-to-one relationship.**

The owner's actual `dotnet --info` output also reports:

```text
.NET SDK:
 Version:           10.0.402
 Workload version:  10.0.400-manifests.378ba522

.NET workloads installed:
There are no installed workloads to display.
```

**Interpretation:** `10.0.402` is the selected SDK; `10.0.400-manifests.378ba522` is workload-manifest-related version information associated with the SDK's feature band; and **no installed workloads were reported**. A directory's existence under `sdk-manifests` is not a substitute for an installed-workload check. This also explains why a `10.0.100` manifest directory should never be treated as proof of an installed `10.0.100` SDK.

**Optional, non-installing Windows PowerShell inspection** of these folder names (not executed by us; no PowerShell output is claimed):

```powershell
Get-ChildItem 'C:\Program Files\dotnet\host\fxr' -Directory | Select-Object -ExpandProperty Name
Get-ChildItem 'C:\Program Files\dotnet\sdk' -Directory | Select-Object -ExpandProperty Name
Get-ChildItem 'C:\Program Files\dotnet\sdk-manifests' -Directory | Select-Object -ExpandProperty Name
```

**What if your results differ?** An SDK might be installed somewhere else, your shell may launch another `dotnet` host, an x86/Arm64 installation may have a different inventory, or SDK/tooling components may have been updated independently. Folder modified dates alone don't prove which installer added or last used each component. Do not delete folders to try to make these lists match.

Microsoft documents the directory roles in [.NET distribution packaging](https://learn.microsoft.com/en-us/dotnet/core/distribution-packaging) and explains the difference between installed workloads and manifest metadata in [`dotnet workload list`](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-workload-list). The product will **not** ask you to install workloads during Session 1.

---

## 1. First, three different decisions

**Think about this:** When you enter `dotnet --version`, what do you expect the number to describe — the executable, the runtime, or the SDK? You don't have to answer yet. The command and output below will explain it.

When you enter `dotnet --version`, it is tempting to think there's a single step called “find .NET.” There isn't.

| Decision | Question being answered | Influenced by (examples) | Inspect with |
| --- | --- | --- | --- |
| **Executable resolution** | Which `dotnet` or `dotnet.exe` starts? | Shell commands/functions/aliases, `PATH`, explicitly typed path, platform and process environment | PowerShell: `Get-Command dotnet -All`; Bash: `type -a dotnet` |
| **SDK resolution** | Which SDK does that host use for SDK commands? | SDKs visible to that host, nearest applicable `global.json`, roll-forward/prerelease rules, working directory, architecture, .NET 10+ `sdk.paths` | `dotnet --version`, `dotnet --list-sdks`, `dotnet --info` |
| **Runtime resolution** | Which .NET runtime runs a particular app? | Application deployment and runtime configuration, available runtimes, architecture, runtime roll-forward behavior | `dotnet --list-runtimes`; app-specific diagnostics |

Runtime resolution is deliberately a preview only. We'll explore it in another session rather than loading three mechanisms into the first lesson. The worked example below shows which number `dotnet --version` actually prints.

### Worked example: what actually happens when you type a command?

Imagine a Windows PowerShell terminal. The machine has Microsoft .NET SDKs `8.0.408` and `10.0.401` installed under its usual shared .NET installation. **You might expect the command to report the executable or runtime version; watch what actually appears.**

You type:

```powershell
dotnet --version
```

The system makes **two decisions in sequence**:

1. **PowerShell finds a command named `dotnet`.** In our example, it launches `C:\Program Files\dotnet\dotnet.exe`. This identifies the *executable* and is influenced by the shell's lookup rules.
2. **That executable selects an SDK.** Assume there is no applicable `global.json` and both SDKs are discoverable. It chooses `10.0.401`, the highest installed SDK, and prints:

```text
10.0.401
```

**Answer to the opening question:** `10.0.401` is the **selected SDK version**. It is neither the executable's pathname nor the .NET runtime version. The host (`dotnet.exe`) is the program PowerShell launches; the SDK is the toolkit that host selects. The command does not print `C:\Program Files\dotnet\dotnet.exe` because `--version` answers the SDK-selection question, not which executable file PowerShell found.

When the command is `dotnet my-app.dll` instead, the runtime hosting rules matter. That operation may not select an SDK at all. We will examine runtime selection separately.

**Why this matters:** The same word, “dotnet,” names a host program that can launch different kinds of operations. Before troubleshooting, ask: *am I trying to identify the executable, the SDK selected for build commands, or the runtime used to run an app?*

**This first worked example is illustrative.** The earlier folder layout is transcribed from the owner's screenshots; the separate [Windows walkthrough](#7-real-windows-powershell-walkthrough) contains sanitized owner-provided CLI observations. Actual paths and versions differ across computers.

### A closer look: what are the host, SDK, and runtime actually responsible for?

These aren't merely three names for “.NET.” They are **different parts of the system doing different jobs**.

**1. The host — the program that gets things started.** On Windows this is typically an executable named `dotnet.exe`; on Linux/macOS it is `dotnet`. For a command such as `dotnet build`, the host launches the selected SDK tooling. For a command such as `dotnet MyApp.dll`, it starts a .NET application through the appropriate runtime-hosting machinery. It is useful to picture the host as the **entry point and dispatcher**, rather than as your application's execution engine or the set of build tools.

The name **host** is sometimes used for related .NET startup components, such as `hostfxr`, which helps resolve and start the required .NET components. This lesson will call the executable you invoke the **`dotnet` host** and treat the `Host` section of `dotnet --info` as information about its hosting components. It is **not** a command that prints the executable's full path or a promise that every app will run on that Host-version number.

**2. The SDK — tools for developing software.** SDK stands for *Software Development Kit*. It contains developer-oriented tools: the CLI, build integration, compilers, publishing/packaging support, and related assets. When you run `dotnet build`, `dotnet test`, or `dotnet publish`, an SDK is involved. SDK versions have their own numbering: `10.0.401` is an SDK version, not a runtime version.

**3. The runtime — components that execute an already-built application.** The .NET runtime includes execution infrastructure such as the Common Language Runtime (CoreCLR), garbage collection, and framework libraries. A framework-dependent `net8.0` application typically needs a compatible .NET 8 runtime to **run**, even if it was **built with** the .NET 10 SDK. Web apps may also require the ASP.NET Core shared framework. A runtime can be installed **without** an SDK; a machine that only runs .NET apps may have no development tools at all.

Think of the overall relationship like this:

```text
You enter a command in PowerShell or Bash
                  |
            shell finds a host
       (e.g. dotnet.exe file on PATH)
                  |
         +--------+---------+
         |                  |
   dotnet build          dotnet MyApp.dll
         |                  |
   SDK resolution        app/runtime resolution
         |                  |
   SDK build tools       compatible runtime
         |                  |
   creates/updates       executes the app
   build artifacts
```

The two paths serve different purposes. The left path is about **developing** an application; the right is about **running** an application. An SDK often includes a runtime too, but that doesn't merge their jobs or version numbers.

### One machine can report three different versions

Now compare these three commands on a *hypothetical* Windows installation. No files need to be created.

```powershell
dotnet --version
dotnet --info
dotnet --list-runtimes
```

Illustrative, **abbreviated** output:

```text
> dotnet --version
10.0.401

> dotnet --info
.NET SDK:
 Version:           10.0.401
 Base Path:         C:\Program Files\dotnet\sdk\10.0.401\

Host:
 Version:           10.0.5
 Architecture:      x64

> dotnet --list-runtimes
Microsoft.NETCore.App 8.0.15 [C:\Program Files\dotnet\shared\Microsoft.NETCore.App]
Microsoft.NETCore.App 10.0.5 [C:\Program Files\dotnet\shared\Microsoft.NETCore.App]
```

**Interpretation, line by line:**

- `--version` prints `10.0.401` because that is the **SDK selected for this invocation**. It does not mean a 10.0.401 runtime exists.
- `.NET SDK: Version` repeats the selected SDK. `Base Path` tells us where that particular SDK's files are installed.
- `Host: Version` is `10.0.5`. This is a **host-component version** reported by .NET, different from the selected SDK version and not the executable pathname.
- `--list-runtimes` reports **two installed .NET runtime versions** at their locations. It is an inventory, not a decision about which runtime an arbitrary application will use.

**Why aren't the numbers the same?** SDK version numbers identify development-tool releases; host/runtime version numbers identify their own component releases. There is no rule that says `10.0.401` must equal `10.0.5` or `8.0.15`. The output is useful precisely because it separates these concepts.

**If the output differs:** There may be more than one architecture or install root, and the version selected may be constrained by `global.json`. `dotnet --info` is not the same as an inventory of every host binary on disk. If `dotnet --version` cannot find an SDK on a runtime-only machine, that does *not* automatically mean the machine is unable to run a compatible already-built .NET app.

We'll revisit SDK selection in Section 3 and how an application chooses a runtime in Section 5. Microsoft's guidance explicitly treats [SDK selection](https://learn.microsoft.com/en-us/dotnet/core/tools/global-json) and [runtime/version selection](https://learn.microsoft.com/en-us/dotnet/core/versions/selection) as separate concerns.

### A version question needs a subject: tool, SDK, host, or runtime

Now apply the distinction to **our own Isolated .NET SDK management tool**. Our tool has its **own release version**. That number is separate from the version of any Microsoft .NET SDK it installs or verifies.

**Windows / PowerShell 7** — suppose the saved management tool is release `v0.4.0` and SDK `10.0.401` is selected by the normal system host:

```powershell
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1" -Version
dotnet --version
dotnet --info
```

Illustrative, abbreviated output (these are separate invocations):

```text
> isolated-dotnet-sdk.ps1 -Version
Isolated .NET SDK v0.4.0

> dotnet --version
10.0.401

> dotnet --info
.NET SDK:
 Version:           10.0.401

Host:
 Version:           10.0.5
```

**What each line tells you:**

- **`Isolated .NET SDK v0.4.0`** is the release of **our management script**. PowerShell uses its `-Version` parameter to ask the script for its own identity. It does **not** identify an installed Microsoft SDK.
- **`10.0.401`** is the **Microsoft SDK selected by the `dotnet` CLI**. That is what Microsoft's `dotnet --version` means.
- **`Host: Version: 10.0.5`** is the reported .NET hosting component version, not the management script version or the selected SDK version.
- An **application's runtime** has yet another resolution decision; inspect installed runtimes with `dotnet --list-runtimes` and its runtime configuration when investigating a specific application.

**Linux/macOS / Bash:** The management tool's own version switch is `--version` (rather than PowerShell's `-Version`):

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" --version
dotnet --version
```

Illustrative output for the same assumed tool/SDK versions:

```text
Isolated .NET SDK v0.4.0
10.0.401
```

**Notice:** Both Bash commands contain `--version`, but they call **different programs**. One reports the *tool release*, while the other reports the *SDK selected by the Microsoft CLI*. The flag's spelling does not determine what the number represents; **the program receiving the flag does**.

**If the numbers differ from these examples:** That is normal. Our script may be a newer release than the example; a different SDK may be selected because of `global.json`; and another installation may report a different Host version. Investigate **which program was called**, **which SDK is selected**, and **which runtime a particular app needs** before comparing version numbers.

The exact product command syntax is also documented in the [Windows](../getting-started/windows-powershell.md#identify-the-tool-version) and [Bash](../getting-started/linux-macos-bash.md#identify-the-tool-version) getting-started guides. All outputs in this section are illustrative and do not imply you have those versions installed.

### Checkpoint 1 — Explain it in your own words

**Q1.** A colleague says, “`dotnet --version` tells us exactly which `dotnet.exe` Windows ran, or which runtime all apps will use.” After seeing the worked outputs, how would you correct that statement? Include what the host, SDK, and runtime each do.

Not sure? Revisit the table above, especially the difference between the first and second rows. Compare your answer with [A1](#a1).

## 2. Executable resolution: which program launches?

**Think about this:** If there are two `dotnet.exe` files on your machine, how does PowerShell decide which one to run? No need to guess; we'll use command output to show you.

When you type `dotnet`, **the shell** first decides what that name means. That is not yet an SDK selection decision.

- In ordinary cases, the shell finds an executable through entries on `PATH` in its environment.
- In PowerShell, a command alias or function can take precedence over a native executable; inspect the actual command category and location rather than assuming every match is `dotnet.exe`.
- In Bash, an alias or function may take precedence; shell lookup details (including remembered command locations) can matter. `type -a` helps expose how the shell currently interprets the name.
- An **explicit executable path** removes ambiguity about which file you are asking the shell to launch.
- Your IDE, build task, terminal, and CI runner can each have a different environment or specify an executable path directly. Resolving `dotnet` in your interactive terminal does not prove what another process launches.

### Optional shell inspection exercise

Use the command for your terminal. If `dotnet` is not installed or not on `PATH`, that is a valid observation; the exercise still illustrates how discovery works.

**Windows — PowerShell 7**

```powershell
Get-Command dotnet -All | Format-Table CommandType, Name, Source, Definition -AutoSize
where.exe dotnet
```

`Get-Command` shows PowerShell's command candidates, potentially including functions or aliases. `where.exe` searches executable paths; it is a supplementary view, not a substitute for PowerShell's actual command-precedence rules. Neither command installs or removes an SDK.

**Linux or macOS — Bash**

```bash
type -a dotnet
command -v dotnet
```

`type -a` is more informative about the shell's interpretation of the command name; `command -v` provides a compact result. They may report a missing command on systems without .NET installed.

**Observe:** What pathname or kind of command is first? Are there multiple candidates? If you have both system and isolated installations, do the isolated folders appear among the candidates? They normally should not unless *you* added them to `PATH`.

### Worked example: resolving `dotnet` on Windows

Assume your machine has two directories containing a file named `dotnet.exe` and that PowerShell has no alias or function named `dotnet`.

```powershell
Get-Command dotnet -All | Select-Object CommandType, Name, Source
```

Illustrative output:

```text
CommandType  Name        Source
-----------  ----        ------
Application  dotnet.exe  C:\Program Files\dotnet\dotnet.exe
Application  dotnet.exe  C:\Tools\dotnet\dotnet.exe
```

**Read it row by row.** `Application` means PowerShell found a native executable; `Source` identifies its file location. Here the first matching executable comes from `C:\Program Files\dotnet`. The second is another candidate — *not* another SDK version inside the first installation.

To inspect executable candidates on the Windows executable search path, compare:

```powershell
where.exe dotnet
```

Illustrative output:

```text
C:\Program Files\dotnet\dotnet.exe
C:\Tools\dotnet\dotnet.exe
```

**Why might these disagree?** `where.exe` searches executable path locations; PowerShell also resolves aliases and functions. For instance, if someone defined a function called `dotnet`, `Get-Command dotnet -All` could show a `Function` first even though `where.exe dotnet` lists only executable files. That is why the *shell's command lookup* is the primary question.

### The equivalent example in Bash (Linux or macOS)

```bash
type -a dotnet
command -v dotnet
```

Illustrative output on a Linux machine:

```text
dotnet is /usr/share/dotnet/dotnet
dotnet is /opt/dotnet/dotnet
/usr/share/dotnet/dotnet
```

The two `type -a` lines list ways the name can be found; `command -v` reports the current command interpretation compactly. The first executable is under `/usr/share/dotnet`. A Bash function or alias can change what a bare `dotnet` means, so don't assume that this is always a filesystem-only lookup.

### If the result is surprising

- **Command not found:** No usable command named `dotnet` was resolved by that shell. It does **not** prove there is no SDK anywhere on disk; an isolated host might exist outside `PATH`.
- **Multiple paths:** Multiple possible *executables* exist. This is not the same as multiple *SDKs*. You need `dotnet --list-sdks` for the SDKs visible to a particular host.
- **An alias/function appears:** Inspect its definition before inferring the actual executable. An editor or CI job may resolve something else because it has a different environment.
- **An executable path looks unfamiliar:** Check which process or shell you are in, whether `PATH` was modified, and whether you are using x86/x64/Arm64 tooling. Do not change your system just to make the exercise match the example.

**One certainty you can introduce deliberately:** To choose a particular installed host file, use its full path, such as `& "$HOME\dotnet-sdks\10.0.401\dotnet.exe" --version` in PowerShell or `"$HOME/dotnet-sdks/10.0.401/dotnet" --version` in Bash. The host file is then explicit; the version the SDK resolver reports is still a separate matter.

### Checkpoint 2

**Q2.** A computer has two `dotnet.exe` files in different directories. Does the newer SDK installation automatically guarantee that its executable is the one launched by `dotnet`? Explain.

**Q3.** Why is an explicit path such as `& "$HOME\dotnet-sdks\10.0.401\dotnet.exe" --version` more predictable than typing `dotnet --version`? What does it *not* guarantee by itself?

Need a hint? Revisit [Section 2](#2-executable-resolution-which-program-launches), then [A2](#a2) and [A3](#a3).

## 3. SDK resolution: which installed SDK is selected?

**Think about this:** Could the same `dotnet.exe` print `10.0.401` in one directory and `8.0.408` in another? The examples in this section explain how that happens.

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

### Optional inspection exercise

Where `dotnet` is available, you may run these diagnostics (subject to the first-run/telemetry note at the top):

```text
dotnet --version
dotnet --list-sdks
dotnet --info
```

Look for (a) the selected SDK, (b) visible SDK versions/locations, and (c) any `global.json` information. You may see an SDK in `--list-sdks` that is not selected by `--version`. The commands report facts **from the host that actually ran**; they are not a complete inventory of every SDK folder on your computer.

If you already have two safe working directories — one inside a project with `global.json`, one outside it — you can repeat `dotnet --version` in each and compare results. **Do not create or edit `global.json` just for this exercise.**

### Worked example: the **same executable**, two SDK results

Assume PowerShell resolves `dotnet` to exactly the same host file in both directories:

```text
C:\Program Files\dotnet\dotnet.exe
```

Assume the host discovers these two SDK installations:

```powershell
dotnet --list-sdks
```

Illustrative output:

```text
8.0.408 [C:\Program Files\dotnet\sdk]
10.0.401 [C:\Program Files\dotnet\sdk]
```

**How to read it:** each row contains an *installed SDK version* followed by the directory containing the SDK version subfolders. It is an inventory from the running host, **not** proof that both SDKs will be selected automatically and **not** a list of all SDKs on the entire disk. In this example, the SDKs live under `C:\Program Files\dotnet\sdk\8.0.408` and `C:\Program Files\dotnet\sdk\10.0.401`.

From a folder with no applicable `global.json`:

```powershell
PS C:\work\scratch> dotnet --version
10.0.401
```

Now consider a different folder containing this **existing example** file at `C:\work\legacy\global.json`:

```json
{
  "sdk": {
    "version": "8.0.408",
    "rollForward": "disable"
  }
}
```

From inside that folder:

```powershell
PS C:\work\legacy> dotnet --version
8.0.408
```

**Why the change?** For CLI SDK commands, .NET looks for `global.json` starting in the current working directory and then its parent directories. In `C:\work\scratch` it found no applicable pin, so it chose the newest visible SDK. In `C:\work\legacy` it found an exact-version requirement and selected `8.0.408`. **The shell still executed the same `dotnet.exe` file.** No system-wide uninstall, reinstall, or change to `PATH` was required to explain the difference.

### A closer look using `dotnet --info`

```powershell
dotnet --info
```

Illustrative **abbreviated** output from the legacy folder (other fields omitted):

```text
.NET SDK:
 Version:           8.0.408
 Base Path:         C:\Program Files\dotnet\sdk\8.0.408\

Host:
 Version:           10.0.5

.NET SDKs installed:
  8.0.408 [C:\Program Files\dotnet\sdk]
  10.0.401 [C:\Program Files\dotnet\sdk]
```

Read each part separately:

- **`.NET SDK Version`:** `8.0.408` is the selected SDK for this invocation.
- **`Base Path`:** where the selected SDK's files live; here it agrees with the `8.0.408` installation.
- **`Host Version`:** `10.0.5` illustrates an independent host/runtime component version. It is **not** the SDK version and should not be assumed equal to it. Actual host versions vary by installation.
- **`.NET SDKs installed`:** the inventory still contains **both** SDKs. Being listed doesn't mean an SDK was selected.

### Unexpected output: when the version can't be selected

Suppose `global.json` instead demands `9.0.100` with `"rollForward": "disable"`, and this host can only see `8.0.408` and `10.0.401`. The CLI will report an SDK-resolution error (wording varies with .NET version), rather than quietly use `10.0.401`.

This is **correct behavior**, not evidence that .NET is broken. The project asked for an exact SDK the running host cannot find. Diagnose in this order: confirm the executable, inspect `dotnet --list-sdks`, read the applicable `global.json` and its roll-forward settings, then consider any custom SDK search paths or architecture differences.

**Important:** The example is about the CLI SDK muxer. Microsoft documents a separate starting directory for the MSBuild project SDK resolver during builds. See the [Microsoft `global.json` reference](https://learn.microsoft.com/en-us/dotnet/core/tools/global-json).

### Checkpoint 3

**Q4.** Can `dotnet --version` report different values in two directories even if `Get-Command dotnet` identifies the same executable in both? Why?

**Q5.** A `global.json` specifies `8.0.408` with `"rollForward": "disable"`, but the current host cannot find that SDK. Should .NET pick `10.0.401` anyway? Why or why not?

Need a hint? Revisit [Section 3](#3-sdk-resolution-which-installed-sdk-is-selected), then [A4](#a4) and [A5](#a5).

## 4. Additional influences to recognize, not memorize yet

**Think about this:** What if an SDK is installed in another folder, but the running `dotnet` host does not normally look there? We will explain SDK search roots and why they are distinct from shell `PATH`.

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

For .NET 10+ hosts, `global.json` can include an ordered `sdk.paths` list of SDK search locations; the first location with a compatible SDK is used under the documented matching rules. This is another reason to avoid teaching the oversimplification that **an explicit host path always guarantees the exact SDK version**. An explicit path guarantees which *host file* you invoke; SDK selection still has its own rules. Our product's Verify operation does more than merely run a host: it checks version and origin in a controlled context.

### Worked example: what changes when SDK search locations are customized?

A .NET 10 or newer host can read `sdk.paths` in `global.json`. That setting affects **where the SDK resolver looks**, not which executable the shell launches. The following is an illustrative local Windows `global.json` (not a file to create during this lesson):

```json
{
  "sdk": {
    "version": "10.0.401",
    "rollForward": "disable",
    "paths": [
      "C:\\Users\\example\\dotnet-sdks\\10.0.401",
      "$host$"
    ]
  }
}
```

**Interpretation:**

- `version` asks for SDK `10.0.401`; `rollForward: disable` insists on an exact match.
- The first `paths` entry points to an additional SDK *installation root*. It is **not** a path to `dotnet.exe`.
- `$host$` means the SDK location associated with the already-running `dotnet` host. It is a special SDK search entry, not a shell variable to expand.
- The supported resolver searches the listed roots in order for a compatible SDK. The host *might* have been started from `C:\Program Files\dotnet\dotnet.exe` while the selected SDK comes from the separate user-owned root.

**If a .NET 10+ host finds the version only through the first entry, it can use that SDK without modifying system `PATH`.** If neither location has a compatible SDK, resolution fails. Older hosts ignore `sdk.paths`, so this example must not be treated as universal across all versions.

Other influences do not need a full lesson yet: preview SDKs may be considered differently inside and outside Visual Studio; x86, x64 and Arm64 host installations can expose different SDK inventories; editor builds and CI tasks may launch a different `dotnet` than your interactive shell. Each is a reason to examine **actual host, actual environment, and actual SDK policy** rather than assume that “latest installed” answers everything.

### Checkpoint 4

**Q6.** Which layer does `sdk.paths` influence: shell executable lookup, SDK selection, or application runtime selection?

Need a hint? Read [Section 4](#4-additional-influences-to-recognize-not-memorize-yet) and [A6](#a6).

## 5. So why have an isolated SDK?

**Think about this:** If two installations show the same SDK version number, are you sure you're using the isolated one? Let's inspect the evidence before drawing that conclusion.

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

Substitute your *actually installed* version; if none is installed, treat the examples as reading material. These commands do not install an SDK, although normal .NET CLI first-run state and telemetry rules can still apply. Their observed SDK selection can be influenced by SDK-selection policy, including an applicable `global.json`.

**What isolation does not mean:** It is **not** a security sandbox, a guarantee that an application can't write user data, a promise that all editors automatically use the SDK, or proof that a project compiles correctly. The tool separates installation locations and provides controlled installation/verification workflows.

### Worked example: system command versus intentional isolated invocation

Assume you normally type `dotnet` on Windows, and your system host sees SDKs `8.0.408` and `10.0.401`. You then install **a separate copy** of `10.0.401` using our tool in the user-owned location `C:\Users\example\dotnet-sdks\10.0.401`. We will not install anything during this lesson.

Compare these two commands:

```powershell
dotnet --version
& "$HOME\dotnet-sdks\10.0.401\dotnet.exe" --version
```

From a directory without an applicable SDK pin, the following is **possible** illustrative output:

```text
10.0.401
10.0.401
```

**Same number, different proof!** The first line is the SDK selected by whichever `dotnet` command PowerShell resolved normally. The second line is the SDK selected after **explicitly launching the isolated host**. A matching version number alone does **not** establish where the SDK's files came from. Two installations can have exactly the same SDK version.

This is the reason the tool's **Verify** operation checks more than a version string. For modern SDKs, it checks the isolated installation directory, that the selected host launches, that the exact SDK appears in the isolated host's SDK inventory **at the expected isolated origin**, and that `--version` resolves correctly in controlled temporary working state. For historical hosts, it uses a generation-appropriate SDK-origin check instead of unsupported inventory commands.

For example, on Windows, a person who **already** installed isolated `10.0.401` can ask the product to verify it:

```powershell
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1" -Action Verify -SdkVersion "10.0.401"
```

Illustrative, **simplified** successful verification section (the actual report contains SDK metadata and optional components, and labels vary for historical hosts):

```text
Verification:
  Installation directory  OK  C:\Users\example\dotnet-sdks\10.0.401
  .NET host               OK  Host executable found and launched
  SDK inventory           OK  Exact SDK found in isolated installation
  SDK resolution          OK  Correct SDK selected

Isolated SDK 10.0.401 verified successfully.
```

**How to read these results:** “Installation directory OK” means the owned version directory exists; “.NET host OK” means the host was found and could launch; “SDK inventory OK” proves the modern host reported the requested SDK in the isolated location rather than accepting an identical system SDK; “SDK resolution OK” proves the expected version was selected under Verify's controlled conditions.

**What if one check fails?** The output identifies which guarantee has failed; it must not report installation health as successful merely because the version string happens to match. Missing Microsoft lifecycle metadata or optional component diagnostics, on the other hand, do **not** change the result of authoritative local verification. Verify also does **not** compile your application or prove runtime compatibility for every project.

On Bash (Linux/macOS), the equivalent product invocation for an already-installed SDK is:

```bash
"$HOME/dotnet-sdks/isolated-dotnet-sdk.sh" verify 10.0.401
```

### Why runtime inventory isn't the same as runtime selection

One final preview clarifies the third layer. For an installed host you can run:

```powershell
dotnet --list-runtimes
```

Illustrative abbreviated output:

```text
Microsoft.NETCore.App 8.0.15 [C:\Program Files\dotnet\shared\Microsoft.NETCore.App]
Microsoft.NETCore.App 10.0.5 [C:\Program Files\dotnet\shared\Microsoft.NETCore.App]
```

This lists runtimes the current host can see. **It does not tell you which runtime every application will use.** That depends on a particular application's runtime configuration and applicable runtime-selection rules. A machine may select SDK `10.0.401` for a build yet run an application using a .NET 8 runtime. SDK selection and runtime selection answer different questions.

### Worked example: building with one SDK and running on another .NET runtime

Imagine a developer built a framework-dependent application called `MyApp` that targets **.NET 8**, but their current command-line tooling selects **SDK 10.0.401**. These are compatible concepts: the *build tool* version is not required to have the same number as the application's target/runtime version.

The project could declare this target framework:

```xml
<PropertyGroup>
  <TargetFramework>net8.0</TargetFramework>
</PropertyGroup>
```

If the host selects SDK 10.0.401, then an illustrative build command is:

```powershell
dotnet build MyApp.csproj
```

Here, the **SDK** performs the build. It doesn't change the fact that `MyApp` targets .NET 8. When the project is built as a framework-dependent app, it has a generated runtime configuration file (for example, `MyApp.runtimeconfig.json`). A simplified form might be:

```json
{
  "runtimeOptions": {
    "tfm": "net8.0",
    "framework": {
      "name": "Microsoft.NETCore.App",
      "version": "8.0.0"
    }
  }
}
```

**Read each field:** `tfm` describes the target framework. `Microsoft.NETCore.App` is the required shared framework. `8.0.0` expresses the runtime-framework request from which normal roll-forward rules decide the compatible installed version. It is **not** a request for SDK 8.0.0 and doesn't require `dotnet --version` to report 8.x.

Now suppose the host can see runtime versions **8.0.15** and **10.0.5**, as in the earlier sample. Running this framework-dependent app with the host:

```powershell
dotnet MyApp.dll
```

would normally select the compatible **8.0.15 runtime** (patch roll-forward within .NET 8) rather than automatically run the app on the latest 10.0.5 runtime. This is a *runtime selection* decision based on the app's configuration, available frameworks, and runtime roll-forward policy — **not** a request to select the newest SDK.

That means the same machine can truthfully show all of these:

| Observation | Example result | What the result means |
| --- | --- | --- |
| `dotnet --version` | `10.0.401` | SDK selected for development commands |
| `dotnet --info` → `Host: Version` | `10.0.5` | Version of the reported hosting component |
| `dotnet --list-runtimes` | `8.0.15` and `10.0.5` | Available framework/runtime inventory |
| `dotnet MyApp.dll` | Runs using compatible `8.0.15` | The app's **specific** runtime resolution |

**If MyApp fails to start:** For example, if only .NET 10 were installed and the app required .NET 8 under the ordinary default policy, the runtime host may report a missing-compatible-framework error. Installing a newer SDK or changing `global.json` is **not** the same as satisfying the application's runtime requirement. Examine the app's `runtimeconfig.json`, the installed runtimes, any runtime roll-forward settings, and the executable/architecture actually used.

This example describes **framework-dependent deployment**. A **self-contained** published app includes its own runtime, so selecting from shared installed runtimes isn't the same process. That's an important boundary, even though the rest of runtime deployment deserves a later session.

Learn more: [Microsoft: select which .NET version to use](https://learn.microsoft.com/en-us/dotnet/core/versions/selection) and [Microsoft: runtime configuration](https://learn.microsoft.com/en-us/dotnet/core/runtime-config/).

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

## 7. Real Windows PowerShell walkthrough

**Status: owner-supplied, sanitized observations.** The project owner provided these command results from **PowerShell 7.6.6** and also supplied a screenshot of Windows **Installed Apps** filtered to `.net`. The CLI output here is sourced from that provided terminal transcript: we did **not** independently execute the commands or capture the screenshot. Unlike earlier hypothetical examples, these version numbers are *observed* from the provided transcript.

**Sanitization and limits:** The owner's Windows username and terminal prompt have been omitted; standard Microsoft installation paths, SDK/runtime versions, and reported metadata remain unchanged. `dotnet --info` is excerpted to avoid duplicating the full SDK and runtime lists preserved separately below. This is a snapshot from **one system, one PowerShell environment, and one working-directory context**, not a universal claim about other machines.

### Observation 1 — Which executable does PowerShell find?

```powershell
Get-Command dotnet -All | Format-Table CommandType, Name, Source -AutoSize
```

Observed output:

```text
CommandType Name       Source
----------- ----       ------
Application dotnet.exe C:\Program Files\dotnet\dotnet.exe
```

**Explanation:** `Application` means PowerShell found a native executable. `Source` identifies its full location: **`C:\Program Files\dotnet\dotnet.exe`**. Only one `dotnet` command candidate appeared in this session. This result answers **which executable PowerShell resolves**, not which SDK version it selects and not which runtime starts an application. A separately installed isolated `dotnet.exe` could exist outside `PATH` without appearing here.

**If you see more rows:** PowerShell might see another executable, function, or alias. Inspect command precedence and paths first; do not confuse multiple executable candidates with multiple installed SDKs.

### Observation 2 — Which SDK does that host select?

```powershell
dotnet --version
```

Observed output:

```text
10.0.402
```

**Explanation:** **`10.0.402` is the selected Microsoft .NET SDK.** It is *not* the version of the `dotnet.exe` file or the runtime used by every application. The owner's `dotnet --info` report says `global.json file: Not found`. The host's SDK inventory below lists `10.0.402` as the highest available SDK, explaining this result in the observed context.

**If the result changes in another directory:** A different applicable `global.json` or SDK search policy may be involved, even if PowerShell still launches the same executable.

### Observation 3 — What else does `dotnet --info` reveal?

```powershell
dotnet --info
```

Observed **excerpt** from the provided report. The workload description and full SDK/runtime inventories are omitted here; their important version lists appear in Observations 4 and 5.

```text
.NET SDK:
 Version:           10.0.402
 Commit:            a8dd0577c5
 Workload version:  10.0.400-manifests.378ba522
 MSBuild version:   18.9.15+a8dd0577c

Runtime Environment:
 OS Name:     Windows
 OS Version:  10.0.26300
 OS Platform: Windows
 RID:         win-x64
 Base Path:   C:\Program Files\dotnet\sdk\10.0.402\

Host:
  Version:      10.0.13
  Architecture: x64
  Commit:       4099f83977

Other architectures found:
  x86   [C:\Program Files (x86)\dotnet]
    registered at [HKLM\SOFTWARE\dotnet\Setup\InstalledVersions\x86\InstallLocation]

Environment variables:
  Not set

global.json file:
  Not found
```

**Read the output carefully:**

- **`.NET SDK: Version 10.0.402`** agrees with `dotnet --version`. The SDK commit, workload manifest and MSBuild values identify *related development-tool components*; they aren't alternative answers to the selected-SDK question.
- **`Base Path: C:\Program Files\dotnet\sdk\10.0.402\`** points to the **selected SDK's files**. Compare that with Observation 1's **`C:\Program Files\dotnet\dotnet.exe`**: one is the SDK directory and one is the executable file.
- **`Host: Version 10.0.13`** reports a **host component**. It differs from SDK `10.0.402` because host components and SDK releases have separate version numbers. It does *not* establish which runtime every application will use.
- **`RID: win-x64`** and **`Host Architecture: x64`** describe the environment/architecture of the reporting host. The **x86** entry means another architecture's .NET installation is registered at `C:\Program Files (x86)\dotnet`, *not* that the x86 SDK inventory has been inspected.
- **`Environment variables: Not set`** means no relevant variables were shown by this report; Windows itself still has environment variables. **`global.json file: Not found`** describes the current SDK-resolution context, not the entire disk.

**Interesting distinction:** `Host Version 10.0.13` also happens to be listed as an available `Microsoft.NETCore.App` runtime below. That does not mean every app on this machine necessarily runs on `10.0.13`. Runtime selection is specific to an app, its runtime configuration and the applicable roll-forward policy.

### Observation 4 — Which SDKs does this host see?

```powershell
dotnet --list-sdks
```

Observed output:

```text
8.0.426 [C:\Program Files\dotnet\sdk]
9.0.319 [C:\Program Files\dotnet\sdk]
10.0.401 [C:\Program Files\dotnet\sdk]
10.0.402 [C:\Program Files\dotnet\sdk]
```

**Explanation:** Four SDKs are visible to the **normally resolved system host**. Each row combines a complete SDK version with the SDK root directory in brackets. `dotnet --version` selected `10.0.402`, but the other three remain installed and could be selected under different compatible SDK policies. No version-specific `~/dotnet-sdks/<version>` path appears in this inventory, but **that does not prove there are no isolated SDKs on disk**.

### Observation 5 — Which runtimes does this host see?

```powershell
dotnet --list-runtimes
```

Observed output:

```text
Microsoft.AspNetCore.App 8.0.32 [C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App]
Microsoft.AspNetCore.App 9.0.21 [C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App]
Microsoft.AspNetCore.App 10.0.12 [C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App]
Microsoft.AspNetCore.App 10.0.13 [C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App]
Microsoft.NETCore.App 6.0.36 [C:\Program Files\dotnet\shared\Microsoft.NETCore.App]
Microsoft.NETCore.App 7.0.20 [C:\Program Files\dotnet\shared\Microsoft.NETCore.App]
Microsoft.NETCore.App 8.0.32 [C:\Program Files\dotnet\shared\Microsoft.NETCore.App]
Microsoft.NETCore.App 9.0.21 [C:\Program Files\dotnet\shared\Microsoft.NETCore.App]
Microsoft.NETCore.App 10.0.12 [C:\Program Files\dotnet\shared\Microsoft.NETCore.App]
Microsoft.NETCore.App 10.0.13 [C:\Program Files\dotnet\shared\Microsoft.NETCore.App]
Microsoft.WindowsDesktop.App 6.0.36 [C:\Program Files\dotnet\shared\Microsoft.WindowsDesktop.App]
Microsoft.WindowsDesktop.App 7.0.20 [C:\Program Files\dotnet\shared\Microsoft.WindowsDesktop.App]
Microsoft.WindowsDesktop.App 8.0.32 [C:\Program Files\dotnet\shared\Microsoft.WindowsDesktop.App]
Microsoft.WindowsDesktop.App 9.0.21 [C:\Program Files\dotnet\shared\Microsoft.WindowsDesktop.App]
Microsoft.WindowsDesktop.App 10.0.12 [C:\Program Files\dotnet\shared\Microsoft.WindowsDesktop.App]
Microsoft.WindowsDesktop.App 10.0.13 [C:\Program Files\dotnet\shared\Microsoft.WindowsDesktop.App]
```

**Explanation of the columns and frameworks:**

- The **first value** is the shared-framework name, the **second** is its installed **runtime version**, and the **bracketed value** identifies the framework installation root.
- **`Microsoft.NETCore.App`** is the core .NET runtime/shared framework. Versions **`6.0.36`** and **`7.0.20`** appear here even though **there is no SDK 6 or 7** in Observation 4. This directly demonstrates that **installed runtimes and installed SDKs are different inventories**.
- **`Microsoft.AspNetCore.App`** is the ASP.NET Core shared framework for compatible web applications.
- **`Microsoft.WindowsDesktop.App`** supplies Windows desktop application frameworks; a Linux/macOS system wouldn't normally report these Windows-only shared frameworks.
- Versions **`10.0.12` and `10.0.13`** coexist for multiple frameworks. Having both installed does **not** establish that the latest runtime is used by every app. For framework-dependent apps, `runtimeconfig.json`, installed frameworks, the host environment and roll-forward behavior affect runtime selection.

There was **no application-specific runtime execution test** in the supplied transcript. The earlier example of building with one SDK and running with a compatible different-numbered runtime remains **illustrative**, not something proven for a particular application by this inventory.

### Observation 6 — What version of *our management tool* is installed?

```powershell
& "$HOME\dotnet-sdks\isolated-dotnet-sdk.ps1" -Version
```

Observed output:

```text
isolated-dotnet-sdk development (main)
```

**Explanation:** This identifies the **development-source build of the Isolated .NET SDK management script**. It does **not** identify a Microsoft SDK release or guarantee that the script is a published stable version. Our PowerShell script's `-Version` is different from Microsoft's `dotnet --version`, even though both commands use the word “version.” This output also **does not** prove which isolated SDK versions are installed; for that, use the product's dedicated **List** command in a separate read-only inspection.

### Observation 7 — What does Windows *Installed Apps* show?

The owner supplied a **fuller screenshot** of **Windows Settings → Apps → Installed apps** with the search box containing **`.net`**. The interface reported **`4 apps found`**. This is observed Windows **installer registration** information, *not* another `dotnet` CLI query. The image itself is not embedded in this document; the table below is a transcription of its four visible results, including the smaller installer-version labels and displayed sizes.

| App name shown in Windows | Secondary displayed version | Reported size |
| --- | --- | --- |
| Microsoft .NET SDK 10.0.401 (x64) from Visual Studio | `40.11.21517` | **800 KB** |
| Microsoft .NET SDK 10.0.402 (x64) | `10.4.226.50611` | **1.17 GB** |
| Microsoft .NET SDK 8.0.426 (x64) | `8.4.2626.50502` | **938 MB** |
| Microsoft .NET SDK 9.0.319 (x64) | `9.3.1926.50507` | **953 MB** |

All four entries name Microsoft Corporation as publisher. The first entry shows an install date of September 15, 2026; the other three show October 13, 2026. **Those details are from the screenshot**, not observations made by `dotnet.exe`. No username, machine address, or personal location is included in this transcription.

**What does this establish?** The *display names* match the same four SDK version numbers seen in Observation 4. The **secondary version labels** (for example `10.4.226.50611`) are Windows application/installer metadata — not additional SDKs selected by `dotnet --version`. The striking **800 KB** reported for `10.0.401 from Visual Studio` is a Windows-apps *reported entry size*, **not proof that the SDK's extracted files occupy only 800 KB**. For this Visual Studio-managed SDK, installation and removal should be handled using the [Visual Studio Installer](https://learn.microsoft.com/en-us/dotnet/core/install/remove-runtime-sdk-versions?pivots=os-windows), not by deleting the SDK folder.

### Why .NET 6 and 7 appear for some components but not others

Compare the actual system-host inventories from Observations 4 and 5. **For the .NET 6 and .NET 7 families specifically:**

| Component | .NET 6 evidence | .NET 7 evidence | What it means |
| --- | --- | --- | --- |
| SDK (`--list-sdks`) | Not listed | Not listed | No SDK 6.x or 7.x visible to the current x64 host |
| Core runtime (`Microsoft.NETCore.App`) | **6.0.36** | **7.0.20** | The core .NET runtime frameworks remain installed |
| Windows Desktop runtime (`Microsoft.WindowsDesktop.App`) | **6.0.36** | **7.0.20** | Windows Forms/WPF runtime frameworks remain installed |
| ASP.NET Core runtime (`Microsoft.AspNetCore.App`) | Not listed | Not listed | The current host does not see the ASP.NET Core 6.x/7.x shared frameworks |

This pattern makes sense once we understand what Microsoft distributes on Windows:

- The **.NET Desktop Runtime** includes the **core .NET runtime** and the **Windows Desktop runtime**, but does **not** include the ASP.NET Core runtime.
- A **.NET SDK installer** typically includes the core runtime, Windows Desktop runtime and ASP.NET Core runtime. Unlike individual runtimes, it adds tools for development.
- Components can remain after other SDKs or installers change. The screenshot and `--list-runtimes` output **cannot establish which installer originally created or retained** the 6.x and 7.x runtime directories. A separately installed desktop runtime, Visual Studio, or another application installer is a possibility, **not an observed historical fact**.

Microsoft's [Windows .NET installation guide](https://learn.microsoft.com/en-us/dotnet/core/install/windows) provides the installer-to-runtime inclusion table. The important lesson is that **one SDK version isn't automatically one runtime of every kind**, and a framework-dependent app must find the particular compatible runtime/framework it needs.

**Example of a possible consequence:** A framework-dependent **.NET 6 Windows Forms application** could potentially run using the available 6.0.36 core and desktop frameworks, subject to its runtime configuration and hosting environment. A framework-dependent **ASP.NET Core 6 application** that needs `Microsoft.AspNetCore.App 6.x` cannot assume that dependency is met just because `Microsoft.NETCore.App 6.0.36` is installed. The CLI inventory alone does **not** demonstrate that either hypothetical application was launched or succeeded.

**Security and maintenance context:** .NET **7** reached end of support on **May 14, 2024**, and .NET **6** on **November 12, 2024**, according to Microsoft's [.NET support policy](https://dotnet.microsoft.com/en-us/platform/support/policy/dotnet-core). Out-of-support runtime components are worth auditing, but **do not remove them just because they appear in this list**: determine application dependencies and the responsible installer first. This exercise does not require uninstalling anything.

### Why the Windows list and CLI inventory are not interchangeable

1. **Windows Settings** shows matching *registered application entries* for the `.net` filter. It is not an exhaustive directory scan or an app-specific runtime-selection report. That search returned **four SDK registrations** on this machine; the UI did **not** list every runtime that the host reports.
2. **`dotnet --list-sdks`** shows SDKs discoverable by this running `dotnet` host, not necessarily every SDK stored under a different host/root or architecture. Here its four displayed versions agree with the four Windows SDK display names.
3. **`dotnet --list-runtimes`** shows installed shared-framework versions visible to this host — **16 lines across three framework families**, including older runtimes with no corresponding SDK on the system-host SDK list.
4. The `dotnet --info` report also noted a registered **x86** install root at `C:\Program Files (x86)\dotnet`. Its existence does **not** tell us which SDKs/runtimes that separate architecture can see. Nothing in the four x64 SDK entries enumerates the x86 inventory.
5. An SDK extracted into an *isolated* folder can exist without a normal Windows Installed Apps registration; likewise, a Windows registration alone doesn't prove a particular running host sees the registered SDK.
6. **Microsoft .NET Framework** (the older Windows-specific product family) is different from modern `Microsoft.NETCore.App` shared framework versions; don't combine their inventories.

**Next step only if diagnosis is needed:** To determine which installer owns a component or which specific application uses an older runtime, collect targeted installer/application evidence. Don't infer dependency or usage from the two version lists alone, and **don't remove anything during training**.

For comparison, Microsoft's [installed-versions instructions](https://learn.microsoft.com/en-us/dotnet/core/install/how-to-detect-installed-versions) use `--list-sdks` and `--list-runtimes`, while its [Windows removal guidance](https://learn.microsoft.com/en-us/dotnet/core/install/remove-runtime-sdk-versions?pivots=os-windows) explains the Installed Apps and Visual Studio Installer surfaces.

### Observation 8 — What version is the actual `dotnet.exe` file?

The owner supplied an additional **Windows File Explorer → `C:\Program Files\dotnet\dotnet.exe` → Properties → Details** screenshot. Earlier, PowerShell resolved that very same executable path in Observation 1. The screenshot displays this file's Windows version information:

| Explorer property | Observed value | What it means |
| --- | --- | --- |
| File description | **.NET Host** | Description of the native entry-point executable |
| Product name | **.NET** | Product associated with the file |
| Product version | **`10.0.13`** (shown with commit metadata) | .NET host product-version information |
| File version | **`10.0.1326.50504`** | Windows executable file-version metadata |
| File size | **163 KB** | Size of this `dotnet.exe` file, **not** the complete SDK/runtime installation |

**Connect it to the CLI output:** `dotnet --info` reported `Host: Version 10.0.13`, which agrees with the **Product version** shown for this executable. But `dotnet --version` reported **10.0.402** because it answers an entirely different question: **which SDK was selected**. Even the Windows **File version** (`10.0.1326.50504`) is another distinct version format. The Windows metadata describes the binary, not the SDK or the runtime that an arbitrary application uses.

**A useful, optional read-only PowerShell inspection** of the same file's metadata is:

```powershell
(Get-Item -LiteralPath 'C:\Program Files\dotnet\dotnet.exe').VersionInfo |
    Select-Object FileDescription, FileVersion, ProductName, ProductVersion
```

The command above is provided **for learners to try**, and its output has **not** been supplied or observed. The *actual evidence* is the owner's File Explorer Properties screenshot. Don't label a future PowerShell result as observed until it has been run.

**If the versions don't match:** First confirm that the binary whose properties you opened is the one PowerShell resolves (`Get-Command dotnet -All`). It is possible to examine the properties of one host file while executing another because of `PATH`, aliases, explicit paths, or architecture differences. Also keep the product's executable metadata distinct from its selected SDK: a newer SDK does not mean `dotnet.exe` must have that SDK's exact version number. Finally, don't interpret this small native executable's **163 KB** size as the space occupied by the associated runtimes, SDK, or user-owned isolated installations.

### Put all eight observations together

| Question | Relevant evidence | Actual finding or limit |
| --- | --- | --- |
| Which executable does PowerShell resolve? | `Get-Command dotnet -All` | `C:\Program Files\dotnet\dotnet.exe` (native Application) |
| Which SDK is currently selected? | `dotnet --version` | **10.0.402** |
| Where are the selected SDK's files? | `dotnet --info` → `Base Path` | `C:\Program Files\dotnet\sdk\10.0.402\` |
| What hosting-component version is reported? | `dotnet --info` → `Host Version` | **10.0.13** (x64) |
| What are the executable's Windows versions? | `dotnet.exe` Properties → Details | **Product 10.0.13; File 10.0.1326.50504**; separately from SDK **10.0.402** |
| Which system-host SDK versions are visible? | `dotnet --list-sdks` | **8.0.426, 9.0.319, 10.0.401, 10.0.402** |
| Which runtime frameworks are visible? | `dotnet --list-runtimes` | Several .NET Core, ASP.NET Core, and Windows Desktop runtime versions; includes **6.0/7.0 runtimes without corresponding visible SDKs** |
| Which management-tool version is reported? | Script `-Version` | **`isolated-dotnet-sdk development (main)`** |
| What does the Windows Settings screenshot establish? | Installed Apps filter `.net` → **4 apps found** | Four x64 SDK registrations, including one Visual Studio-managed entry; **not** a complete runtime inventory |
| Which runtime did *a particular application* use? | Would require application-specific evidence | **Not determined** by these six commands or the Installed Apps screenshot |

**Takeaway:** A file's Windows version properties, the host's reported product version, and the selected SDK version can all be different values. “What version of .NET do I have?” is incomplete. First ask **which program is running**, **which SDK it selects**, **which host components are reported**, **which runtimes can be discovered**, **which runtime a specific app uses**, and **which installation-management interface is being viewed**. These are different questions with different evidence.

Keep the Q1–Q8 reinforcement questions independent of this owner's specific versions, so the curriculum remains useful on other Windows, Linux and macOS machines.

---

## Answer key and self-check

**Use this after attempting each question.** A useful answer explains *why*, not just yes/no. Exact wording is not required.

### A1

No. `dotnet --version` shows the selected **SDK version** for that invocation. **Host:** the entry-point program (for example `dotnet.exe`) found by the shell; it launches SDK tooling for development commands or helps start an app via the runtime host. **SDK:** the development tools selected for commands such as `build` and `test`; this is what `--version` reports. **Runtime:** the components that execute a built application; selection depends on that application's framework/runtime configuration. To learn which host executable the shell would launch, inspect `Get-Command dotnet -All` or `type -a dotnet`. `dotnet --info` reports both SDK and Host information, but none of these facts alone proves the runtime used by *every* application.

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
- Identify at least two non-installing inspection commands for diagnosing resolution on your platform, and recognize that invoking the CLI can have ordinary first-run effects.
- Explain what the isolated tool changes and what it intentionally leaves unchanged.
- Avoid claiming that explicit host selection alone guarantees a particular SDK, or that “isolation” means sandboxing.

If any item is uncertain, return to the linked section and Microsoft/product references below, then try again. Completing every command is not required on machines without .NET installed.

## Authoritative references

**Microsoft (platform behavior)**

- [The `dotnet` command](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet) — particularly `--version`, `--list-sdks`, and `--info`.
- [.NET CLI telemetry](https://learn.microsoft.com/en-us/dotnet/core/tools/telemetry) — first-run and telemetry behavior of CLI invocation.
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