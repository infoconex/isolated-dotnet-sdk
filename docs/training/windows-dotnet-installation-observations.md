# Windows .NET installation observations — preserved source notes

**Status: Preserved reference material; not an approved curriculum case study.**

This document retains the owner-supplied Windows command-output and screenshot transcriptions formerly included in the Session 1 self-paced curriculum, together with their existing explanations, qualifications, and references. It is being kept so none of those observations are lost while we decide **whether, how, and where** the information should be taught.

**Do not treat the current organization, interpretations, length, or exercises as endorsed for the Session 1 pedagogical pilot.** Session 1's [core curriculum](isolated-dotnet-sdk-session-1-self-paced.md) and its [AI instructor guide](isolated-dotnet-sdk-session-1-ai-instructor.md) do not require this document. Learners need not read or execute anything here to complete Q1–Q8.

**Evidence provenance:** These are sanitized results supplied by the project owner, not observations gathered independently for this document. Screenshot details are transcribed; the original images are not embedded. The evidence does not establish what runtime any particular application loaded. The source content below is intentionally retained in its prior form pending a separate editorial review; references to the original lesson or to optional exercises are historical, not instructions to current learners.

---

## Optional evidence walkthrough: a real Windows .NET installation

**Status: owner-supplied, sanitized observations.** The project owner provided these command results from **PowerShell 7.6.6** and also supplied a screenshot of Windows **Installed Apps** filtered to `.net`. The CLI output here is sourced from that provided terminal transcript: we did **not** independently execute the commands or capture the screenshot. Unlike earlier hypothetical examples, these version numbers are *observed* from the provided transcript.

**Sanitization and limits:** The owner's Windows username and terminal prompt have been omitted; standard Microsoft installation paths, SDK/runtime versions, and reported metadata remain unchanged. `dotnet --info` is excerpted to avoid duplicating the full SDK and runtime lists preserved separately below. This is a snapshot from **one system, one PowerShell environment, and one working-directory context**, not a universal claim about other machines.

### Observation 1: Which executable does PowerShell find?

```powershell
Get-Command dotnet -All | Format-Table CommandType, Name, Source -AutoSize
```

Observed output:

```text
CommandType Name       Source
----------- ----       ------
Application dotnet.exe C:\Program Files\dotnet\dotnet.exe
```

**Explanation:** `Application` means PowerShell found a native executable. `Source` identifies its full location: **`C:\Program Files\dotnet\dotnet.exe`**. Only one `dotnet` command candidate appeared in this session. This result answers **which executable PowerShell resolves**, not which SDK version it selects and not which runtime starts an application. Another `dotnet.exe` could exist outside `PATH` without appearing here.

**If you see more rows:** PowerShell might see another executable, function, or alias. Inspect command precedence and paths first; do not confuse multiple executable candidates with multiple installed SDKs.

### Observation 2: Which SDK does that host select?

```powershell
dotnet --version
```

Observed output:

```text
10.0.402
```

**Explanation:** **`10.0.402` is the selected Microsoft .NET SDK.** It is *not* the version of the `dotnet.exe` file or the runtime used by every application. The owner's `dotnet --info` report says `global.json file: Not found`. The host's SDK inventory below lists `10.0.402` as the highest available SDK, explaining this result in the observed context.

**If the result changes in another directory:** A different applicable `global.json` or SDK search policy may be involved, even if PowerShell still launches the same executable.

### Observation 3: What else does `dotnet --info` reveal?

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

### Observation 4: Which SDKs does this host see?

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

**Explanation:** Four SDKs are visible to the **normally resolved system host**. Each row combines a complete SDK version with the SDK root directory in brackets. `dotnet --version` selected `10.0.402`, but the other three remain installed and could be selected under different compatible SDK policies. Another SDK root could exist elsewhere without appearing in this host's inventory.

### Observation 5: Which runtimes does this host see?

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

### Observation 6: What does Windows *Installed Apps* show?

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
5. An SDK in another installation root can exist without a normal Windows Installed Apps registration; likewise, an installer registration alone doesn't prove a particular host sees the SDK.
6. **Microsoft .NET Framework** (the older Windows-specific product family) is different from modern `Microsoft.NETCore.App` shared framework versions; don't combine their inventories.

**Next step only if diagnosis is needed:** To determine which installer owns a component or which specific application uses an older runtime, collect targeted installer/application evidence. Don't infer dependency or usage from the two version lists alone, and **don't remove anything during training**.

For comparison, Microsoft's [installed-versions instructions](https://learn.microsoft.com/en-us/dotnet/core/install/how-to-detect-installed-versions) use `--list-sdks` and `--list-runtimes`, while its [Windows removal guidance](https://learn.microsoft.com/en-us/dotnet/core/install/remove-runtime-sdk-versions?pivots=os-windows) explains the Installed Apps and Visual Studio Installer surfaces.

