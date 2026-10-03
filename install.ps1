$ErrorActionPreference = 'Stop'

$Repository = 'infoconex/isolated-dotnet-sdk'
$LatestReleaseUrl = "https://api.github.com/repos/$Repository/releases/latest"
$RawBaseUrl = "https://raw.githubusercontent.com/$Repository"
$ReleaseDownloadBaseUrl = "https://github.com/$Repository/releases/download"
$ToolName = 'isolated-dotnet-sdk.ps1'
$GitHubHeaders = @{
    Accept = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
}

$release = Invoke-RestMethod -Uri $LatestReleaseUrl -Headers $GitHubHeaders
$releaseTag = [string]$release.tag_name
if ($release.draft -ne $false -or
    $release.prerelease -ne $false -or
    $releaseTag -notmatch '^v\d+\.\d+\.\d+$') {
    throw 'Latest release metadata does not identify one published stable release.'
}

$tempRoot = [System.IO.Path]::GetTempPath()
$operationId = [guid]::NewGuid().ToString('N')
$toolTemp = Join-Path $tempRoot "isolated-dotnet-sdk-$operationId.ps1"
$checksumsTemp = Join-Path $tempRoot "isolated-dotnet-sdk-$operationId-SHA256SUMS"

try {
    Invoke-WebRequest "$RawBaseUrl/$releaseTag/$ToolName" -OutFile $toolTemp
    Invoke-WebRequest "$ReleaseDownloadBaseUrl/$releaseTag/SHA256SUMS" -OutFile $checksumsTemp

    $checksumMatches = @(
        Select-String -LiteralPath $checksumsTemp -Pattern '^([0-9a-fA-F]{64})  isolated-dotnet-sdk\.ps1$'
    )
    if ($checksumMatches.Count -ne 1) {
        throw 'SHA256SUMS does not contain exactly one valid isolated-dotnet-sdk.ps1 entry.'
    }

    $expected = $checksumMatches[0].Matches[0].Groups[1].Value
    $actual = (Get-FileHash -LiteralPath $toolTemp -Algorithm SHA256).Hash
    if ($actual -ine $expected) {
        throw "Checksum verification failed for isolated-dotnet-sdk.ps1. Expected $expected, got $actual."
    }

    $powerShellExecutable = (Get-Process -Id $PID).Path
    & $powerShellExecutable -NoLogo -NoProfile -File $toolTemp
    $toolExitCode = $LASTEXITCODE
    if ($toolExitCode -ne 0) {
        throw "Released tool exited with exit code $toolExitCode."
    }
}
finally {
    Remove-Item -LiteralPath $toolTemp, $checksumsTemp -Force -ErrorAction SilentlyContinue
}
