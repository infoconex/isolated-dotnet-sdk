[CmdletBinding(DefaultParameterSetName = 'Check')]
param(
    [Parameter(ParameterSetName = 'Check')]
    [switch]$Check,

    [Parameter(Mandatory, ParameterSetName = 'Write')]
    [switch]$Write
)

$ErrorActionPreference = 'Stop'
$IsCheck = $Check -or -not $Write

$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$VersionConfigPath = Join-Path $RepositoryRoot '.config/static-analysis.json'

try {
    $VersionConfig = Get-Content -LiteralPath $VersionConfigPath -Raw -ErrorAction Stop |
        ConvertFrom-Json -ErrorAction Stop
    $RequiredVersionValue = [string]$VersionConfig.psScriptAnalyzerVersion
    if ([string]::IsNullOrWhiteSpace($RequiredVersionValue)) {
        throw 'psScriptAnalyzerVersion must be a non-empty string.'
    }
    $RequiredVersion = [version]$RequiredVersionValue
}
catch {
    [Console]::Error.WriteLine(
        "Unable to read the pinned PSScriptAnalyzer version from $VersionConfigPath. $($_.Exception.Message)")
    exit 2
}

try {
    Import-Module PSScriptAnalyzer -RequiredVersion $RequiredVersion -ErrorAction Stop
}
catch {
    [Console]::Error.WriteLine(
        "PSScriptAnalyzer $RequiredVersion is required. Install it with: Install-Module PSScriptAnalyzer -RequiredVersion $RequiredVersion -Scope CurrentUser")
    exit 2
}

$FormattingPaths = @(
    (Join-Path $RepositoryRoot 'isolated-dotnet-sdk.ps1')
)

$ChangedPaths = @()

foreach ($Path in $FormattingPaths) {
    $Original = [System.IO.File]::ReadAllText($Path)
    $OriginalUsesCrLf = $Original.Contains("`r`n")
    $NormalizedOriginal = $Original.Replace("`r`n", "`n")
    $Formatted = Invoke-Formatter -ScriptDefinition $Original
    $NormalizedFormatted = $Formatted.Replace("`r`n", "`n")

    if ($NormalizedOriginal -eq $NormalizedFormatted) {
        continue
    }

    $ChangedPaths += $Path

    if (-not $IsCheck) {
        $Output = if ($OriginalUsesCrLf) {
            $NormalizedFormatted.Replace("`n", "`r`n")
        }
        else {
            $NormalizedFormatted
        }

        [System.IO.File]::WriteAllText(
            $Path,
            $Output,
            [System.Text.UTF8Encoding]::new($false))
    }
}

if (-not $IsCheck) {
    if ($ChangedPaths.Count -eq 0) {
        Write-Output "PowerShell formatting already satisfied for $($FormattingPaths.Count) file(s)."
    }
    else {
        Write-Output "Formatted $($ChangedPaths.Count) PowerShell file(s):"
        $ChangedPaths | ForEach-Object {
            Write-Output "  $([System.IO.Path]::GetRelativePath($RepositoryRoot, $_))"
        }
    }

    exit 0
}

if ($ChangedPaths.Count -gt 0) {
    foreach ($Path in $ChangedPaths) {
        [Console]::Error.WriteLine(
            "Formatting required: $([System.IO.Path]::GetRelativePath($RepositoryRoot, $Path))")

        $Original = [System.IO.File]::ReadAllText($Path)
        $Formatted = Invoke-Formatter -ScriptDefinition $Original
        $TemporaryPath = [System.IO.Path]::GetTempFileName()
        try {
            [System.IO.File]::WriteAllText(
                $TemporaryPath,
                $Formatted,
                [System.Text.UTF8Encoding]::new($false))
            $Diff = @(& git diff --no-index -- $Path $TemporaryPath 2>&1)
            [Console]::Error.WriteLine('FORMATTER-DIFF-BEGIN')
            foreach ($Line in $Diff) {
                [Console]::Error.WriteLine([string]$Line)
            }
            [Console]::Error.WriteLine('FORMATTER-DIFF-END')
        }
        finally {
            Remove-Item -LiteralPath $TemporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
    [Console]::Error.WriteLine(
        'Run: pwsh -NoProfile -File ./scripts/Invoke-PSFormatter.ps1 -Write')
    exit 1
}

Write-Output "PowerShell formatting check passed for $($FormattingPaths.Count) file(s) with PSScriptAnalyzer $RequiredVersion."
