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
    throw "Pester $expectedVersion is required. See docs/maintainers/testing/testing.md."
}

Import-Module Pester -RequiredVersion $expectedVersion -Force

$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-shared-host-{0}" -f [guid]::NewGuid())
$fixtureTimer = [System.Diagnostics.Stopwatch]::StartNew()
$suiteTimer = [System.Diagnostics.Stopwatch]::StartNew()

try {
    $sharedHostRoot = & (Join-Path $PSScriptRoot 'New-FakeDotNetHost.ps1') -OutputRoot $fixtureRoot
    if ([string]::IsNullOrWhiteSpace($sharedHostRoot) -or -not (Test-Path -LiteralPath $sharedHostRoot -PathType Container)) {
        throw 'Shared deterministic fake dotnet host was not created.'
    }
    $fixtureTimer.Stop()
    $env:ISOLATED_DOTNET_SDK_SHARED_FAKE_HOST_ROOT = $sharedHostRoot
    Write-Output ("Shared fake dotnet host setup: {0:N2}s" -f $fixtureTimer.Elapsed.TotalSeconds)

    $result = Invoke-Pester `
        -Path (Join-Path $PSScriptRoot '*.Tests.ps1') `
        -PassThru `
        -Output Detailed

    $suiteTimer.Stop()
    Write-Output ("PowerShell behavioral validation wall time: {0:N2}s" -f $suiteTimer.Elapsed.TotalSeconds)

    if ($result.Result -ne 'Passed') {
        exit 1
    }
}
finally {
    Remove-Item Env:ISOLATED_DOTNET_SDK_SHARED_FAKE_HOST_ROOT -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}
