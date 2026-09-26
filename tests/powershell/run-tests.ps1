$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$config = Get-Content -LiteralPath (Join-Path $repoRoot '.config/test-frameworks.json') -Raw |
    ConvertFrom-Json
$expectedVersion = [version][string]$config.pesterVersion

if ($null -eq $expectedVersion) {
    throw 'pesterVersion is required in .config/test-frameworks.json.'
}

$availablePester = Get-Module -ListAvailable -Name Pester |
    Where-Object { $_.Version -eq $expectedVersion } |
    Select-Object -First 1

if ($null -eq $availablePester) {
    throw "Pester $expectedVersion is required. See docs/testing.md."
}

Import-Module Pester -RequiredVersion $expectedVersion -Force

$result = Invoke-Pester `
    -Path (Join-Path $PSScriptRoot '*.Tests.ps1') `
    -PassThru `
    -Output Detailed

if ($result.Result -ne 'Passed') {
    exit 1
}
