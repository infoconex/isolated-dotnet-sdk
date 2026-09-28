[CmdletBinding()]
param(
    [string]$ResultPath,
    [string]$ReportPath,
    [string]$Repository = $env:GITHUB_REPOSITORY,
    [string]$Token = $env:GITHUB_TOKEN
)

$ErrorActionPreference = 'Stop'
$script:DependencyMonitorIssueTitle = 'Pinned dependency updates available'
$script:DependencyMonitorIssueMarker = '<!-- isolated-dotnet-sdk:dependency-update-monitor -->'

function Select-DependencyMonitorIssue {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Issue
    )

    $trackingIssues = @(
        $Issue | Where-Object {
            [string]$_.title -eq $script:DependencyMonitorIssueTitle -and
            $null -eq $_.pull_request
        }
    )

    if ($trackingIssues.Count -gt 1) {
        throw 'Found multiple dependency monitor tracking issues; reconcile the duplicates before monitoring can continue.'
    }

    if ($trackingIssues.Count -eq 0) {
        return $null
    }

    return $trackingIssues[0]
}

function Get-DependencyMonitorIssueDecision {
    param(
        [Parameter(Mandatory)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$UpdateCount,

        [AllowNull()]
        [psobject]$ExistingIssue
    )

    if ($null -eq $ExistingIssue) {
        if ($UpdateCount -gt 0) {
            return 'Create'
        }

        return 'None'
    }

    $state = [string]$ExistingIssue.state
    if ($state -notin @('open', 'closed')) {
        throw "Dependency monitor tracking issue has unsupported state '$state'."
    }

    if ($UpdateCount -gt 0) {
        if ($state -eq 'open') {
            return 'Update'
        }

        return 'Reopen'
    }

    if ($state -eq 'open') {
        return 'Close'
    }

    return 'None'
}

function Get-GitHubIssueApiHeader {
    param(
        [Parameter(Mandatory)]
        [string]$AccessToken
    )

    if ([string]::IsNullOrWhiteSpace($AccessToken)) {
        throw 'A GitHub token is required to synchronize the dependency monitor issue.'
    }

    return [ordered]@{
        Accept = 'application/vnd.github+json'
        Authorization = "Bearer $AccessToken"
        'User-Agent' = 'isolated-dotnet-sdk-update-monitor'
        'X-GitHub-Api-Version' = '2022-11-28'
    }
}

function Invoke-GitHubIssueApi {
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [ValidateSet('Get', 'Post', 'Patch')]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$AccessToken,

        [AllowNull()]
        [hashtable]$Body
    )

    $request = @{
        Uri = $Uri
        Method = $Method
        Headers = Get-GitHubIssueApiHeader -AccessToken $AccessToken
        ErrorAction = 'Stop'
    }

    if ($null -ne $Body) {
        $request.ContentType = 'application/json'
        $request.Body = $Body | ConvertTo-Json -Depth 5 -Compress
    }

    return Invoke-RestMethod @request
}

function Find-DependencyMonitorIssue {
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryName,

        [Parameter(Mandatory)]
        [string]$AccessToken
    )

    if ($RepositoryName -notmatch '^[^/]+/[^/]+$') {
        throw "GitHub repository '$RepositoryName' must use owner/name form."
    }

    $query = [uri]::EscapeDataString(
        "repo:$RepositoryName is:issue in:title `"$script:DependencyMonitorIssueTitle`"")
    $uri = "https://api.github.com/search/issues?q=$query&per_page=100"
    $response = Invoke-GitHubIssueApi -Uri $uri -Method Get -AccessToken $AccessToken -Body $null

    if ($null -eq $response -or $null -eq $response.items) {
        throw 'GitHub issue search response did not include an items collection.'
    }

    return Select-DependencyMonitorIssue -Issue @($response.items)
}

function Invoke-DependencyMonitorIssueSync {
    param(
        [Parameter(Mandatory)]
        [string]$JsonPath,

        [Parameter(Mandatory)]
        [string]$MarkdownPath,

        [Parameter(Mandatory)]
        [string]$RepositoryName,

        [Parameter(Mandatory)]
        [string]$AccessToken
    )

    if (-not (Test-Path -LiteralPath $JsonPath -PathType Leaf)) {
        throw "Dependency update result '$JsonPath' does not exist."
    }
    if (-not (Test-Path -LiteralPath $MarkdownPath -PathType Leaf)) {
        throw "Dependency update report '$MarkdownPath' does not exist."
    }

    $result = Get-Content -LiteralPath $JsonPath -Raw | ConvertFrom-Json
    if ($result.PSObject.Properties.Name -notcontains 'UpdateCount') {
        throw 'Dependency update result does not include UpdateCount.'
    }

    $updateCount = 0
    if (-not [int]::TryParse([string]$result.UpdateCount, [ref]$updateCount) -or $updateCount -lt 0) {
        throw "Dependency update result has invalid UpdateCount '$($result.UpdateCount)'."
    }

    $report = Get-Content -LiteralPath $MarkdownPath -Raw
    if ([string]::IsNullOrWhiteSpace($report)) {
        throw 'Dependency update report must not be empty.'
    }

    $existingIssue = Find-DependencyMonitorIssue `
        -RepositoryName $RepositoryName `
        -AccessToken $AccessToken
    $decision = Get-DependencyMonitorIssueDecision `
        -UpdateCount $updateCount `
        -ExistingIssue $existingIssue
    $body = "$script:DependencyMonitorIssueMarker`n`n$($report.TrimEnd())`n"
    $repositoryUri = "https://api.github.com/repos/$RepositoryName"

    switch ($decision) {
        'Create' {
            Invoke-GitHubIssueApi `
                -Uri "$repositoryUri/issues" `
                -Method Post `
                -AccessToken $AccessToken `
                -Body @{
                title = $script:DependencyMonitorIssueTitle
                body = $body
            } | Out-Null
        }
        'Update' {
            Invoke-GitHubIssueApi `
                -Uri "$repositoryUri/issues/$($existingIssue.number)" `
                -Method Patch `
                -AccessToken $AccessToken `
                -Body @{ body = $body } | Out-Null
        }
        'Reopen' {
            Invoke-GitHubIssueApi `
                -Uri "$repositoryUri/issues/$($existingIssue.number)" `
                -Method Patch `
                -AccessToken $AccessToken `
                -Body @{ body = $body; state = 'open' } | Out-Null
        }
        'Close' {
            Invoke-GitHubIssueApi `
                -Uri "$repositoryUri/issues/$($existingIssue.number)" `
                -Method Patch `
                -AccessToken $AccessToken `
                -Body @{ body = $body; state = 'closed' } | Out-Null
        }
        'None' {
            # No mutation is required when there is no outstanding update state.
        }
        default {
            throw "Unsupported dependency monitor issue decision '$decision'."
        }
    }

    return $decision
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-DependencyMonitorIssueSync `
        -JsonPath $ResultPath `
        -MarkdownPath $ReportPath `
        -RepositoryName $Repository `
        -AccessToken $Token
}
