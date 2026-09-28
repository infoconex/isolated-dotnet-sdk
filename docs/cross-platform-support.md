# Cross-platform support contract

The repository supports one implementation per operating-system family:

| Supported platform | Product entry point | Validation mapping |
| --- | --- | --- |
| Windows | `isolated-dotnet-sdk.ps1` under PowerShell 7 | `windows-latest` PowerShell job |
| Linux | `isolated-dotnet-sdk.sh` under Bash | `ubuntu-latest` Bash job |
| macOS | `isolated-dotnet-sdk.sh` under Bash | `macos-latest` Bash job |

This matrix is the supported product contract. PowerShell on Linux/macOS and Bash on Windows are not currently supported product combinations. Expanding that matrix requires separate requirements rather than incidental compatibility work.

## Runtime and tool assumptions

The product scripts intentionally use shell-native facilities and a small set of platform tools.

- Windows execution requires PowerShell 7. The repository validation suite currently requires PowerShell 7.4 or newer because of the pinned Pester major version.
- Linux/macOS execution requires Bash plus standard Unix tools used by the script (`awk`, `grep`, `sed`, `tr`, `mktemp`, `chmod`, `mv`, `rm`, and `curl`).
- Bash installer-integrity verification accepts either `sha256sum` or `shasum -a 256`; this is the deliberate GNU/Linux versus macOS portability boundary.
- Product SDK operations use the platform's .NET host name: `dotnet.exe` on Windows and executable `dotnet` on Linux/macOS.
- Repository validation has additional development dependencies documented in [`testing.md`](testing.md), including Pester, Bats-core, PSScriptAnalyzer, ShellCheck, Git, and `jq`.

No supported product path should depend on a developer-specific absolute path. Persistent state is derived from the current user's home/profile and lives under that user's `dotnet-sdks` directory.

## Paths and filesystem semantics

PowerShell uses .NET/PowerShell path APIs such as `Join-Path` and `[System.IO.Path]`; Bash quotes path expansions and constructs paths using `/`. Paths containing whitespace are supported and must remain quoted correctly through bootstrap, saved-tool execution, and SDK operations.

The tool does not define a synthetic cross-platform case-normalization layer. Path and filename case behavior follows the host filesystem and runtime. Product correctness must not depend on a case-sensitive or case-insensitive filesystem beyond platform-native host naming (`dotnet.exe` versus `dotnet`).

Bootstrap candidates, release-metadata temporary files, install helpers, and SDK staging directories are created under the isolated SDK root. Keeping replacement/promotion on the same root avoids introducing cross-filesystem rename assumptions into normal product behavior.

Filesystem failure mechanics differ by operating system. Windows may reject replacement/deletion because a file is locked or in use; Unix-like systems more commonly surface permission or directory-entry failures. The portable contract is the observable result already defined in [`filesystem-safety.md`](filesystem-safety.md): failure propagates, destructive scope does not broaden, recovery state is preserved where specified, and success is not reported falsely.

Timing-sensitive native locking races are not a repository validation requirement when deterministic injected failures establish the same public contract more reliably.

## Unix executable-bit behavior

The saved Bash tool is intended to be directly executable. Bootstrap writes a staged candidate, applies `chmod +x`, and promotes it only after that step succeeds. Losing the executable bit is therefore a product defect even if `bash isolated-dotnet-sdk.sh` could still interpret the file explicitly.

Installed isolated SDK discovery on Linux/macOS likewise recognizes only version directories containing an executable `dotnet` host. Windows uses the platform-appropriate `dotnet.exe` existence check instead.

## Shell invocation and argument forwarding

File-based bootstrap preserves the exact current script bytes before re-execution. PowerShell re-invokes the saved script using native PowerShell argument binding; Bash uses `exec` with the original argument vector. The mechanisms differ intentionally, but both must preserve the saved tool's result and must handle home/tool paths containing whitespace without argument splitting.

Operational native-command failures remain subject to [`native-command-failures.md`](native-command-failures.md). Exact numeric exit codes need not be identical across runtimes unless a narrower contract says otherwise.

## Interactive, non-interactive, and terminal behavior

Automation should supply the action and exact version whenever interactive selection would otherwise be required. Unavailable required input is an operational failure; explicit user cancellation remains a successful no-change result. The shared behavior is specified in [`behavioral-parity.md`](behavioral-parity.md).

Presentation remains shell-native:

- PowerShell uses semantic streams and `$PSStyle`; redirected information output must remain free of ANSI escape sequences.
- Bash enables ANSI decoration only when standard output is a terminal (`[[ -t 1 ]]`). Captured or redirected Bash output must therefore remain ANSI-free.

Byte-for-byte output or identical stream mechanics are not required across shells.

## CI and validation scope

The `Validate` workflow maps product implementations to the supported operating systems:

- Bash syntax and Bats behavioral tests run on both Ubuntu and macOS;
- ShellCheck runs on Ubuntu;
- PowerShell parser validation, PSScriptAnalyzer, formatting checks, and Pester behavioral tests run on Windows.

This mapping validates the supported product combinations while avoiding unsupported shell/OS combinations. It does not claim that hosted-runner image versions themselves are a long-term reproducibility policy; runner assumptions and pinning remain Issue #28.

## Boundaries

This document records platform support and intentional mechanics. It does not:

- expand support to PowerShell-on-Unix or Bash-on-Windows;
- require identical implementation structure across shells;
- add compatibility layers for hypothetical case, path, or locking behavior;
- replace deterministic failure injection with timing-sensitive native races;
- redesign stable bootstrap or supply-chain policy from Issues #21/#22;
- redesign CI runner-image reproducibility owned by Issue #28;
- perform the broader CLI/help and operational-documentation work owned by Issue #23.
