[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [Parameter(Mandatory)]
    [ValidatePattern('^v[0-9]+\.[0-9]+\.[0-9]+$')]
    [string]$ReleaseTag
)

$ErrorActionPreference = 'Stop'

$targets = @(
    [pscustomobject]@{
        Path = 'isolated-dotnet-sdk.ps1'
        DevelopmentMarker = '$ToolReleaseIdentity = ''development'''
        ReleaseMarker = '$ToolReleaseIdentity = ''' + $ReleaseTag + ''''
    },
    [pscustomobject]@{
        Path = 'isolated-dotnet-sdk.sh'
        DevelopmentMarker = 'TOOL_RELEASE_IDENTITY="development"'
        ReleaseMarker = 'TOOL_RELEASE_IDENTITY="' + $ReleaseTag + '"'
    }
)

foreach ($target in $targets) {
    $path = Join-Path $RepositoryRoot $target.Path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Release product script was not found: $path"
    }

    $content = [System.IO.File]::ReadAllText($path)
    $matches = [regex]::Matches($content, [regex]::Escape($target.DevelopmentMarker))
    if ($matches.Count -ne 1) {
        throw "Expected exactly one development identity marker in $($target.Path); found $($matches.Count)."
    }

    $stamped = $content.Replace($target.DevelopmentMarker, $target.ReleaseMarker)
    if ($stamped -eq $content) {
        throw "Release identity stamping did not modify $($target.Path)."
    }

    [System.IO.File]::WriteAllText(
        $path,
        $stamped,
        [System.Text.UTF8Encoding]::new($false))
}
