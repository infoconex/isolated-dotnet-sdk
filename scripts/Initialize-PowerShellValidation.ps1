param(
    [Parameter(Mandatory = $true)]
    [string]$ModuleRoot,

    [Parameter(Mandatory = $true)]
    [bool]$CacheHit,

    [string]$GitHubEnvironmentFile
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$syntaxPaths = @(
    (Join-Path $repoRoot 'isolated-dotnet-sdk.ps1'),
    (Join-Path $repoRoot 'tests/e2e/powershell/direct.ps1'),
    (Join-Path $repoRoot 'tests/e2e/powershell/interactive.ps1')
)

$parseErrors = @()
foreach ($path in $syntaxPaths) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $path,
        [ref]$tokens,
        [ref]$errors) | Out-Null
    $parseErrors += $errors
}

if ($parseErrors.Count -gt 0) {
    $parseErrors | ForEach-Object { Write-Error $_.Message }
    exit 1
}

$testConfig = Get-Content -LiteralPath (Join-Path $repoRoot '.config/test-frameworks.json') -Raw |
    ConvertFrom-Json
$analysisConfig = Get-Content -LiteralPath (Join-Path $repoRoot '.config/static-analysis.json') -Raw |
    ConvertFrom-Json
$pesterVersion = [string]$testConfig.pesterVersion
$analyzerVersion = [string]$analysisConfig.psScriptAnalyzerVersion

if ([string]::IsNullOrWhiteSpace($pesterVersion)) {
    throw 'pesterVersion is required in .config/test-frameworks.json.'
}
if ([string]::IsNullOrWhiteSpace($analyzerVersion)) {
    throw 'psScriptAnalyzerVersion is required in .config/static-analysis.json.'
}

if (-not $CacheHit) {
    Remove-Item -LiteralPath $ModuleRoot -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $ModuleRoot -Force | Out-Null
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    Save-Module -Name Pester -RequiredVersion $pesterVersion -Path $ModuleRoot -Repository PSGallery -Force
    Save-Module -Name PSScriptAnalyzer -RequiredVersion $analyzerVersion -Path $ModuleRoot -Repository PSGallery -Force
}

$pesterManifestPath = Join-Path $ModuleRoot "Pester/$pesterVersion/Pester.psd1"
$analyzerManifestPath = Join-Path $ModuleRoot "PSScriptAnalyzer/$analyzerVersion/PSScriptAnalyzer.psd1"
if (-not (Test-Path -LiteralPath $pesterManifestPath -PathType Leaf)) {
    throw "Cached Pester manifest was not found at $pesterManifestPath."
}
if (-not (Test-Path -LiteralPath $analyzerManifestPath -PathType Leaf)) {
    throw "Cached PSScriptAnalyzer manifest was not found at $analyzerManifestPath."
}

$pesterManifest = Test-ModuleManifest -Path $pesterManifestPath
$analyzerManifest = Test-ModuleManifest -Path $analyzerManifestPath
if ($pesterManifest.Version.ToString() -ne $pesterVersion) {
    throw "Expected Pester $pesterVersion but cached manifest reports $($pesterManifest.Version)."
}
if ($analyzerManifest.Version.ToString() -ne $analyzerVersion) {
    throw "Expected PSScriptAnalyzer $analyzerVersion but cached manifest reports $($analyzerManifest.Version)."
}

$modulePath = "$ModuleRoot$([System.IO.Path]::PathSeparator)$env:PSModulePath"
$env:PSModulePath = $modulePath
if (-not [string]::IsNullOrWhiteSpace($GitHubEnvironmentFile)) {
    "PSModulePath=$modulePath" | Add-Content -LiteralPath $GitHubEnvironmentFile
}

Write-Output "PowerShell validation setup passed with Pester $pesterVersion and PSScriptAnalyzer $analyzerVersion."
