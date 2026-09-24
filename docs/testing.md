# Testing

The repository keeps its behavioral assertions in repository-owned test scripts so the same checks can run locally and in GitHub Actions.

## Bash behavioral tests

From the repository root, run:

```bash
bash tests/bash/run-tests.sh
```

The Bash suite covers:

- isolated temporary `HOME` handling;
- file-based bootstrap source preservation;
- the `list` command;
- rejection of an invalid SDK version.

## PowerShell behavioral tests

PowerShell 7 (`pwsh`) is required. From the repository root, run:

```powershell
pwsh -NoProfile -File ./tests/powershell/run-tests.ps1
```

The PowerShell suite covers:

- isolated temporary home/profile handling;
- file-based bootstrap source preservation;
- the `List` action;
- rejection of an invalid SDK version.

## Static analysis

Static-analysis scope and version policy are documented in [`static-analysis.md`](static-analysis.md).

### PowerShell

PowerShell 7 and PSScriptAnalyzer `1.25.0` are required. Install the pinned module version for the current user:

```powershell
Install-Module PSScriptAnalyzer -RequiredVersion 1.25.0 -Scope CurrentUser -Repository PSGallery
```

Then run the repository-owned analyzer command from the repository root:

```powershell
pwsh -NoProfile -File ./scripts/Invoke-PSScriptAnalyzer.ps1
```

### Bash

ShellCheck `0.11.0` is required. Install that exact version using the upstream ShellCheck release appropriate for the local operating system, then verify it with:

```bash
shellcheck --version
```

Run the repository-owned analyzer command from the repository root:

```bash
bash scripts/run-shellcheck.sh
```

The runner rejects missing or mismatched ShellCheck versions so local analysis stays aligned with CI.

## Isolation

Both behavioral suites create temporary user/home state and clean it up when the run completes. They do not intentionally read from or modify the developer's real `~/dotnet-sdks` installation.

The current behavioral checks do not install an SDK or require release-metadata downloads.

## CI

`.github/workflows/validate.yml` runs:

- Bash syntax validation and the Bash behavioral suite on Ubuntu and macOS;
- ShellCheck once on Ubuntu;
- PowerShell parser validation and the PowerShell behavioral suite on Windows;
- PSScriptAnalyzer once on Windows.

Syntax/parser checks, static analysis, and behavioral tests remain separate validation layers.
