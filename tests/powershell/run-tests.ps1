$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-tests-{0}" -f [guid]::NewGuid())
$testHome = Join-Path $testRoot 'home'
$toolRoot = Join-Path $testHome 'dotnet-sdks'
$toolPath = Join-Path $toolRoot 'isolated-dotnet-sdk.ps1'
$sourceCopy = Join-Path $testRoot 'isolated-dotnet-sdk-source.ps1'
$listSuccessOutputPath = Join-Path $testRoot 'list-success.txt'
$listInformationOutputPath = Join-Path $testRoot 'list-information.txt'
$homeVariableName = if ($IsWindows) { 'USERPROFILE' } else { 'HOME' }
$originalHomeValue = [Environment]::GetEnvironmentVariable($homeVariableName, 'Process')
$failure = $null

function Write-Pass {
    param([string]$Message)
    Write-Output "PASS: $Message"
}

try {
    New-Item -ItemType Directory -Path $testHome -Force | Out-Null

    [Environment]::SetEnvironmentVariable($homeVariableName, $testHome, 'Process')
    $env:ISOLATED_DOTNET_SDK_EXPECTED_HOME = $testHome

    & pwsh -NoProfile -Command 'if ($HOME -ne $env:ISOLATED_DOTNET_SDK_EXPECTED_HOME) { [Console]::Error.WriteLine("Child PowerShell HOME did not match the isolated profile."); exit 1 }'
    if ($LASTEXITCODE -ne 0) {
        throw 'child PowerShell process did not use the isolated home/profile'
    }
    Write-Pass 'isolated home/profile contract'

    Copy-Item (Join-Path $repoRoot 'isolated-dotnet-sdk.ps1') $sourceCopy -Force
    Add-Content -Path $sourceCopy -Value "`n# bootstrap-source-marker"

    & pwsh -NoProfile -File $sourceCopy -Action List *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "file-based bootstrap failed with exit code $LASTEXITCODE"
    }

    if (-not (Select-String -Path $toolPath -Pattern '# bootstrap-source-marker' -SimpleMatch -Quiet)) {
        throw 'file-based bootstrap did not preserve the exact source script'
    }
    Write-Pass 'file-based bootstrap preserves source'

    $listOutput = @(& pwsh -NoProfile -File $toolPath -Action List 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "list command failed with exit code $LASTEXITCODE"
    }

    if (($listOutput -join [Environment]::NewLine) -notmatch 'Isolated SDKs under') {
        throw 'list output did not include the isolated SDK root heading'
    }
    Write-Pass 'list command'

    $env:ISOLATED_DOTNET_SDK_TOOL_PATH = $toolPath
    $env:ISOLATED_DOTNET_SDK_SOURCE_COPY = $sourceCopy
    $env:ISOLATED_DOTNET_SDK_LIST_SUCCESS = $listSuccessOutputPath
    $env:ISOLATED_DOTNET_SDK_LIST_INFORMATION = $listInformationOutputPath

    & pwsh -NoProfile -Command '$successPath = $env:ISOLATED_DOTNET_SDK_LIST_SUCCESS; $informationPath = $env:ISOLATED_DOTNET_SDK_LIST_INFORMATION; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action List 1> $successPath 6> $informationPath'
    if ($LASTEXITCODE -ne 0) {
        throw "list stream-contract command failed with exit code $LASTEXITCODE"
    }

    $listSuccessOutput = if (Test-Path -LiteralPath $listSuccessOutputPath) {
        Get-Content -LiteralPath $listSuccessOutputPath -Raw
    }
    else {
        ''
    }

    if (-not [string]::IsNullOrWhiteSpace($listSuccessOutput)) {
        throw 'list presentation unexpectedly wrote data to the success stream'
    }

    $listInformationOutput = if (Test-Path -LiteralPath $listInformationOutputPath) {
        Get-Content -LiteralPath $listInformationOutputPath -Raw
    }
    else {
        ''
    }

    if ($listInformationOutput -notmatch 'Isolated SDKs under' -or
        $listInformationOutput -notmatch 'None') {
        throw 'list presentation did not write the expected content to the information stream'
    }

    if ($listInformationOutput.Contains([char]27)) {
        throw 'default redirected information output contained ANSI escape sequences'
    }
    Write-Pass 'list output stream contract'

    & pwsh -NoProfile -Command '$PSStyle.OutputRendering = "Ansi"; $output = @(& $env:ISOLATED_DOTNET_SDK_SOURCE_COPY -Action List 6>&1); $text = $output -join [Environment]::NewLine; $expectedInfoPrefix = "$($PSStyle.Foreground.Cyan)isolated-dotnet-sdk:$($PSStyle.Reset)"; $expectedSuccessPrefix = "$($PSStyle.Foreground.Green)isolated-dotnet-sdk:$($PSStyle.Reset)"; if (-not $text.Contains($expectedInfoPrefix)) { [Console]::Error.WriteLine("ANSI rendering did not use the expected cyan informational prefix."); exit 1 }; if (-not $text.Contains("$expectedSuccessPrefix Tool installed.")) { [Console]::Error.WriteLine("ANSI rendering did not use the expected green success prefix."); exit 1 }'
    if ($LASTEXITCODE -ne 0) {
        throw 'ANSI presentation contract failed'
    }
    Write-Pass 'ANSI informational and success color contract'

    $originalNoColor = [Environment]::GetEnvironmentVariable('NO_COLOR', 'Process')
    try {
        [Environment]::SetEnvironmentVariable('NO_COLOR', '1', 'Process')
        & pwsh -NoProfile -Command '$output = @(& $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action List 6>&1); $text = $output -join [Environment]::NewLine; if ($PSStyle.OutputRendering -ne "PlainText") { [Console]::Error.WriteLine("NO_COLOR did not select PlainText rendering."); exit 1 }; if ($text.Contains([char]27)) { [Console]::Error.WriteLine("NO_COLOR output contained ANSI escape sequences."); exit 1 }'
        if ($LASTEXITCODE -ne 0) {
            throw 'NO_COLOR presentation contract failed'
        }
    }
    finally {
        [Environment]::SetEnvironmentVariable('NO_COLOR', $originalNoColor, 'Process')
    }
    Write-Pass 'NO_COLOR presentation contract'

    & pwsh -NoProfile -File $toolPath -Action Install -Version 'invalid/version' -Yes *> $null
    if ($LASTEXITCODE -eq 0) {
        throw 'invalid SDK version was accepted'
    }
    Write-Pass 'invalid SDK version rejection'
}
catch {
    $failure = $_.Exception.Message
}
finally {
    [Environment]::SetEnvironmentVariable($homeVariableName, $originalHomeValue, 'Process')
    Remove-Item Env:ISOLATED_DOTNET_SDK_EXPECTED_HOME -ErrorAction SilentlyContinue
    Remove-Item Env:ISOLATED_DOTNET_SDK_TOOL_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:ISOLATED_DOTNET_SDK_SOURCE_COPY -ErrorAction SilentlyContinue
    Remove-Item Env:ISOLATED_DOTNET_SDK_LIST_SUCCESS -ErrorAction SilentlyContinue
    Remove-Item Env:ISOLATED_DOTNET_SDK_LIST_INFORMATION -ErrorAction SilentlyContinue
    Remove-Item -Path $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($null -ne $failure) {
    [Console]::Error.WriteLine("FAIL: $failure")
    exit 1
}

Write-Output 'All PowerShell behavioral tests passed.'
