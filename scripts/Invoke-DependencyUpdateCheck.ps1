[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$ResultPath,
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'

function ConvertTo-StableVersion {
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $normalized = $Value.Trim()
    if ($normalized.StartsWith('v', [System.StringComparison]::OrdinalIgnoreCase)) {
        $normalized = $normalized.Substring(1)
    }

    try {
        return [version]$normalized
    }
    catch {
        throw "Version '$Value' is not a supported stable version."
    }
}

function Test-DependencyVersionUpdate {
    param(
        [Parameter(Mandatory)]
        [string]$CurrentVersion,

        [Parameter(Mandatory)]
        [string]$CandidateVersion
    )

    $current = ConvertTo-StableVersion -Value $CurrentVersion
    $candidate = ConvertTo-StableVersion -Value $CandidateVersion
    return $candidate -gt $current
}

function Get-RepositoryDependencyPin {
    param(
        [Parameter(Mandatory)]
        [string]$Root
    )

    $analysis = Get-Content -LiteralPath (Join-Path $Root '.config/static-analysis.json') -Raw |
        ConvertFrom-Json
    $test = Get-Content -LiteralPath (Join-Path $Root '.config/test-frameworks.json') -Raw |
        ConvertFrom-Json
    $remote = Get-Content -LiteralPath (Join-Path $Root '.config/remote-artifacts.json') -Raw |
        ConvertFrom-Json

    $requiredValues = @{
        'psScriptAnalyzerVersion' = [string]$analysis.psScriptAnalyzerVersion
        'shellCheckVersion' = [string]$analysis.shellCheckVersion
        'pesterVersion' = [string]$test.pesterVersion
        'batsVersion' = [string]$test.batsVersion
        'batsCommit' = [string]$test.batsCommit
        'dotnetInstallCommit' = [string]$remote.dotnetInstall.commit
    }

    foreach ($entry in $requiredValues.GetEnumerator()) {
        if ([string]::IsNullOrWhiteSpace($entry.Value)) {
            throw "$($entry.Key) is required for dependency update monitoring."
        }
    }

    if ($requiredValues['batsCommit'] -notmatch '^[0-9a-f]{40}$') {
        throw 'batsCommit must be a full lowercase Git commit SHA.'
    }
    if ($requiredValues['dotnetInstallCommit'] -notmatch '^[0-9a-f]{40}$') {
        throw 'dotnetInstall.commit must be a full lowercase Git commit SHA.'
    }

    return [pscustomobject][ordered]@{
        PSScriptAnalyzerVersion = $requiredValues['psScriptAnalyzerVersion']
        PesterVersion = $requiredValues['pesterVersion']
        ShellCheckVersion = $requiredValues['shellCheckVersion']
        BatsVersion = $requiredValues['batsVersion']
        BatsCommit = $requiredValues['batsCommit']
        DotNetInstallCommit = $requiredValues['dotnetInstallCommit']
    }
}

function Get-GitHubApiHeader {
    $headers = [ordered]@{
        Accept = 'application/vnd.github+json'
        'User-Agent' = 'isolated-dotnet-sdk-update-monitor'
        'X-GitHub-Api-Version' = '2022-11-28'
    }

    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
        $headers.Authorization = "Bearer $($env:GITHUB_TOKEN)"
    }

    return $headers
}

