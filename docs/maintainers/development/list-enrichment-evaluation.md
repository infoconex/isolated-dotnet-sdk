# List enrichment evaluation

This document records the maintainer decision on whether the default **List** operation should absorb the health information from **Verify** or the online servicing/lifecycle information from **Audit**.

## Decision

Keep the three operations separate:

- **List** remains local inventory.
- **Verify** remains an explicit local health check for one exact isolated SDK.
- **Audit** remains an explicit online lifecycle/update/security-servicing assessment.

Do not automatically verify every isolated SDK during List, and do not automatically fetch Microsoft release metadata during List.

The direct Verify and Audit commands remain useful for automation and troubleshooting, and the interactive Verify and Audit actions remain distinct because they perform materially different work from inventory.

## Measurement method

Measurements were collected on the repository's supported hosted-runner mappings:

- Windows 2025 with PowerShell 7;
- Ubuntu 24.04 with Bash;
- macOS 26 with Bash.

The evaluation used the production List and Audit commands from the normal per-user installed-tool path.

List measurements used recognized synthetic isolated inventory directories while preserving the runner's real system `dotnet --list-sdks` inventory. A second List series used synthetic System inventories of 1, 5, and 20 entries to isolate inventory-scaling cost.

The Verify prototype measured the dominant existing health-check cost: launching the runner's real `dotnet --list-sdks` once for each isolated SDK and applying the same exact-version membership decision in-process. It deliberately excluded repeated tool-script startup, because a folded List implementation would reuse the already-running process. This is therefore a better approximation of consolidation cost than invoking the public Verify command once per SDK. The proxy uses the runner's system host rather than a full isolated SDK tree, so absolute per-host timing is not treated as a contract; scaling and relative cost are the relevant evidence.

Audit was measured two ways:

1. the production Audit command against live Microsoft release metadata;
2. the same Audit algorithm against a local controlled metadata endpoint, changing only the temporary copy's release-index URL.

The controlled endpoint allowed deterministic request counting plus slow, unavailable, and malformed metadata scenarios. The slow scenario added 250 ms per metadata response.

Timing values below are medians from the evaluation run. They describe hosted-runner observations, not performance guarantees.

## Baseline List results

### Isolated inventory scaling

| Isolated SDKs | Windows | Ubuntu | macOS |
| ---: | ---: | ---: | ---: |
| 1 | 380.38 ms | 22.00 ms | 73.88 ms |
| 3 | 384.63 ms | 23.61 ms | 76.55 ms |
| 5 | 379.03 ms | 25.60 ms | 67.50 ms |
| 10 | 379.71 ms | 30.27 ms | 113.52 ms |
| 20 | 393.78 ms | 39.43 ms | 167.77 ms |

Windows List is dominated by PowerShell process startup in this measurement. Ubuntu remains very fast and scales gradually. macOS shows more filesystem/process variance, with larger inventories becoming noticeably slower but still remaining local.

### System inventory scaling

| System SDKs | Windows | Ubuntu | macOS |
| ---: | ---: | ---: | ---: |
| 1 | 384.71 ms | 14.18 ms | 40.12 ms |
| 5 | 386.70 ms | 16.83 ms | 44.15 ms |
| 20 | 385.92 ms | 26.76 ms | 55.80 ms |

Parsing and rendering larger System inventories is inexpensive compared with shell/process startup. The current List contract remains predictable and local.

## List plus Verify results

The healthy-inventory Verify proxy produced these incremental medians:

| Isolated SDKs checked | Windows | Ubuntu | macOS |
| ---: | ---: | ---: | ---: |
| 1 | 6.74 ms | 1.62 ms | 5.80 ms |
| 3 | 19.48 ms | 4.85 ms | 27.68 ms |
| 5 | 31.44 ms | 8.08 ms | 42.38 ms |
| 10 | 62.86 ms | 16.09 ms | 89.41 ms |
| 20 | 132.16 ms | 32.53 ms | 184.44 ms |

Mixed healthy/unhealthy checks had essentially the same scaling because the dominant cost is launching a host and enumerating SDKs, not classifying the result.

At 10 isolated SDKs, the approximate incremental cost over the corresponding List median was:

- Windows: +16.6%;
- Ubuntu: +53.2%;
- macOS: +78.8%.

At 20 isolated SDKs, it was approximately:

