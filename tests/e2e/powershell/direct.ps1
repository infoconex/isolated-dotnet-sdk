$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$config = Get-Content -LiteralPath (Join-Path $repositoryRoot '.config/e2e.json') -Raw |
    ConvertFrom-Json
$sdkVersion = [string]$config.sdkVersion
if ([string]::IsNullOrWhiteSpace($sdkVersion)) {
    throw 'sdkVersion is required in .config/e2e.json.'
}

$baseTemp = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [System.IO.Path]::GetTempPath() }
$testRoot = Join-Path $baseTemp ("isolated-dotnet-sdk-e2e-direct-{0}" -f [guid]::NewGuid())
$testHome = Join-Path $testRoot 'home'
$dotnetCliHome = Join-Path $testHome '.dotnet-cli'
New-Item -ItemType Directory -Path $dotnetCliHome -Force | Out-Null

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
    $startInfo.Environment['DOTNET_CLI_HOME'] = $dotnetCliHome
    $startInfo.Environment['DOTNET_CLI_TELEMETRY_OPTOUT'] = '1'
    $startInfo.Environment['DOTNET_NOLOGO'] = '1'
    $startInfo.Environment['DOTNET_SKIP_FIRST_TIME_EXPERIENCE'] = '1'

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
    $dotnetHost = Join-Path $sdkRoot 'dotnet.exe'

    $toolVersion = Invoke-E2EProcess `
        -FilePath 'pwsh' `
        -Arguments @('-NoProfile', '-File', $sourceTool, '-Version')
    Assert-Success -Result $toolVersion -Operation 'Tool version query'
    if ($toolVersion.Output.Trim() -ne 'isolated-dotnet-sdk development (main)') {
        throw "Expected development tool identity but received: $($toolVersion.Output.Trim())"
    }
    if (Test-Path -LiteralPath $toolRoot) {
        throw "Tool version query unexpectedly created SDK state at $toolRoot."
    }

    Write-Host "E2E direct: installing .NET SDK $sdkVersion into $sdkRoot"
    $install = Invoke-E2EProcess `
        -FilePath 'pwsh' `
        -Arguments @('-NoProfile', '-File', $sourceTool, '-Action', 'Install', '-SdkVersion', $sdkVersion, '-Yes')
    Assert-Success -Result $install -Operation 'Direct install'
    Write-Host $install.Output

    if (-not (Test-Path -LiteralPath $savedTool -PathType Leaf)) {
        throw "Bootstrapped tool was not found at $savedTool."
    }
    if (-not (Test-Path -LiteralPath $dotnetHost -PathType Leaf)) {
        throw "Isolated dotnet host was not found at $dotnetHost."
    }

    $savedToolVersion = Invoke-E2EProcess `
        -FilePath 'pwsh' `
        -Arguments @('-NoProfile', '-File', $savedTool, '-Version')
    Assert-Success -Result $savedToolVersion -Operation 'Saved tool version query'
    if ($savedToolVersion.Output.Trim() -ne 'isolated-dotnet-sdk development (main)') {
        throw "Expected saved development tool identity but received: $($savedToolVersion.Output.Trim())"
    }

    $version = Invoke-E2EProcess -FilePath $dotnetHost -Arguments @('--version')
    Assert-Success -Result $version -Operation 'Isolated dotnet --version'
    $actualVersion = $version.Output.Trim()
    if ($actualVersion -ne $sdkVersion) {
        throw "Expected isolated SDK version $sdkVersion but dotnet reported $actualVersion."
    }

    $verify = Invoke-E2EProcess `
        -FilePath 'pwsh' `
        -Arguments @('-NoProfile', '-File', $savedTool, '-Action', 'Verify', '-SdkVersion', $sdkVersion)
    Assert-Success -Result $verify -Operation 'Direct verify'
    Write-Host $verify.Output
    if ($verify.Output -notmatch [regex]::Escape("Isolated SDK $sdkVersion is healthy.")) {
        throw "Verify output did not report SDK $sdkVersion healthy."
    }

    $list = Invoke-E2EProcess `
        -FilePath 'pwsh' `
        -Arguments @('-NoProfile', '-File', $savedTool, '-Action', 'List')
    Assert-Success -Result $list -Operation 'Direct list'
    Write-Host $list.Output
    if ($list.Output -notmatch [regex]::Escape($sdkVersion)) {
        throw "List output did not contain installed SDK $sdkVersion."
    }

    $audit = Invoke-E2EProcess `
        -FilePath 'pwsh' `
        -Arguments @('-NoProfile', '-File', $savedTool, '-Action', 'Audit')
    Assert-Success -Result $audit -Operation 'Direct audit'
    Write-Host $audit.Output
    if ($audit.Output -notmatch [regex]::Escape('.NET SDK audit') -or
        $audit.Output -notmatch [regex]::Escape($sdkVersion)) {
        throw "Audit output did not assess installed SDK $sdkVersion."
    }

    Write-Host "E2E direct: removing .NET SDK $sdkVersion"
    $remove = Invoke-E2EProcess `
        -FilePath 'pwsh' `
        -Arguments @('-NoProfile', '-File', $savedTool, '-Action', 'Remove', '-SdkVersion', $sdkVersion, '-Yes')
    Assert-Success -Result $remove -Operation 'Direct remove'
    Write-Host $remove.Output

    if (Test-Path -LiteralPath $sdkRoot) {
        throw "SDK directory still exists after removal: $sdkRoot"
    }

    Write-Host "E2E direct lifecycle passed for .NET SDK $sdkVersion."
}
finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
