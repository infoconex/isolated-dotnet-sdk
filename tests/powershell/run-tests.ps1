$ErrorActionPreference = 'Stop'

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-tests-{0}" -f [guid]::NewGuid())
$testHome = Join-Path $testRoot 'home'
$homeVariableName = if ($IsWindows) { 'USERPROFILE' } else { 'HOME' }
$originalHomeValue = [Environment]::GetEnvironmentVariable($homeVariableName, 'Process')
$failure = $null

try {
    New-Item -ItemType Directory -Path $testHome -Force | Out-Null

    [Environment]::SetEnvironmentVariable($homeVariableName, $testHome, 'Process')
    $env:ISOLATED_DOTNET_SDK_EXPECTED_HOME = $testHome

    & pwsh -NoProfile -Command 'if ($HOME -ne $env:ISOLATED_DOTNET_SDK_EXPECTED_HOME) { [Console]::Error.WriteLine("Child PowerShell HOME did not match the isolated profile."); exit 1 }'
    if ($LASTEXITCODE -ne 0) {
        throw 'child PowerShell process did not use the isolated home/profile'
    }

    Write-Output 'PASS: isolated home/profile contract'
}
catch {
    $failure = $_.Exception.Message
}
finally {
    [Environment]::SetEnvironmentVariable($homeVariableName, $originalHomeValue, 'Process')
    Remove-Item Env:ISOLATED_DOTNET_SDK_EXPECTED_HOME -ErrorAction SilentlyContinue
    Remove-Item -Path $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($null -ne $failure) {
    [Console]::Error.WriteLine("FAIL: $failure")
    exit 1
}

Write-Output 'All PowerShell behavioral tests passed.'
