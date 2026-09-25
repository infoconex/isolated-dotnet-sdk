$ErrorActionPreference = 'Stop'

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

$AnalysisPaths = @(
    (Join-Path $RepositoryRoot 'isolated-dotnet-sdk.ps1'),
    (Join-Path $RepositoryRoot 'tests/powershell/run-tests.ps1'),
    (Join-Path $RepositoryRoot 'tests/powershell/run-removal-tests.ps1'),
    $PSCommandPath
)

try {
    Import-Module PSScriptAnalyzer -RequiredVersion $RequiredVersion -ErrorAction Stop
}
catch {
    [Console]::Error.WriteLine(
        "PSScriptAnalyzer $RequiredVersion is required. Install it with: Install-Module PSScriptAnalyzer -RequiredVersion $RequiredVersion -Scope CurrentUser")
    exit 2
}

$Findings = @(
    foreach ($Path in $AnalysisPaths) {
        Invoke-ScriptAnalyzer -Path $Path
    }
)

if ($Findings.Count -gt 0) {
    foreach ($Finding in $Findings) {
        Write-Output ("{0}:{1}:{2}: {3}: {4} [{5}]" -f `
            $Finding.ScriptName,
            $Finding.Line,
            $Finding.Column,
            $Finding.Severity,
            $Finding.Message,
            $Finding.RuleName)
    }

    [Console]::Error.WriteLine("PSScriptAnalyzer reported $($Findings.Count) finding(s).")
    exit 1
}

Write-Output "PSScriptAnalyzer $RequiredVersion passed for $($AnalysisPaths.Count) file(s)."