### Observation 7: What version is the actual `dotnet.exe` file?

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

**If the versions don't match:** First confirm that the binary whose properties you opened is the one PowerShell resolves (`Get-Command dotnet -All`). It is possible to examine the properties of one host file while executing another because of `PATH`, aliases, explicit paths, or architecture differences. Keep the executable's Windows metadata distinct from its selected SDK: a newer SDK does not mean `dotnet.exe` must have that SDK's exact version number. Finally, don't interpret this small native executable's **163 KB** size as the space occupied by the associated runtimes, SDK, or user-owned isolated installations.

### Additional filesystem evidence: hostfxr, SDKs, and workload manifests

Three extra terms help us interpret actual .NET installation folders:

| Additional term | Plain-language meaning |
| --- | --- |
| **`hostfxr` (host framework resolver)** | A native .NET hosting component stored under `host/fxr`. It helps resolve SDKs and shared runtimes after a `dotnet` host starts. It is **not** an SDK, not an app runtime, and not another `dotnet.exe` for every folder. |
| **SDK feature band** | A grouping of related SDK releases, reflected in versions such as `10.0.400` (the feature band for SDK `10.0.402`). Feature-band names can appear in workload-related metadata; they are **not** a list of installed SDK patch versions. |
| **Workload / workload manifest** | An optional development capability (such as platform-specific tooling), and metadata describing the assets needed for those workloads. A manifest folder alone **does not** mean a workload is installed. |

#### Observation 8: A real Windows installation: three folders that look similar but mean different things

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
  shared\                <-- runtime frameworks (studied in this walkthrough)
```

**First, look at `host\fxr`.** Each numbered folder contains a version of the **host framework resolver** (`hostfxr`), which participates in choosing compatible .NET components. The folders **6.0.36**, **7.0.20**, **8.0.32**, **9.0.21**, **10.0.12**, and **10.0.13** do **not** mean six different SDKs are installed or that every application loads all six hostfxr versions. Microsoft's host typically selects an appropriate hosting component during startup. The screenshot itself **does not prove which hostfxr DLL was loaded by a particular process**.

**Next, look at `sdk`.** These four directories are the actual installed **SDK versions**: **8.0.426**, **9.0.319**, **10.0.401**, and **10.0.402**. Compare them with [Observation 4's `dotnet --list-sdks` result](#observation-4-which-sdks-does-this-host-see): all four appear there. An SDK directory is a collection of build/development tooling, not another hostfxr version or a shared application runtime.

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

Microsoft documents the directory roles in [.NET distribution packaging](https://learn.microsoft.com/en-us/dotnet/core/distribution-packaging) and explains the difference between installed workloads and manifest metadata in [`dotnet workload list`](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-workload-list). No workload installation is part of Session 1.

### Put the observations together

| Question | Relevant evidence | Actual finding or limit |
| --- | --- | --- |
| Which executable does PowerShell resolve? | `Get-Command dotnet -All` | `C:\Program Files\dotnet\dotnet.exe` (native Application) |
| Which SDK is currently selected? | `dotnet --version` | **10.0.402** |
| Where are the selected SDK's files? | `dotnet --info` → `Base Path` | `C:\Program Files\dotnet\sdk\10.0.402\` |
| What hosting-component version is reported? | `dotnet --info` → `Host Version` | **10.0.13** (x64) |
| What are the executable's Windows versions? | `dotnet.exe` Properties → Details | **Product 10.0.13; File 10.0.1326.50504**; separately from SDK **10.0.402** |
| Which system-host SDK versions are visible? | `dotnet --list-sdks` | **8.0.426, 9.0.319, 10.0.401, 10.0.402** |
| Which runtime frameworks are visible? | `dotnet --list-runtimes` | Several .NET Core, ASP.NET Core, and Windows Desktop runtime versions; includes **6.0/7.0 runtimes without corresponding visible SDKs** |
| What does the Windows Settings screenshot establish? | Installed Apps filter `.net` → **4 apps found** | Four x64 SDK registrations, including one Visual Studio-managed entry; **not** a complete runtime inventory |
| Which runtime did *a particular application* use? | Would require application-specific evidence | **Not determined** by these six commands or the Installed Apps screenshot |

**Takeaway:** A file's Windows version properties, the host's reported product version, and the selected SDK version can all be different values. “What version of .NET do I have?” is incomplete. First ask **which program is running**, **which SDK it selects**, **which host components are reported**, **which runtimes can be discovered**, **which runtime a specific app uses**, and **which installation-management interface is being viewed**. These are different questions with different evidence.

No new required checkpoint is introduced. Q1–Q8 remain independent of the owner's machine and versions.

---
