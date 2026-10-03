$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$baseTemp = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [System.IO.Path]::GetTempPath() }
$testRoot = Join-Path $baseTemp ("isolated-dotnet-sdk-e2e-latest-bootstrap-{0}" -f [guid]::NewGuid())
$testHome = Join-Path $testRoot 'home'
$checksums = Join-Path $testRoot 'SHA256SUMS'
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
    $repository = 'infoconex/isolated-dotnet-sdk'
    $headers = @{
        Accept = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
    }
    $release = Invoke-RestMethod `
        -Uri "https://api.github.com/repos/$repository/releases/latest" `
        -Headers $headers
    $releaseTag = [string]$release.tag_name
    if ($release.draft -ne $false -or
        $release.prerelease -ne $false -or
        $releaseTag -notmatch '^v\d+\.\d+\.\d+$') {
        throw 'GitHub latest-release metadata did not identify a published stable release.'
    }

    Invoke-WebRequest `
        "https://github.com/$repository/releases/download/$releaseTag/SHA256SUMS" `
        -OutFile $checksums
    $checksumMatches = @(
        Select-String `
            -LiteralPath $checksums `
            -Pattern '^([0-9a-fA-F]{64})  isolated-dotnet-sdk\.ps1$'
    )
    if ($checksumMatches.Count -ne 1) {
        throw 'Current stable release does not contain exactly one valid PowerShell checksum entry.'
    }
    $expected = $checksumMatches[0].Matches[0].Groups[1].Value

    $bootstrap = Join-Path $repositoryRoot 'install.ps1'
    $result = Invoke-E2EProcess `
        -FilePath 'pwsh' `
        -Arguments @('-NoProfile', '-File', $bootstrap) `
        -InputLines @('E')
    Assert-Success -Result $result -Operation 'Latest-stable PowerShell bootstrap'
    Write-Host $result.Output

    $savedTool = Join-Path $testHome 'dotnet-sdks/isolated-dotnet-sdk.ps1'
    if (-not (Test-Path -LiteralPath $savedTool -PathType Leaf)) {
        throw "Latest-stable bootstrap did not save the released PowerShell tool at $savedTool."
    }

    $actual = (Get-FileHash -LiteralPath $savedTool -Algorithm SHA256).Hash
    if ($actual -ine $expected) {
        throw "Saved PowerShell tool does not match current stable release $releaseTag. Expected $expected, got $actual."
    }

    if ($result.Output -notmatch [regex]::Escape('Exiting.')) {
        throw 'Latest-stable PowerShell bootstrap did not reach the released tool interactive exit.'
    }

    Write-Host "Latest-stable PowerShell bootstrap E2E passed for $releaseTag."
}
finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
