$ErrorActionPreference = 'Stop'

$RequiredVersion = [version]'1.25.0'
$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$AnalysisPaths = @(
    (Join-Path $RepositoryRoot 'isolated-dotnet-sdk.ps1'),
    (Join-Path $RepositoryRoot 'tests/powershell/run-tests.ps1'),
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