function Resolve-GitHubReleaseCommit {
    param(
        [Parameter(Mandatory)]
        [string]$Repository,

        [Parameter(Mandatory)]
        [string]$Tag
    )

    $escapedTag = [uri]::EscapeDataString($Tag)
    $headers = Get-GitHubApiHeader
    $refUri = "https://api.github.com/repos/$Repository/git/ref/tags/$escapedTag"
    $ref = Invoke-RestMethod -Uri $refUri -Headers $headers -Method Get

    if ($null -eq $ref.object -or [string]::IsNullOrWhiteSpace([string]$ref.object.sha)) {
        throw "GitHub tag '$Tag' for '$Repository' did not include an object SHA."
    }

    if ([string]$ref.object.type -eq 'commit') {
        return [string]$ref.object.sha
    }

    if ([string]$ref.object.type -ne 'tag') {
        throw "GitHub tag '$Tag' for '$Repository' resolved to unsupported object type '$($ref.object.type)'."
    }

    $tagUri = "https://api.github.com/repos/$Repository/git/tags/$($ref.object.sha)"
    $tagObject = Invoke-RestMethod -Uri $tagUri -Headers $headers -Method Get
    if (
        $null -eq $tagObject.object -or
        [string]$tagObject.object.type -ne 'commit' -or
        [string]$tagObject.object.sha -notmatch '^[0-9a-f]{40}$'
    ) {
        throw "Annotated GitHub tag '$Tag' for '$Repository' did not resolve to a commit."
    }

    return [string]$tagObject.object.sha
}

function Get-GitHubStableRelease {
    param(
        [Parameter(Mandatory)]
        [string]$Repository,

        [switch]$ResolveCommit
    )

    $headers = Get-GitHubApiHeader
    $releaseUri = "https://api.github.com/repos/$Repository/releases/latest"
    $release = Invoke-RestMethod -Uri $releaseUri -Headers $headers -Method Get

    if (
        $null -eq $release -or
        [bool]$release.draft -or
        [bool]$release.prerelease -or
        [string]::IsNullOrWhiteSpace([string]$release.tag_name) -or
        [string]::IsNullOrWhiteSpace([string]$release.html_url)
    ) {
        throw "Latest GitHub release metadata for '$Repository' was missing required stable-release fields."
    }

    $commit = $null
    if ($ResolveCommit) {
        $commit = Resolve-GitHubReleaseCommit -Repository $Repository -Tag ([string]$release.tag_name)
        if ($commit -notmatch '^[0-9a-f]{40}$') {
            throw "Latest GitHub release '$($release.tag_name)' for '$Repository' did not resolve to a full commit SHA."
        }
    }

    return [pscustomobject][ordered]@{
        Version = [string]$release.tag_name
        Commit = $commit
        SourceUrl = [string]$release.html_url
    }
}

function Get-PowerShellGalleryStableRelease {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq (Get-Command Find-Module -ErrorAction SilentlyContinue)) {
        throw "Find-Module is required to query the PowerShell Gallery for '$Name'."
    }

    $module = Find-Module -Name $Name -Repository PSGallery -ErrorAction Stop
    if ($null -eq $module -or $null -eq $module.Version) {
        throw "PowerShell Gallery metadata for '$Name' did not include a version."
    }

    $version = [string]$module.Version
    ConvertTo-StableVersion -Value $version | Out-Null

    return [pscustomobject][ordered]@{
        Version = $version
        SourceUrl = "https://www.powershellgallery.com/packages/$Name/$version"
    }
}

function Get-UpstreamDependencySnapshot {
    $analyzer = Get-PowerShellGalleryStableRelease -Name 'PSScriptAnalyzer'
    $pester = Get-PowerShellGalleryStableRelease -Name 'Pester'
    $shellCheck = Get-GitHubStableRelease -Repository 'koalaman/shellcheck'
    $bats = Get-GitHubStableRelease -Repository 'bats-core/bats-core' -ResolveCommit
    $dotnetInstall = Get-GitHubStableRelease -Repository 'dotnet/install-scripts' -ResolveCommit

    return [pscustomobject][ordered]@{
        PSScriptAnalyzer = $analyzer
        Pester = $pester
        ShellCheck = $shellCheck
        Bats = $bats
        DotNetInstall = $dotnetInstall
    }
}

