# Session 1 — Understanding .NET and How It Selects Components

**Audience:** Developers and maintainers who want to understand Microsoft's component selection behavior.
**Format:** Self-paced; an AI instructor is optional.
**Status:** Curriculum pilot draft v0.5, pending review.
**Companion:** [AI Instructor Guide](isolated-dotnet-sdk-session-1-ai-instructor.md).

> **Safety and evidence:** No installation, removal, builds or changes to `PATH` or `global.json` are required. Live inspections are optional. CLI commands may cause normal first-run state or telemetry per [Microsoft's settings](https://learn.microsoft.com/en-us/dotnet/core/tools/telemetry). Worked examples in this core lesson are **illustrative**, not claims about your computer. Separate owner-supplied observations have been retained for later consideration.

## Why start here?

Imagine you maintain an application targeting .NET 8. You install the .NET 10 SDK to explore its features. The next day, your development tools report .NET 10.

You might ask:

1. Did installing SDK 10 replace the existing installation?
2. Am I now using a different `dotnet.exe`?
3. Will my existing projects automatically use SDK 10?
4. Will my applications execute using the .NET 10 runtime?

These are distinct questions. We will explain **why** the distinctions matter, **what** components participate, **how** they work, and which common misconceptions produce troubleshooting mistakes. Commands appear only to demonstrate or investigate those decisions.

### How to study

Study the host, SDK-selection, and runtime-selection concepts in order. Read each mechanism and demonstration, then attempt Q1–Q8. Use the hints if stuck, and check the [answer key](#answer-key-and-self-assessment) only after attempting the questions. Q6 is an optional advanced checkpoint. Afterward, you may [try the concepts on your own computer](#try-it-yourself-explore-your-own-net-installation); this practical activity is optional and does not affect session completion.

### Learning outcomes

You can explain why host, SDK, and runtime versions differ; how executable resolution, SDK selection and application runtime selection work; how policies and inventories affect those decisions; and what the available evidence does **not** prove.

## Key Terms

A few definitions will help as we learn how .NET finds its executable, selects an SDK, and runs applications.

Before we discuss *resolution*, here are the terms we'll use:

| Term | Plain-language meaning |
| --- | --- |
| **`dotnet` executable / host** | The actual program (`dotnet.exe` on Windows, `dotnet` on Linux/macOS) that starts when you run a .NET CLI command. A *host* is not the same as an SDK version. |
| **SDK** | Software Development Kit: the .NET tools needed to build, test, and publish software. Different SDK versions may coexist. |
| **Runtime** | The components needed to execute a .NET application. An app's runtime selection is different from selecting an SDK to build it. |
| **Resolution** | The process of deciding which executable, SDK, or runtime to use. The answer depends on *which one* is being resolved. |
| **`PATH`** | A list of directories consulted when locating commands by name. Shell aliases/functions and explicit paths can take precedence. |
| **`global.json`** | An optional file that tells .NET which SDK version or range of SDK versions to accept. It does not rename or redirect the shell's `dotnet` command. |

## Concept 1: Understanding the .NET Host

### Why understand `dotnet.exe`?

Developers sometimes assume installing a new SDK necessarily replaces the executable, or that the SDK used for a build determines the runtime for every application. These are different component-selection decisions. Confusing them can lead to changes to the wrong configuration or incorrect troubleshooting conclusions.

On Windows, `dotnet.exe` is a native **.NET host**, also named `dotnet` on Linux/macOS. It is an entry point, **not** the entire SDK or the runtime executing managed application code. The host participates in (1) launching **SDK tooling** for development operations, and (2) launching **framework-dependent applications** through the appropriate runtime-hosting machinery. Other components, such as `hostfxr`, help resolve the required .NET pieces; their installation layout is beyond this foundational lesson.

A conventional .NET installation root may have one shared `dotnet.exe` and multiple side-by-side SDK directories. Host components can be serviced independently, and different installation roots or architectures can have separate hosts.

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



### Which `dotnet.exe` does the shell start?

**Think about this:** If there are two `dotnet.exe` files on your machine, how does PowerShell decide which one to run? No need to guess; we'll use command output to show you.

When you type `dotnet`, **the shell** first decides what that name means. That is not yet an SDK selection decision.

- In ordinary cases, the shell finds an executable through entries on `PATH` in its environment.
- In PowerShell, a command alias or function can take precedence over a native executable; inspect the actual command category and location rather than assuming every match is `dotnet.exe`.
- In Bash, an alias or function may take precedence; shell lookup details (including remembered command locations) can matter. `type -a` helps expose how the shell currently interprets the name.
- An **explicit executable path** removes ambiguity about which file you are asking the shell to launch.
- Your IDE, build task, terminal, and CI runner can each have a different environment or specify an executable path directly. Resolving `dotnet` in your interactive terminal does not prove what another process launches.

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

- **Command not found:** No usable command named `dotnet` was resolved by that shell. It does **not** prove there is no SDK anywhere on disk; another host might exist outside `PATH`.
- **Multiple paths:** Multiple possible *executables* exist. This is not the same as multiple *SDKs*. You need `dotnet --list-sdks` for the SDKs visible to a particular host.
- **An alias/function appears:** Inspect its definition before inferring the actual executable. An editor or CI job may resolve something else because it has a different environment.
- **An executable path looks unfamiliar:** Check which process or shell you are in, whether `PATH` was modified, and whether you are using x86/x64/Arm64 tooling. Do not change your system just to make the exercise match the example.

**One certainty you can introduce deliberately:** To choose a particular installed host file, use its full path, such as `& "C:\Program Files\dotnet\dotnet.exe" --version` in PowerShell or `/usr/share/dotnet/dotnet --version` in Bash. The host file is then explicit; the version the SDK resolver reports is still a separate matter.

### What does `dotnet --version` actually establish?

Assume a shared host discovers SDKs `8.0.408` and `10.0.401`, with no applicable policy changing the default. A developer runs:

```powershell
dotnet --version
```

Illustrative output:

```text
10.0.401
```

This number identifies **the SDK selected for the invocation**, not the host executable's file version, the SDK every project will use, or the runtime a particular application loaded. Commands are evidence for a question, not interchangeable definitions of "the .NET version."

### Common misconceptions

| Assumption | What actually follows |
| --- | --- |
| "`dotnet.exe` is the SDK." | Host and SDK are different components. |
| "Installing a new SDK necessarily chooses another `dotnet.exe`." | Shell command lookup chooses the executable; installation and servicing have separate rules. |
| "There's one `dotnet.exe` on a Windows computer." | There can be multiple roots/architectures and separate host executables. |
| "Calling a host by full path guarantees the selected SDK." | It guarantees the *host file*, not every SDK resolver outcome. |
| "SDK 10 means my apps run on runtime 10." | App runtime selection is a third decision. |

### Revisiting our four opening questions

| Question | What we know now |
| --- | --- |
| Did installing SDK 10 replace my installation? | Not necessarily. SDKs coexist; shared host components may be updated separately. |
| Am I using a different `dotnet.exe`? | Not necessarily; inspect executable lookup and file identity. |
| Will my projects use SDK 10? | **It depends on SDK selection. Concept 2 answers this next.** |
| Will my apps execute with runtime 10? | Not necessarily; Concept 3 explains this. |

### Checkpoint: executable resolution

**Q1.** A computer has two `dotnet.exe` files in different directories. Does the newer SDK installation automatically guarantee that its executable is the one launched by `dotnet`? Explain.

**Q2.** Why is an explicit path such as `& "C:\Program Files\dotnet\dotnet.exe" --version` more predictable than typing `dotnet --version`? What does it *not* guarantee by itself?

**Q3.** A developer says their `dotnet.exe` must be version 10.0.401 because `dotnet --version` prints 10.0.401. Explain what is wrong.

Need a hint? For Q1–Q2, revisit [which executable the shell starts](#which-dotnetexe-does-the-shell-start), and consult [A1](#a1) and [A2](#a2) only after attempting the questions. For Q3, revisit [what the command establishes](#what-does-dotnet---version-actually-establish), then consult [A3](#a3) after your attempt.

**Transition:** The shell has started the host. **How does .NET now decide which SDK to use?**

## Concept 2: Understanding How .NET Selects an SDK

**Think about this:** Could the same `dotnet.exe` print `10.0.401` in one directory and `8.0.408` in another? The examples in this section explain how that happens.

Once a `dotnet` executable is running and you invoke an SDK-related command, .NET's SDK resolver selects an SDK it can find and that satisfies the active policy.

In a typical terminal invocation:

- Without an applicable `global.json`, the resolver normally selects the highest installed SDK version visible to that host; prerelease visibility depends on the invocation context and related settings.
- With a `global.json`, SDK selection is constrained by the file's version and policy. For the CLI, the search starts in the **current working directory** and walks upward through parent directories.
- A `global.json` version is a full SDK version, e.g. `10.0.401`; it isn't just `10` or `10.0`.
- The `rollForward` policy governs which alternatives are acceptable. `"rollForward": "disable"` means that exact SDK version must be available.
- A different SDK version may be selected — or resolution may fail — without the shell choosing a different executable.

**Important nuance:** The MSBuild project SDK resolver can start its search from a solution/project directory rather than the CLI's current directory. Thus, do not casually generalize every build-related resolver as “always starts where the shell is.”

### Understanding SDK roll-forward

`global.json` can request a full SDK version and a `rollForward` policy. The default when a version is specified without a policy is `patch`. SDK roll-forward is separate from application runtime roll-forward.

| SDK policy | General behavior |
| --- | --- |
| `disable` | Require exactly the requested SDK version. |
| `patch`, `latestPatch` | Permit appropriate later patches in the requested SDK feature band, with different preferences. |
| `feature`, `minor`, `major` | Allow increasingly broad compatible bands with closest-eligible-version preferences. |
| `latestFeature`, `latestMinor`, `latestMajor` | Allow broader ranges and prefer the highest eligible matching version. |

For precise matching rules, see [Microsoft's SDK policy table](https://learn.microsoft.com/en-us/dotnet/core/tools/global-json#rollforward).

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

**Important:** This example concerns SDK resolution by the CLI's `dotnet` host (also called the *muxer*). Microsoft documents a separate starting directory for the MSBuild project SDK resolver during builds. See the [Microsoft `global.json` reference](https://learn.microsoft.com/en-us/dotnet/core/tools/global-json).

### Checkpoint: SDK selection

**Q4.** Can `dotnet --version` report different values in two directories even if `Get-Command dotnet` identifies the same executable in both? Why?

**Q5.** A `global.json` specifies `8.0.408` with `"rollForward": "disable"`, but the current host cannot find that SDK. Should .NET pick `10.0.401` anyway? Why or why not?

Need a hint? Revisit [Concept 2](#concept-2-understanding-how-net-selects-an-sdk), then [A4](#a4) and [A5](#a5) after attempting the questions.

### Additional influences to recognize, not memorize yet

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

For .NET 10+ hosts, `global.json` can include an ordered `sdk.paths` list of SDK search locations; the first location with a compatible SDK is used under the documented matching rules. This is another reason to avoid teaching the oversimplification that **an explicit host path always guarantees the exact SDK version**. An explicit path guarantees which *host file* you invoke; SDK selection still has its own rules.

### Worked example: what changes when SDK search locations are customized?

A .NET 10 or newer host can read `sdk.paths` in `global.json`. That setting affects **where the SDK resolver looks**, not which executable the shell launches. The following is an illustrative local Windows `global.json` (not a file to create during this lesson):

```json
{
  "sdk": {
    "version": "10.0.401",
    "rollForward": "disable",
    "paths": [
      "C:\\Tools\\dotnet-preview",
      "$host$"
    ]
  }
}
```

**Interpretation:**

- `version` asks for SDK `10.0.401`; `rollForward: disable` insists on an exact match.
- The first `paths` entry points to an additional SDK *installation root*. It is **not** a path to `dotnet.exe`.
- `$host$` means the SDK location associated with the already-running `dotnet` host. It is a special SDK search entry, not a shell variable to expand.
- The supported resolver searches the listed roots in order for a compatible SDK. The host *might* have been started from `C:\Program Files\dotnet\dotnet.exe` while the selected SDK comes from the separate SDK installation root.

**If a .NET 10+ host finds the version only through the first entry, it can use that SDK without modifying system `PATH`.** If neither location has a compatible SDK, resolution fails. Older hosts ignore `sdk.paths`, so this example must not be treated as universal across all versions.

Other influences do not need a full lesson yet: preview SDKs may be considered differently inside and outside Visual Studio; x86, x64 and Arm64 host installations can expose different SDK inventories; editor builds and CI tasks may launch a different `dotnet` than your interactive shell. Each is a reason to examine **actual host, actual environment, and actual SDK policy** rather than assume that “latest installed” answers everything.

### Optional advanced SDK checkpoint

**Q6 (optional).** Which layer does `sdk.paths` influence: shell executable lookup, SDK selection, or application runtime selection?

Need a hint? Revisit [additional SDK influences](#additional-influences-to-recognize-not-memorize-yet), then [A6](#a6) after your optional attempt.

**Transition:** We've seen how .NET selects the SDK used to build an application. **How does it select the runtime that executes that application?**

## Concept 3: Understanding Application Runtime Selection

### Why does runtime selection matter?

The developer who installed SDK 10 still has an application targeting .NET 8. Does the application now execute on runtime 10? **Not necessarily.** SDKs build programs; runtimes execute them. Misunderstanding this can lead to trying to fix an application-launch problem by editing SDK configuration.

### Which components run an application?

The .NET runtime supports managed execution, memory management and garbage collection. It may be installed without an SDK. Several shared-framework families exist:

| Shared framework | Responsibility |
| --- | --- |
| `Microsoft.NETCore.App` | Core runtime and base libraries |
| `Microsoft.AspNetCore.App` | Shared framework used by ASP.NET Core apps |
| `Microsoft.WindowsDesktop.App` | Windows desktop application frameworks |

An app can require multiple frameworks. Installing only the core shared framework doesn't automatically satisfy an ASP.NET Core requirement.

### How runtime roll-forward differs from SDK roll-forward

A framework-dependent application ordinarily expresses its runtime request in a generated `runtimeconfig.json`. Runtime roll-forward applies **runtime-specific rules**, not the SDK's `global.json` rules.

Under the normal default runtime **`Minor`** policy, the resolver selects the highest eligible patch in the requested major/minor line, and may advance to a higher minor in the **same major** if needed. It doesn't automatically advance to a newer major version. Runtime settings and launch context can override the default.

### Why runtime inventory isn't runtime selection

Consider the third selection layer. For an installed host you can run:

```powershell
dotnet --list-runtimes
```

Illustrative abbreviated output:

```text
Microsoft.NETCore.App 8.0.15 [C:\Program Files\dotnet\shared\Microsoft.NETCore.App]
Microsoft.NETCore.App 10.0.5 [C:\Program Files\dotnet\shared\Microsoft.NETCore.App]
```

This lists runtimes the current host can see. **It does not tell you which runtime every application will use.** That depends on a particular application's runtime configuration and applicable runtime-selection rules. A machine may select SDK `10.0.401` for a build yet run an application using a .NET 8 runtime. SDK selection and runtime selection answer different questions.

### Worked example: SDK 10 builds a .NET 8 application

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


### Common misconceptions and failures

| Misconception | Better explanation |
| --- | --- |
| "SDK 10 built the app, so it runs on runtime 10." | Development SDK and app runtime are different selections. |
| "The highest installed runtime always runs." | Application requirements and runtime roll-forward govern selection. |
| "`--list-runtimes` tells me what my app used." | It reports inventory, not app-execution evidence. |
| "Runtime 10 always replaces missing runtime 8." | Default runtime policy does not cross major versions. |
| "An SDK must be installed to run an app." | A framework-dependent app may run with a compatible runtime alone. |
| "Every app uses an installed shared runtime." | Self-contained deployments carry their own runtime. |

If a framework-dependent `net8.0` app requires `Microsoft.NETCore.App 8.0.0` and **only runtime 10.0.5** is visible, normal default resolution can fail with a missing-framework error. This isn't evidence the SDK is broken. Check the app's runtime configuration, compatible framework inventory, architecture, effective roll-forward and actual launch. Changing `global.json` does not directly satisfy the app's runtime requirement.

### Put all three decisions together

```text
Shell / calling process
         |
1. Executable resolution
         |
      .NET host
       /     \
SDK operation  Application launch
      |             |
2. SDK choice  3. Runtime choice
      |             |
 Build tools    App execution
```

**An inventory is not a selection.** The installed SDKs, installed runtimes and an application's actual loaded runtime answer different questions.

### Revisiting our developer

Installing SDK 10 didn't necessarily change the host PowerShell launched. It may have changed the selected SDK for a development operation under normal policy. It didn't automatically change the runtime used by every existing app.

### Check your understanding — Concept 3

**Q7.** A host lists `Microsoft.NETCore.App 8.0.15` and `10.0.5`. A framework-dependent `net8.0` app requests `Microsoft.NETCore.App 8.0.0`. Which runtime would it normally select under default policy? Why doesn't the installed-runtime inventory alone prove what any particular app loaded?

**Q8 — Capstone.** A developer says: "I installed SDK 10. `dotnet --version` says 10.0.401, so my `dotnet.exe` is version 10.0.401 and every app runs on .NET 10." Separate the supported observation from unsupported conclusions, and explain what evidence each other decision requires.

Need a hint? Revisit [the runtime scenario](#worked-example-sdk-10-builds-a-net-8-application) and [inventory versus selection](#why-runtime-inventory-isnt-runtime-selection), then consult [A7](#a7) and [A8](#a8).

## Answer key and self-assessment

**Use after attempting the questions.** An adequate answer explains the mechanism, not merely the command spelling.

### A1

The shell decides which `dotnet` command is resolved, considering aliases/functions, executable lookup and `PATH`. Installing the newest SDK alone doesn't establish what starts.

### A2

A full path fixes the **host executable file**, but not necessarily the selected SDK under applicable SDK policy or which runtime an application executes with.

### A3

`dotnet --version` identifies the **selected SDK**, not the host binary's file version or runtime a particular application uses.

### A4

Yes. The same host can select different SDKs because working directory, applicable `global.json` and SDK policy can differ.

### A5

No. With `"rollForward": "disable"`, exact SDK availability is required. The CLI fails rather than silently choose an unrelated SDK.

### A6

`sdk.paths` influences SDK discovery on supporting .NET 10+ hosts, not shell command lookup or application runtime selection.

### A7

With the stated conditions, default runtime roll-forward would ordinarily select `Microsoft.NETCore.App 8.0.15`. The list doesn't prove what a particular app loaded: app configuration, launch, policy, hosting architecture and actual execution evidence matter.

### A8

The only established fact is that the invoked `dotnet --version` selected **SDK 10.0.401**. It does not establish the host file's version, every project's SDK, or every app's runtime. Investigate executable identity, SDK selection policy, and application runtime configuration/execution separately.

### Session 1 pass criteria

The learner can explain executable, SDK and runtime resolution; what governs them; why an inventory isn't a selection; and how to diagnose unsupported assumptions. **Required checkpoints:** Q1–Q5, Q7–Q8. **Optional advanced:** Q6. The hands-on activity below is entirely optional; live commands and application launches are not needed to pass.

## Try it yourself — Explore your own .NET installation

**Optional hands-on practice (about 5–10 minutes).** You've already learned the three decisions and attempted Q1–Q8. Now see what the same questions look like on a real computer. Your version numbers will probably differ from the examples; the goal is to explain **what your findings establish**, not to reproduce an expected output. This is practice, not another assessment.

If you don't have .NET installed, prefer not to run commands, or encounter an error, **skip the commands** and use the worked examples in Concepts 1–3 to answer the interpretation prompts. Do not install or remove an SDK, edit `PATH` or `global.json`, or build or launch an application just for this activity. As noted at the start, the .NET CLI may perform normal first-run setup or telemetry. If you share command output, remove usernames, personal paths, or other private details.

### Step 1 — Which executable does your shell resolve?

Choose the command appropriate for your shell.

**Windows / PowerShell**

```powershell
Get-Command dotnet -All | Select-Object CommandType, Name, Source, Definition
```

**Linux or macOS / Bash**

```bash
type -a dotnet
```

**Interpret:** Which command is first? Is it a native executable, alias, or function? If multiple candidates appear, which would your *current shell* use? Can you conclude that no other `dotnet` installations exist elsewhere on the computer? Revisit [executable resolution](#which-dotnetexe-does-the-shell-start) if needed.

If no `dotnet` command is found, that's a valid result; don't install anything to continue.

### Step 2 — Which SDK does that host select?

If `dotnet` is available in your shell, run these commands in the **same working directory**:

```text
dotnet --version
dotnet --list-sdks
dotnet --info
```

**Interpret:** What SDK version does `--version` select, if any? What other SDKs can this invocation see? Which SDK `Base Path` and `Host` version does `--info` report? Why must the host version and selected SDK version not be confused? Does any of this prove what SDK would be selected from *another* directory? Revisit [SDK selection](#concept-2-understanding-how-net-selects-an-sdk) if needed.

If selection fails or only runtime components are installed, record the failure instead of changing your machine. You can still explain what the commands were meant to show.

### Step 3 — Which runtimes are available?

If `dotnet` is available, run:

```text
dotnet --list-runtimes
```

**Interpret:** Which shared-framework families and versions are listed? Are some runtime versions present without matching SDK versions? Is that necessarily a problem? Most importantly, **can this inventory tell you which runtime a particular application actually loaded?** Revisit [runtime inventory versus selection](#why-runtime-inventory-isnt-runtime-selection) if needed.

**Evidence boundary:** This command reveals runtime *inventory*, not execution. Proving which runtime an application loaded would require a specific application, its runtime requirements, its launch context and evidence from execution. That experiment is **not required** here.

### Put your findings together

| Decision | Observation from your computer (if available) | What you can conclude |
| --- | --- | --- |
| **Executable** | Shell command type and path | The command your current shell resolves; not a whole-disk inventory |
| **SDK** | Selected SDK, SDK list and `Base Path` | What this invocation selected and could find, under its context |
| **Runtime** | Listed shared-framework versions | What frameworks are visible; **not** what a specific app loaded |

**Final reflection:** If your host, SDK and runtime version numbers differ, is that automatically evidence of a problem? Explain which decision each observation belongs to and identify **one conclusion your commands cannot justify**.

This activity adds **no new required questions**. If you're learning with an AI instructor, you can optionally share *sanitized* results and ask it to help interpret them; it should never claim to have inspected your machine.

**Source observations kept for future review:** The project's [original Windows installation observations](windows-dotnet-installation-observations.md) are preserved separately. They are not an assigned example or an approved teaching walkthrough, and you do not need to compare your results against them.

## Microsoft references

- [.NET distribution packaging](https://learn.microsoft.com/en-us/dotnet/core/distribution-packaging)
- [.NET CLI](https://learn.microsoft.com/en-us/dotnet/core/tools/)
- [`global.json` and SDK roll-forward](https://learn.microsoft.com/en-us/dotnet/core/tools/global-json)
- [.NET runtime version selection](https://learn.microsoft.com/en-us/dotnet/core/versions/selection)
- [.NET runtime configuration](https://learn.microsoft.com/en-us/dotnet/core/runtime-config/)
- [Installed version detection](https://learn.microsoft.com/en-us/dotnet/core/install/how-to-detect-installed-versions)
- [PowerShell Get-Command](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/get-command)

## Next session

[Session 2 — Understanding Isolated .NET SDK (Issue #213)](https://github.com/infoconex/isolated-dotnet-sdk/issues/213) applies these Microsoft fundamentals to product behavior. Product-version, isolated-installation and Verify examples from the earlier draft are preserved in that issue's linked historical sources.

---

*Pilot note: Q1–Q8 map to A1–A8 here and the same questions in the AI instructor guide.*
