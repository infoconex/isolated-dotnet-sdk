[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$OutputPath = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path 'SHA256SUMS')
)

$ErrorActionPreference = 'Stop'

$releaseFiles = @(
    'isolated-dotnet-sdk.ps1',
    'isolated-dotnet-sdk.sh'
)

$lines = foreach ($fileName in $releaseFiles) {
    $path = Join-Path $RepositoryRoot $fileName
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Release file was not found: $path"
    }

    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    '{0}  {1}' -f $hash, $fileName
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$content = ($lines -join "`n") + "`n"
[System.IO.File]::WriteAllText(
    $OutputPath,
    $content,
    [System.Text.UTF8Encoding]::new($false))

Write-Output $OutputPath