function New-DependencyUpdateRecord {
    param(
        [Parameter(Mandatory)]
        [string]$Dependency,

        [Parameter(Mandatory)]
        [string]$Current,

        [Parameter(Mandatory)]
        [string]$Candidate,

        [Parameter(Mandatory)]
        [string]$SourceUrl,

        [Parameter(Mandatory)]
        [string]$ReviewTogether
    )

    foreach ($value in @($Dependency, $Current, $Candidate, $SourceUrl, $ReviewTogether)) {
        if ([string]::IsNullOrWhiteSpace($value)) {
            throw 'Dependency update records require non-empty review fields.'
        }
    }

    return [pscustomobject][ordered]@{
        Dependency = $Dependency
        Current = $Current
        Candidate = $Candidate
        SourceUrl = $SourceUrl
        ReviewTogether = $ReviewTogether
    }
}

function Get-DependencyUpdateRecord {
    param(
        [Parameter(Mandatory)]
        [psobject]$Current,

        [Parameter(Mandatory)]
        [psobject]$Candidate
    )

    $updates = [System.Collections.Generic.List[object]]::new()

    if (Test-DependencyVersionUpdate -CurrentVersion $Current.PSScriptAnalyzerVersion -CandidateVersion $Candidate.PSScriptAnalyzer.Version) {
        $updates.Add((New-DependencyUpdateRecord `
                    -Dependency 'PSScriptAnalyzer' `
                    -Current $Current.PSScriptAnalyzerVersion `
                    -Candidate $Candidate.PSScriptAnalyzer.Version `
                    -SourceUrl $Candidate.PSScriptAnalyzer.SourceUrl `
                    -ReviewTogether 'Review analyzer release notes and findings before changing the exact module pin.'))
    }

    if (Test-DependencyVersionUpdate -CurrentVersion $Current.PesterVersion -CandidateVersion $Candidate.Pester.Version) {
        $updates.Add((New-DependencyUpdateRecord `
                    -Dependency 'Pester' `
                    -Current $Current.PesterVersion `
                    -Candidate $Candidate.Pester.Version `
                    -SourceUrl $Candidate.Pester.SourceUrl `
                    -ReviewTogether 'Review framework release notes and behavioral-test compatibility before changing the exact module pin.'))
    }

    $shellCheckCandidateVersion = ([string]$Candidate.ShellCheck.Version).TrimStart('v')
    if (Test-DependencyVersionUpdate -CurrentVersion $Current.ShellCheckVersion -CandidateVersion $shellCheckCandidateVersion) {
        $updates.Add((New-DependencyUpdateRecord `
                    -Dependency 'ShellCheck' `
                    -Current $Current.ShellCheckVersion `
                    -Candidate $shellCheckCandidateVersion `
                    -SourceUrl $Candidate.ShellCheck.SourceUrl `
                    -ReviewTogether 'Update shellCheckVersion and the Linux x64 release archive SHA-256 together.'))
    }

    if ([string]$Candidate.Bats.Commit -notmatch '^[0-9a-f]{40}$') {
        throw 'Bats-core candidate release did not resolve to a full lowercase Git commit SHA.'
    }
    $batsCandidateVersion = ([string]$Candidate.Bats.Version).TrimStart('v')
    $batsIsNewer = Test-DependencyVersionUpdate -CurrentVersion $Current.BatsVersion -CandidateVersion $batsCandidateVersion
    if (-not $batsIsNewer -and $batsCandidateVersion -eq $Current.BatsVersion -and $Candidate.Bats.Commit -ne $Current.BatsCommit) {
        throw "Bats-core release v$($Current.BatsVersion) now resolves to '$($Candidate.Bats.Commit)' instead of pinned commit '$($Current.BatsCommit)'."
    }
    if ($batsIsNewer) {
        $updates.Add((New-DependencyUpdateRecord `
                    -Dependency 'Bats-core' `
                    -Current "$($Current.BatsVersion) ($($Current.BatsCommit))" `
                    -Candidate "$batsCandidateVersion ($($Candidate.Bats.Commit))" `
                    -SourceUrl $Candidate.Bats.SourceUrl `
                    -ReviewTogether 'Update batsVersion and the reviewed immutable batsCommit together.'))
    }

    if ([string]$Candidate.DotNetInstall.Commit -notmatch '^[0-9a-f]{40}$') {
        throw 'dotnet/install-scripts candidate release did not resolve to a full lowercase Git commit SHA.'
    }
    if ([string]$Candidate.DotNetInstall.Commit -ne $Current.DotNetInstallCommit) {
        $updates.Add((New-DependencyUpdateRecord `
                    -Dependency 'Microsoft dotnet/install-scripts' `
                    -Current $Current.DotNetInstallCommit `
                    -Candidate "$($Candidate.DotNetInstall.Version) ($($Candidate.DotNetInstall.Commit))" `
                    -SourceUrl $Candidate.DotNetInstall.SourceUrl `
                    -ReviewTogether 'Review the release commit, Bash/PowerShell blob IDs, commit-qualified URLs, SHA-256 values, and embedded product constants together.'))
    }

    return @($updates)
}

function ConvertTo-DependencyUpdateReport {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Update
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# Pinned dependency update monitor')
    $lines.Add('')

    if ($Update.Count -eq 0) {
        $lines.Add('All unsupported repository-owned dependency pins match their current stable upstream releases.')
        return ($lines -join [Environment]::NewLine) + [Environment]::NewLine
    }

    $lines.Add("Newer stable releases are available for $($Update.Count) pinned dependencies. Discovery does not modify repository pins.")
    $lines.Add('')
    $lines.Add('| Dependency | Current | Candidate | Authoritative source | Review together |')
    $lines.Add('| --- | --- | --- | --- | --- |')

    foreach ($item in $Update) {
        $dependency = ([string]$item.Dependency).Replace('|', '\|')
        $current = ([string]$item.Current).Replace('|', '\|')
        $candidate = ([string]$item.Candidate).Replace('|', '\|')
        $sourceUrl = ([string]$item.SourceUrl).Replace('|', '%7C')
        $reviewTogether = ([string]$item.ReviewTogether).Replace('|', '\|')
        $lines.Add("| $dependency | $current | $candidate | $sourceUrl | $reviewTogether |")
    }

    $lines.Add('')
    $lines.Add('Adopt an update only through the normal reviewed repository workflow; do not change a friendly version without its coupled integrity/provenance metadata.')
    return ($lines -join [Environment]::NewLine) + [Environment]::NewLine
}

function Write-DependencyUpdateResult {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Update,

        [string]$JsonPath,

        [string]$MarkdownPath
    )

    $report = ConvertTo-DependencyUpdateReport -Update $Update
    $result = [ordered]@{
        UpdateCount = $Update.Count
        Updates = @($Update)
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)

    if (-not [string]::IsNullOrWhiteSpace($JsonPath)) {
        $json = $result | ConvertTo-Json -Depth 6
        [System.IO.File]::WriteAllText($JsonPath, $json + [Environment]::NewLine, $utf8NoBom)
    }

    if (-not [string]::IsNullOrWhiteSpace($MarkdownPath)) {
        [System.IO.File]::WriteAllText($MarkdownPath, $report, $utf8NoBom)
    }

    return $report
}

function Invoke-DependencyUpdateCheck {
    param(
        [Parameter(Mandatory)]
        [string]$Root,

        [string]$JsonPath,

        [string]$MarkdownPath
    )

    $current = Get-RepositoryDependencyPin -Root $Root
    $candidate = Get-UpstreamDependencySnapshot
    $updates = Get-DependencyUpdateRecord -Current $current -Candidate $candidate
    return Write-DependencyUpdateResult -Update $updates -JsonPath $JsonPath -MarkdownPath $MarkdownPath
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-DependencyUpdateCheck `
        -Root $RepositoryRoot `
        -JsonPath $ResultPath `
        -MarkdownPath $ReportPath
}