- Windows: +33.6%;
- Ubuntu: +82.5%;
- macOS: +109.9%.

### Verify consolidation decision

Do **not** verify every isolated SDK automatically during default List.

Reasons:

- the work scales linearly with isolated SDK count because each owned SDK must prove its own host health;
- the relative cost is substantial on Ubuntu and macOS as inventories grow;
- automatic verification would turn a simple inventory operation into a sequence of process launches;
- unhealthy isolated SDKs need per-item degradation semantics rather than being allowed to make basic inventory fragile;
- System SDKs still should not be subjected to isolated ownership/health checks, so consolidation would not eliminate the conceptual distinction;
- direct exact-version Verify remains valuable for automation and diagnostics;
- interactive Verify remains useful when the user intentionally wants a health check rather than inventory.

Parallel verification could reduce wall-clock time, but it would add process bursts, scheduling variance, implementation complexity, and new failure-ordering semantics. The current evidence does not justify adding that complexity to default List.

## List plus Audit results

### Live Audit

With five synthetic isolated entries plus the hosted runner's real System inventory, production Audit against live Microsoft metadata measured:

| Platform | Live Audit median |
| --- | ---: |
| Windows | 984.69 ms |
| Ubuntu | 3,244.07 ms |
| macOS | 8,917.91 ms |

The wide cross-platform/network variance is itself important. Even when Audit succeeds, its cost is qualitatively different from local inventory.

### Controlled request cost

For an inventory spanning two known channels, Audit made exactly three metadata requests:

1. one release-index request;
2. one channel-metadata request for .NET 10;
3. one channel-metadata request for .NET 8.

The implementation correctly reused channel metadata within one Audit invocation.

Against the local controlled endpoint, normal Audit medians were:

| Platform | Controlled normal |
| --- | ---: |
| Windows | 478.46 ms |
| Ubuntu | 184.81 ms |
| macOS | 676.79 ms |

Adding 250 ms of latency to each of the three responses raised medians to:

| Platform | Controlled slow |
| --- | ---: |
| Windows | 1,254.88 ms |
| Ubuntu | 939.02 ms |
| macOS | 1,421.36 ms |

Unavailable or structurally invalid release-index/channel metadata caused Audit to fail nonzero as designed. A separate List immediately afterward still succeeded and rendered inventory, confirming that the existing command boundary isolates basic local inventory from Audit availability.

### Repeated-session behavior

Two Audit selections in one interactive session made six requests: the same release index plus two channel-metadata requests were fetched again for the second Audit.

A short-lived session cache could reduce repeated Audit cost, but it would not remove the first network dependency, offline behavior, metadata failure handling, or the surprise of making List perform online work. Caching therefore does not change the consolidation decision.

### Audit consolidation decision

Do **not** add Audit enrichment to default List.

Reasons:

- live Audit added roughly one to nine seconds in this measurement, depending on platform/network path;
- request cost grows with the number of distinct known installed channels;
- degraded networks directly increase wall-clock time;
- unavailable or malformed metadata is an expected operational failure mode for Audit but must never make local inventory unavailable;
- automatically performing network work for List would be surprising compared with the current local contract;
- preserving inventory on enrichment failure would require a second set of partial-success semantics and presentation states such as `Audit unavailable`;
- direct and interactive Audit already provide an explicit place for users and automation to opt into current online metadata.

## Resulting CLI and interactive model

No consolidation is approved, so no command/menu simplification follows from this evaluation.

The intentional model remains:

- **List** — fast local inventory of Isolated and read-only System SDKs;
- **Verify** — explicit local exact isolated-SDK health check;
- **Audit** — explicit online servicing/lifecycle assessment of Isolated and System SDKs;
- **Install** — online acquisition and installation.

Keeping these boundaries makes cost and failure behavior visible in the command the user chooses.

## Revisit conditions

Revisit the decision only if a material product or implementation change alters the evidence, for example:

- isolated health can be established without launching each SDK host;
- Audit metadata becomes reliably available from a local trusted source;
- a broader UX redesign introduces an explicit enriched/online List mode rather than changing the default;
- measured usage shows that the separate actions cause more user friction than the latency and failure-isolation costs documented here.

A future evaluation should preserve the same core requirement: basic inventory must remain usable when optional health or online enrichment fails.
