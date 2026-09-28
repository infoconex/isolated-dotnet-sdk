$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$config = Get-Content -LiteralPath (Join-Path $repositoryRoot '.config/e2e.json') -Raw |
    ConvertFrom-Json
$channelVersion = [string]$config.channelVersion
$sdkVersion = [string]$config.sdkVersion
if ([string]::IsNullOrWhiteSpace($channelVersion)) {
    throw 'channelVersion is required in .config/e2e.json.'
}
if ([string]::IsNullOrWhiteSpace($sdkVersion)) {
    throw 'sdkVersion is required in .config/e2e.json.'
}

$baseTemp = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [System.IO.Path]::GetTempPath() }
$testRoot = Join-Path $baseTemp ("isolated-dotnet-sdk-e2e-interactive-{0}" -f [guid]::NewGuid())
$testHome = Join-Path $testRoot 'home'
New-Item -ItemType Directory -Path $testHome -Force | Out-Null

function Invoke-E2EProcess {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [string[]]$Arguments = @(),

        [string[]]$InputLines = @()
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.Environment['HOME'] = $testHome
    $startInfo.Environment['USERPROFILE'] = $testHome

    foreach ($argument in $Arguments) {
        $startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    [void]$process.Start()

    foreach ($line in $InputLines) {
        $process.StandardInput.WriteLine($line)
    }
    $process.StandardInput.Close()

    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()

    [pscustomobject]@{
        ExitCode = $process.ExitCode
        Output = $stdoutTask.GetAwaiter().GetResult() + $stderrTask.GetAwaiter().GetResult()
    }
}

function Assert-Success {
    param(
        [Parameter(Mandatory)]
        $Result,

        [Parameter(Mandatory)]
        [string]$Operation
    )

    if ($Result.ExitCode -ne 0) {
        throw "$Operation failed with exit code $($Result.ExitCode).`n$($Result.Output)"
    }
}

try {
    $sourceTool = Join-Path $repositoryRoot 'isolated-dotnet-sdk.ps1'
    $toolRoot = Join-Path $testHome 'dotnet-sdks'
    $savedTool = Join-Path $toolRoot 'isolated-dotnet-sdk.ps1'
    $sdkRoot = Join-Path $toolRoot $sdkVersion

    Write-Host "E2E interactive: discovering displayed selection for .NET $channelVersion"
    $discovery = Invoke-E2EProcess `
        -FilePath 'pwsh' `
        -Arguments @('-NoProfile', '-File', $sourceTool, '-Action', 'Install') `
        -InputLines @('Q')
    Assert-Success -Result $discovery -Operation 'Interactive channel discovery'
    Write-Host $discovery.Output

    $escapedChannel = [regex]::Escape($channelVersion)
    $channelMatch = [regex]::Match(
        $discovery.Output,
        "(?m)^\s*(\d+)\.\s+\.NET\s+$escapedChannel(?:\s|$)")
    if (-not $channelMatch.Success) {
        throw "Unable to find .NET $channelVersion in the displayed live channel picker."
    }
    $channelSelection = $channelMatch.Groups[1].Value

    if (-not (Test-Path -LiteralPath $savedTool -PathType Leaf)) {
        throw "Bootstrapped tool was not found at $savedTool."
    }

    $inputLines = @(
        '1',
        $channelSelection,
        'B',
        $channelSelection,
        'M',
        $sdkVersion,
        '3',
        '2',
        '1',
        '4'
    )

    Write-Host "E2E interactive: running persistent session for .NET SDK $sdkVersion"
    $interactive = Invoke-E2EProcess `
        -FilePath 'pwsh' `
        -Arguments @('-NoProfile', '-File', $savedTool, '-Yes') `
        -InputLines $inputLines
    Assert-Success -Result $interactive -Operation 'Persistent interactive lifecycle'
    Write-Host $interactive.Output

    $mainPromptCount = ([regex]::Matches($interactive.Output, 'What would you like to do\?')).Count
    if ($mainPromptCount -ne 4) {
        throw "Expected 4 Main prompts but observed $mainPromptCount."
    }

    $requiredFragments = @(
        'Back to .NET channels',
        'Isolated SDK installation completed successfully.',
        'Isolated SDKs under',
        $sdkVersion,
        'was removed.',
        'Exiting.'
    )

    foreach ($fragment in $requiredFragments) {
        if ($interactive.Output -notmatch [regex]::Escape($fragment)) {
            throw "Interactive output did not contain required text: $fragment"
        }
    }

    if (Test-Path -LiteralPath $sdkRoot) {
        throw "SDK directory still exists after interactive removal: $sdkRoot"
    }

    Write-Host "E2E interactive lifecycle passed for .NET SDK $sdkVersion."
}
finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
