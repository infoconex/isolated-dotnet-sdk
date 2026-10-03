# Source formatting

This repository enforces source formatting only where the consistency benefit justifies the tooling and maintenance cost.

## PowerShell

PowerShell formatting is repository-enforced through `Invoke-Formatter` from the already-required PSScriptAnalyzer module.

The PSScriptAnalyzer version is pinned in `.config/static-analysis.json`, so formatter behavior changes only through an intentional analyzer-version update. Reusing that dependency avoids introducing a second PowerShell formatting tool or a separate version source.

Formatting enforcement applies to the product PowerShell script:

- `isolated-dotnet-sdk.ps1`

Use the repository runner for both checking and applying formatting:

```powershell
pwsh -NoProfile -File ./scripts/Invoke-PSFormatter.ps1 -Check
pwsh -NoProfile -File ./scripts/Invoke-PSFormatter.ps1 -Write
```

The runner requires the exact PSScriptAnalyzer version declared by `.config/static-analysis.json`. CI installs that version before invoking the formatting check.

## Bash

No additional Bash formatter is adopted at this time.

`shfmt` is an established formatter and can provide deterministic formatting, but adding it would introduce another executable dependency, version/integrity metadata, installation path, and update obligation solely for source presentation. The current Bash source already follows a consistent repository style, while ShellCheck provides the materially higher-value correctness and portability checks.

For this repository's current size and style consistency, the incremental benefit does not justify the added tooling. This decision can be revisited if formatting drift becomes recurring review noise or the Bash surface grows substantially.

Bash continues to use:

- `bash -n` for syntax validation;
- the pinned repository-owned ShellCheck runner for static analysis;
- focused review for source-style consistency.

## Policy boundaries

Formatting changes must remain mechanical. Do not combine formatter-driven normalization with semantic refactoring, naming changes, or behavior changes.

Repository formatting policy is intentionally source-focused. It does not establish editor/IDE configuration or broad contributor workstation policy.
