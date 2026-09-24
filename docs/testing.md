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

## Isolation

Both suites create temporary user/home state and clean it up when the run completes. They do not intentionally read from or modify the developer's real `~/dotnet-sdks` installation.

The current behavioral checks do not install an SDK or require release-metadata downloads.

## CI

`.github/workflows/validate.yml` runs:

- Bash syntax validation and the Bash behavioral suite on Ubuntu and macOS;
- PowerShell parser validation and the PowerShell behavioral suite on Windows.

Syntax/parser checks remain CI tooling checks rather than behavioral test cases.
