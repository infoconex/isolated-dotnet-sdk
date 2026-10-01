<#
.SYNOPSIS
Installs and manages isolated .NET SDK versions on Windows with PowerShell 7.

.DESCRIPTION
Installs exact .NET SDK versions under the current user's dotnet-sdks directory without modifying the system-wide .NET installation or PATH. Isolated SDKs remain under that user-owned root and are not added to PATH.

Supported product actions are Install, Remove, List, and Verify. When Action and Version are both omitted, the tool starts a persistent interactive session and returns to the main menu after normal completion or cancellation. When Action is omitted and Version is supplied, Install is selected. Explicit actions and exact-version requests remain one-shot. Explicit List with Version is invalid. Verify requires an exact Version and remains direct-command-only; it does not appear on the persistent Main menu. Install or Remove without a resolved version may require interactive selection.

Yes skips supported confirmation prompts only; it does not choose a missing action or version. PowerShell WhatIf and Confirm are supported only for Remove. Required interactive input that is unavailable is an operational failure. Explicit cancellation is a successful no-change result. Operational failures return a nonzero exit status.

Exact-version installs bypass release-metadata discovery. Interactive install selection uses Microsoft's published .NET release metadata. List reports recognized isolated SDKs first and then the read-only SDK inventory returned by the normally resolved dotnet --list-sdks host. System SDK discovery is supplemental rather than an exhaustive filesystem inventory, and system SDKs are never managed by Remove.

.PARAMETER Action
Specifies the operation to perform: Install, Remove, List, or Verify. When omitted, the script starts the persistent interactive session unless Version is supplied, in which case Install is selected.

.PARAMETER Version
Specifies an exact .NET SDK version. When omitted for Install or Remove, the script provides an interactive version selection workflow. Verify requires Version. Version is invalid with an explicit List action.

.PARAMETER Yes
Skips confirmation prompts that support automatic confirmation. It does not supply a missing action or version.

.EXAMPLE
.\isolated-dotnet-sdk.ps1 -Action List

Lists recognized isolated SDKs and SDKs reported by the normally resolved system dotnet host once and exits.

.EXAMPLE
.\isolated-dotnet-sdk.ps1 -Action Install -Version 10.0.100

Installs .NET SDK 10.0.100 in an isolated directory.

.EXAMPLE
.\isolated-dotnet-sdk.ps1 -Action Verify -Version 10.0.100

Verifies that the existing isolated .NET SDK 10.0.100 has a launchable host that reports the requested exact version.

.EXAMPLE
.\isolated-dotnet-sdk.ps1 -Action Remove -Version 10.0.100 -Yes

Removes the isolated .NET SDK 10.0.100 without the tool-owned confirmation prompt.

.EXAMPLE
.\isolated-dotnet-sdk.ps1 -Action Remove -Version 10.0.100 -WhatIf

Previews removal without shutting down build servers or deleting the isolated SDK.

.EXAMPLE
.\isolated-dotnet-sdk.ps1

Starts the persistent interactive session.

.NOTES
Supported product mapping: Windows with PowerShell 7. Linux and macOS use the Bash implementation. PowerShell on Linux/macOS and Bash on Windows are not supported product combinations.

Run an installed isolated SDK directly from $HOME\dotnet-sdks\<version>\dotnet.exe. The tool does not add isolated SDKs to the normal PATH.

.LINK
https://github.com/infoconex/isolated-dotnet-sdk

.LINK
https://github.com/infoconex/isolated-dotnet-sdk/blob/main/docs/behavioral-parity.md

.LINK
https://github.com/infoconex/isolated-dotnet-sdk/blob/main/docs/cross-platform-support.md
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$Action,
    [string]$Version,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'

$RepositoryRawBase = 'https://raw.githubusercontent.com/infoconex/isolated-dotnet-sdk/main'
$ReleaseIndexUrl = 'https://builds.dotnet.microsoft.com/dotnet/release-metadata/releases-index.json'
$ToolName = 'isolated-dotnet-sdk.ps1'
$SdkRoot = Join-Path $HOME 'dotnet-sdks'
$ToolPath = Join-Path $SdkRoot $ToolName
$script:Bootstrapped = $false
$script:ActionWasSpecified = $PSBoundParameters.ContainsKey('Action')
$script:VersionWasSpecified = $PSBoundParameters.ContainsKey('Version')
$script:InteractiveSession = -not $script:ActionWasSpecified -and -not $script:VersionWasSpecified
$script:BackToMain = $false
$script:ExitRequested = $false
$script:ConfirmWasSpecified = $PSBoundParameters.ContainsKey('Confirm')
$script:ConfirmValue = if ($script:ConfirmWasSpecified) { [bool]$PSBoundParameters['Confirm'] } else { $false }
$script:WhatIfWasSpecified = $PSBoundParameters.ContainsKey('WhatIf')
$script:WhatIfValue = if ($script:WhatIfWasSpecified) { [bool]$PSBoundParameters['WhatIf'] } else { $false }

function Write-ToolDisplay {
    param(
        [AllowEmptyString()]
        [string]$Message = ''
    )

    Write-Information -MessageData $Message -InformationAction Continue
}

function Format-ToolMessage {
    param(
        [ValidateSet('Heading', 'Accent', 'Success')]
        [string]$Kind,
        [string]$Message
    )

    if ($null -eq $PSStyle) {
        return $Message
    }

    $SupportsVirtualTerminal = $null -ne $Host.UI -and $Host.UI.SupportsVirtualTerminal
    $UseAnsi = $PSStyle.OutputRendering -eq 'Ansi' -or
    ($PSStyle.OutputRendering -eq 'Host' -and $SupportsVirtualTerminal)

    if (-not $UseAnsi) {
        return $Message
    }

    $Foreground = if ($Kind -eq 'Success') {
        $PSStyle.Foreground.Green
    }
    else {
        $PSStyle.Foreground.Cyan
    }

    return "$Foreground$Message$($PSStyle.Reset)"
}

function Write-ToolInfo {
    param([string]$Message)
    Write-ToolDisplay $Message
}

function Write-ToolLabelValue {
    param(
        [string]$Label,
        [AllowEmptyString()]
        [string]$Value = ''
    )

    $AccentLabel = Format-ToolMessage -Kind Accent -Message $Label
    if ([string]::IsNullOrEmpty($Value)) {
        Write-ToolDisplay $AccentLabel
        return
    }

    Write-ToolDisplay "$AccentLabel $Value"
}

function Format-ToolAccent {
    param([string]$Message)
    return (Format-ToolMessage -Kind Accent -Message $Message)
}

function Format-ToolInput {
    param(
        [AllowEmptyString()]
        [string]$Value = ''
    )

    return [regex]::Replace($Value, '[^\x20-\x7E]', '?')
}

function Get-SelectionRange {
    param([int]$Count)

    if ($Count -le 1) {
        return '1'
    }

    return "1-$Count"
}

function Write-InvalidSelection {
    param(
        [AllowEmptyString()]
        [string]$Selection = '',
        [string]$Choices
    )

    Write-ToolDisplay
    if ([string]::IsNullOrWhiteSpace($Selection)) {
        Write-ToolWarning "A selection is required. $Choices"
        return
    }

    $SafeSelection = Format-ToolInput $Selection.Trim()
    Write-ToolWarning "Invalid selection: $SafeSelection. $Choices"
}

function Write-ToolHeading {
    param([string]$Message)
    Write-ToolDisplay (Format-ToolMessage -Kind Heading -Message $Message)
}

function Write-ToolSuccess {
    param([string]$Message)
    Write-ToolDisplay (Format-ToolMessage -Kind Success -Message $Message)
}

function Write-ToolWarning {
    param([string]$Message)
    Write-Warning $Message
}

function Assert-ValidAction {
    if ([string]::IsNullOrWhiteSpace($script:Action)) {
        return
    }

    if ($script:Action -notin @('Install', 'Remove', 'List', 'Verify')) {
        throw "Invalid action: $script:Action"
    }
}

function Assert-ValidVersion {
    if ($script:Version -notmatch '^[0-9A-Za-z][0-9A-Za-z.+-]*$') {
        throw "Invalid SDK version: $script:Version"
    }
}

function Read-ToolInput {
    param([string]$Prompt)

    try {
        return Read-Host $Prompt
    }
    catch {
        throw 'Interactive input is unavailable.'
    }
}

function Confirm-Action {
    param([string]$Prompt)

    if ($Yes) {
        return $true
    }

    $Response = Read-ToolInput "$Prompt [y/N]"
    return $Response -match '^[Yy]$'
}

# Bootstrap to the per-user tool path. File-based execution preserves the exact source;
# piped execution downloads the current main-branch source before re-executing.
function Install-ToolIfNeeded {
    New-Item -ItemType Directory -Path $SdkRoot -Force -WhatIf:$false -Confirm:$false | Out-Null

    $CurrentPath = $null
    if ($PSCommandPath) {
        $CurrentPath = [System.IO.Path]::GetFullPath($PSCommandPath)
    }

    $ExpectedPath = [System.IO.Path]::GetFullPath($ToolPath)

    if ($CurrentPath -eq $ExpectedPath) {
        return
    }

    if (Test-Path -LiteralPath $ToolPath -PathType Container) {
        throw "Tool path is a directory: $ToolPath"
    }

    Write-ToolDisplay
    Write-ToolInfo "Installing tool to $ToolPath"

    $StagedToolPath = Join-Path `
        $SdkRoot `
    ('.{0}.{1}.tmp' -f $ToolName, [guid]::NewGuid().ToString('N'))

    try {
        if ($CurrentPath -and (Test-Path -LiteralPath $CurrentPath)) {
            Copy-Item `
                -LiteralPath $CurrentPath `
                -Destination $StagedToolPath `
                -Force `
                -WhatIf:$false `
                -Confirm:$false
        }
        else {
            Invoke-WebRequest `
                "$RepositoryRawBase/$ToolName" `
                -OutFile $StagedToolPath
        }

        if (Get-Command Unblock-File -ErrorAction SilentlyContinue) {
            Unblock-File -Path $StagedToolPath -WhatIf:$false -Confirm:$false
        }

        [System.IO.File]::Move($StagedToolPath, $ToolPath, $true)
    }
    finally {
        if (Test-Path -LiteralPath $StagedToolPath -PathType Leaf) {
            Remove-Item `
                -LiteralPath $StagedToolPath `
                -Force `
                -ErrorAction SilentlyContinue `
                -WhatIf:$false `
                -Confirm:$false
        }
    }

    Write-ToolSuccess 'Tool installed.'
    Write-ToolDisplay

    $Arguments = @{}
    if ($script:ActionWasSpecified) {
        $Arguments.Action = $Action
    }
    if ($script:VersionWasSpecified) {
        $Arguments.Version = $Version
    }
    if ($Yes) {
        $Arguments.Yes = $true
    }
    if ($script:ConfirmWasSpecified) {
        $Arguments.Confirm = $script:ConfirmValue
    }
    if ($script:WhatIfWasSpecified) {
        $Arguments.WhatIf = $script:WhatIfValue
    }

    & $ToolPath @Arguments
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    $script:Bootstrapped = $true
}

function Get-IsolatedDotNetPath {
    param([string]$SdkVersion)
    return Join-Path (Join-Path $SdkRoot $SdkVersion) 'dotnet.exe'
}

function Get-SystemSdkInventory {
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        return @()
    }

    $InstalledSdks = dotnet --list-sdks
    $ExitCode = $LASTEXITCODE
    if ($ExitCode -ne 0) {
        throw "Unable to list SDKs through the system dotnet host with exit code $ExitCode."
    }

    return @(
        $InstalledSdks |
            ForEach-Object {
                $Line = [string]$_
                if ([string]::IsNullOrWhiteSpace($Line)) {
                    return
                }

                $Match = [regex]::Match($Line, '^(?<Version>\S+)\s+\[(?<Path>.*)\]$')
                if ($Match.Success) {
                    [pscustomobject]@{
                        Version = $Match.Groups['Version'].Value
                        Path    = $Match.Groups['Path'].Value
                    }
                }
                else {
                    [pscustomobject]@{
                        Version = ($Line -split '\s+')[0]
                        Path    = ''
                    }
                }
            }
    )
}

function Get-SystemSdkVersion {
    return @(
        Get-SystemSdkInventory |
            ForEach-Object { $_.Version }
    )
}

function Get-IsolatedSdkVersion {
    $SdkDirectories = Get-ChildItem `
        -Path $SdkRoot `
        -Directory `
        -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName 'dotnet.exe') } |
        Sort-Object Name

    return @($SdkDirectories | ForEach-Object { $_.Name })
}

function Show-InstalledSdk {
    $IsolatedVersions = @(Get-IsolatedSdkVersion)
    $SystemSdks = @(Get-SystemSdkInventory)

    Write-ToolHeading 'Installed .NET SDKs'
    Write-ToolDisplay
    Write-ToolHeading 'Isolated SDKs:'

    if (-not $IsolatedVersions) {
        Write-ToolDisplay '  None'
    }
    else {
        foreach ($SdkVersion in $IsolatedVersions) {
            Write-ToolDisplay "  $SdkVersion  $(Join-Path $SdkRoot $SdkVersion)"
        }
    }

    Write-ToolDisplay
    Write-ToolHeading 'System SDKs:'

    if (-not $SystemSdks) {
        Write-ToolDisplay '  None'
        return
    }

    foreach ($Sdk in $SystemSdks) {
        if ([string]::IsNullOrWhiteSpace($Sdk.Path)) {
            Write-ToolDisplay "  $($Sdk.Version)"
        }
        else {
            Write-ToolDisplay "  $($Sdk.Version)  $(Join-Path $Sdk.Path $Sdk.Version)"
        }
    }
}

function Format-SupportPhase {
    param([string]$Phase)

    switch ($Phase) {
        'preview' { return 'Preview' }
        'go-live' { return 'Go Live' }
        'active' { return 'Active' }
        'maintenance' { return 'Maintenance' }
        'eol' { return 'EOL' }
        default { return $Phase }
    }
}

function Get-SdkVersionSortKey {
    param([string]$SdkVersion)

    $Match = [regex]::Match(
        $SdkVersion,
        '^(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)(?:-(?<label>[^.]+)(?:\.(?<sequence>\d+))?(?:\.(?<build>\d+))?(?:\.(?<revision>\d+))?)?$')

    if (-not $Match.Success) {
        return "000000000.000000000.000000000.0.000000000.000000000.000000000.$SdkVersion"
    }

    $Major = [int]$Match.Groups['major'].Value
    $Minor = [int]$Match.Groups['minor'].Value
    $Patch = [int]$Match.Groups['patch'].Value
    $Rank = 9
    $Sequence = 0
    $Build = 0
    $Revision = 0

    if ($Match.Groups['label'].Success) {
        $Rank = switch ($Match.Groups['label'].Value) {
            'rc' { 8 }
            'preview' { 7 }
            default { 1 }
        }

        if ($Match.Groups['sequence'].Success) {
            $Sequence = [int]$Match.Groups['sequence'].Value
        }
        if ($Match.Groups['build'].Success) {
            $Build = [int]$Match.Groups['build'].Value
        }
        if ($Match.Groups['revision'].Success) {
            $Revision = [int]$Match.Groups['revision'].Value
        }
    }

    return '{0:D9}.{1:D9}.{2:D9}.{3}.{4:D9}.{5:D9}.{6:D9}' -f `
        $Major, $Minor, $Patch, $Rank, $Sequence, $Build, $Revision
}

function Get-SdkFeatureBand {
    param([string]$SdkVersion)

    $Match = [regex]::Match($SdkVersion, '^(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)')
    if (-not $Match.Success) {
        return $SdkVersion
    }

    $Patch = [int]$Match.Groups['patch'].Value
    return '{0}.{1}.{2}xx' -f `
        $Match.Groups['major'].Value, `
        $Match.Groups['minor'].Value, `
        [math]::Floor($Patch / 100)
}

function Get-OrderedSdkVersion {
    param([string[]]$SdkVersions)

    return @(
        $SdkVersions |
            ForEach-Object {
                [pscustomobject]@{
                    Version = $_
                    SortKey = Get-SdkVersionSortKey $_
                }
            } |
            Sort-Object `
            @{ Expression = 'SortKey'; Descending = $true }, `
            @{ Expression = 'Version'; Descending = $true } |
            ForEach-Object { $_.Version }
    )
}

function Get-FeaturedSdkVersion {
    param(
        [string[]]$OrderedSdkVersions,
        [string]$LatestSdk
    )

    $Result = [System.Collections.Generic.List[string]]::new()
    $SeenBands = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    if (-not [string]::IsNullOrWhiteSpace($LatestSdk) -and
        $OrderedSdkVersions -contains $LatestSdk) {
        $Result.Add($LatestSdk)
        [void]$SeenBands.Add((Get-SdkFeatureBand $LatestSdk))
    }

    foreach ($SdkVersion in $OrderedSdkVersions) {
        if ($SdkVersion -eq $LatestSdk) {
            continue
        }

        $FeatureBand = Get-SdkFeatureBand $SdkVersion
        if ($SeenBands.Add($FeatureBand)) {
            $Result.Add($SdkVersion)
        }
    }

    return @($Result)
}

function Select-Action {
    Assert-ValidAction

    if (-not [string]::IsNullOrWhiteSpace($script:Action)) {
        return $true
    }

    if (-not [string]::IsNullOrWhiteSpace($script:Version)) {
        $script:Action = 'Install'
        return $true
    }

    while ($true) {
        Write-ToolHeading 'What would you like to do?'
        Write-ToolDisplay
        Write-ToolDisplay '  1. Install an SDK'
        Write-ToolDisplay '  2. Remove an isolated SDK'
        Write-ToolDisplay '  3. List installed SDKs'
        Write-ToolDisplay
        Write-ToolDisplay '  E. Exit'
        Write-ToolDisplay

        $Selection = Read-ToolInput 'Selection'

        switch ($Selection) {
            '1' { $script:Action = 'Install'; return $true }
            '2' { $script:Action = 'Remove'; return $true }
            '3' { $script:Action = 'List'; return $true }
            'e' { Write-ToolInfo 'Exiting.'; return $false }
            'E' { Write-ToolInfo 'Exiting.'; return $false }
            default {
                Write-InvalidSelection -Selection $Selection -Choices 'Choose 1, 2, 3, or E.'
                Write-ToolDisplay
            }
        }
    }
}

function Assert-ActionParameterUsage {
    if ($script:Action -eq 'List' -and $script:VersionWasSpecified) {
        throw '-Version is supported only with -Action Install, Remove, or Verify.'
    }

    if ($script:Action -eq 'Verify' -and [string]::IsNullOrWhiteSpace($script:Version)) {
        throw '-Version is required with -Action Verify.'
    }

    if ($script:Action -eq 'Remove') {
        return
    }

    if ($script:WhatIfWasSpecified -or $script:ConfirmWasSpecified) {
        throw '-WhatIf and -Confirm are supported only with -Action Remove.'
    }
}

function Get-ReleaseIndex {
    Write-ToolInfo 'Loading available .NET SDK releases from Microsoft...'

    try {
        $ReleaseIndex = Invoke-RestMethod -Uri $ReleaseIndexUrl
    }
    catch {
        throw 'Unable to load .NET release metadata from Microsoft.'
    }

    if ($null -eq $ReleaseIndex -or
        $null -eq $ReleaseIndex.'releases-index') {
        throw 'Invalid .NET release metadata from Microsoft.'
    }

    return $ReleaseIndex
}

# Microsoft release metadata can expose SDK versions through both `sdk` and `sdks`.
# Preserve first-seen order while removing duplicates from those sources.
function Get-ChannelSdkVersion {
    param($ChannelMetadata)

    $Versions = [System.Collections.Generic.List[string]]::new()
    $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($Release in @($ChannelMetadata.releases)) {
        if ($Release.sdk -and -not [string]::IsNullOrWhiteSpace($Release.sdk.version)) {
            $SdkVersion = [string]$Release.sdk.version
            if ($Seen.Add($SdkVersion)) {
                $Versions.Add($SdkVersion)
            }
        }

        foreach ($Sdk in @($Release.sdks)) {
            if ($Sdk -and -not [string]::IsNullOrWhiteSpace($Sdk.version)) {
                $SdkVersion = [string]$Sdk.version
                if ($Seen.Add($SdkVersion)) {
                    $Versions.Add($SdkVersion)
                }
            }
        }
    }

    return @($Versions)
}

function Read-ManualVersion {
    $script:Version = Read-ToolInput '.NET SDK version'
    if ([string]::IsNullOrWhiteSpace($script:Version)) {
        throw 'An SDK version is required.'
    }

    Assert-ValidVersion
}

# Select from Microsoft's release index when no exact SDK version was supplied.
function Select-InstallVersion {
    $script:BackToMain = $false
    $ReleaseIndex = Get-ReleaseIndex
    $AllChannels = @(
        $ReleaseIndex.'releases-index' |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace([string]$_.'channel-version') -and
                -not [string]::IsNullOrWhiteSpace([string]$_.'support-phase') -and
                -not [string]::IsNullOrWhiteSpace([string]$_.'releases.json')
            }
    )

    if (-not $AllChannels) {
        throw 'No selectable .NET channels were found in Microsoft release metadata.'
    }

    $ShowArchived = $false

    while ($true) {
        Write-ToolDisplay

        if ($ShowArchived) {
            Write-ToolHeading 'Select an end-of-life .NET channel:'
            $Channels = @($AllChannels | Where-Object { $_.'support-phase' -eq 'eol' })
        }
        else {
            Write-ToolHeading 'Select a supported or development .NET channel:'
            $Channels = @($AllChannels | Where-Object { $_.'support-phase' -ne 'eol' })
        }

        Write-ToolDisplay

        for ($Index = 0; $Index -lt $Channels.Count; $Index++) {
            $Channel = $Channels[$Index]
            $ReleaseType = ([string]$Channel.'release-type').ToUpperInvariant()
            $SupportPhase = Format-SupportPhase ([string]$Channel.'support-phase')
            $LatestSdk = [string]$Channel.'latest-sdk'

            if ([string]::IsNullOrWhiteSpace($LatestSdk)) {
                Write-ToolDisplay ("  {0}. .NET {1}  {2}  {3}" -f `
                    ($Index + 1), `
                        $Channel.'channel-version', `
                        $ReleaseType, `
                        $SupportPhase)
            }
            else {
                Write-ToolDisplay ("  {0}. .NET {1}  {2}  {3}  latest SDK {4}" -f `
                    ($Index + 1), `
                        $Channel.'channel-version', `
                        $ReleaseType, `
                        $SupportPhase, `
                        $LatestSdk)
            }
        }

        Write-ToolDisplay
        if ($ShowArchived) {
            Write-ToolDisplay '  S. Show supported/development channels'
        }
        else {
            Write-ToolDisplay '  S. Show end-of-life channels'
        }
        if ($script:InteractiveSession) {
            Write-ToolDisplay '  B. Back to Main'
        }
        Write-ToolDisplay '  M. Enter an exact SDK version manually'
        if ($script:InteractiveSession) {
            Write-ToolDisplay '  E. Exit'
        }
        else {
            Write-ToolDisplay '  Q. Cancel'
        }
        Write-ToolDisplay

        $Selection = Read-ToolInput 'Selection'

        if ($Selection -match '^[Mm]$') {
            Read-ManualVersion
            return $true
        }

        if ($Selection -match '^[Ee]$' -and $script:InteractiveSession) {
            $script:ExitRequested = $true
            Write-ToolInfo 'Exiting.'
            return $false
        }

        if ($Selection -match '^[Qq]$' -and -not $script:InteractiveSession) {
            return $false
        }

        if ($Selection -match '^[Bb]$' -and $script:InteractiveSession) {
            $script:BackToMain = $true
            return $false
        }

        if ($Selection -match '^[Ss]$') {
            $ShowArchived = -not $ShowArchived
            continue
        }

        $Number = 0
        if (-not [int]::TryParse($Selection, [ref]$Number) -or
            $Number -lt 1 -or
            $Number -gt $Channels.Count) {
            $SelectionRange = Get-SelectionRange -Count $Channels.Count
            $Choices = if ($script:InteractiveSession) {
                "Choose $SelectionRange, S, B, M, or E."
            }
            else {
                "Choose $SelectionRange, S, M, or Q."
            }
            Write-InvalidSelection -Selection $Selection -Choices $Choices
            continue
        }

        $SelectedChannel = $Channels[$Number - 1]
        $ChannelVersion = [string]$SelectedChannel.'channel-version'
        $LatestSdk = [string]$SelectedChannel.'latest-sdk'
        $ChannelMetadataUrl = [string]$SelectedChannel.'releases.json'

        try {
            $ChannelMetadata = Invoke-RestMethod -Uri $ChannelMetadataUrl
        }
        catch {
            throw "Unable to load release metadata for .NET $ChannelVersion."
        }

        if ($null -eq $ChannelMetadata -or
            $null -eq $ChannelMetadata.releases) {
            throw "Invalid release metadata for .NET $ChannelVersion."
        }

        $DiscoveredSdkVersions = @(Get-ChannelSdkVersion $ChannelMetadata)
        if (-not $DiscoveredSdkVersions) {
            throw "No SDK versions were found for .NET $ChannelVersion."
        }

        $AllSdkVersions = @(Get-OrderedSdkVersion $DiscoveredSdkVersions)
        $FeaturedSdkVersions = @(Get-FeaturedSdkVersion `
                -OrderedSdkVersions $AllSdkVersions `
                -LatestSdk $LatestSdk)
        $ShowAllVersions = $false
        $SystemVersions = @(Get-SystemSdkVersion)
        $IsolatedVersions = @(Get-IsolatedSdkVersion)

        while ($true) {
            Write-ToolDisplay
            Write-ToolHeading "Available .NET $ChannelVersion SDKs:"
            Write-ToolDisplay

            if ($ShowAllVersions) {
                $SdkVersions = @($AllSdkVersions)
            }
            else {
                $SdkVersions = @($FeaturedSdkVersions)
            }

            for ($Index = 0; $Index -lt $SdkVersions.Count; $Index++) {
                $SdkVersion = $SdkVersions[$Index]
                $Markers = [System.Collections.Generic.List[string]]::new()

                if (-not [string]::IsNullOrWhiteSpace($LatestSdk) -and
                    $SdkVersion -eq $LatestSdk) {
                    $Markers.Add('latest')
                }
                if ($SystemVersions -contains $SdkVersion) {
                    $Markers.Add('system')
                }
                if ($IsolatedVersions -contains $SdkVersion) {
                    $Markers.Add('isolated')
                }

                if ($Markers.Count -gt 0) {
                    $Metadata = Format-ToolAccent -Message ("({0})" -f ($Markers -join ', '))
                    Write-ToolDisplay ("  {0}. {1} {2}" -f ($Index + 1), $SdkVersion, $Metadata)
                }
                else {
                    Write-ToolDisplay ("  {0}. {1}" -f ($Index + 1), $SdkVersion)
                }
            }

            Write-ToolDisplay
            if ($FeaturedSdkVersions.Count -lt $AllSdkVersions.Count) {
                if ($ShowAllVersions) {
                    Write-ToolDisplay '  S. Show featured versions'
                }
                else {
                    Write-ToolDisplay '  S. Show all versions'
                }
            }
            Write-ToolDisplay '  B. Back to .NET channels'
            Write-ToolDisplay '  M. Enter an exact SDK version manually'
            if ($script:InteractiveSession) {
                Write-ToolDisplay '  E. Exit'
            }
            else {
                Write-ToolDisplay '  Q. Cancel'
            }
            Write-ToolDisplay

            $Selection = Read-ToolInput 'Selection'

            if ($Selection -match '^[Bb]$') {
                break
            }

            if ($Selection -match '^[Ss]$' -and
                $FeaturedSdkVersions.Count -lt $AllSdkVersions.Count) {
                $ShowAllVersions = -not $ShowAllVersions
                continue
            }

            if ($Selection -match '^[Mm]$') {
                Read-ManualVersion
                return $true
            }

            if ($Selection -match '^[Ee]$' -and $script:InteractiveSession) {
                $script:ExitRequested = $true
                Write-ToolInfo 'Exiting.'
                return $false
            }

            if ($Selection -match '^[Qq]$' -and -not $script:InteractiveSession) {
                return $false
            }

            $Number = 0
            if ([int]::TryParse($Selection, [ref]$Number) -and
                $Number -ge 1 -and
                $Number -le $SdkVersions.Count) {
                $script:Version = $SdkVersions[$Number - 1]
                Assert-ValidVersion
                return $true
            }

            $SelectionRange = Get-SelectionRange -Count $SdkVersions.Count
            $HasViewToggle = $FeaturedSdkVersions.Count -lt $AllSdkVersions.Count
            if ($script:InteractiveSession) {
                $Choices = if ($HasViewToggle) {
                    "Choose $SelectionRange, S, B, M, or E."
                }
                else {
                    "Choose $SelectionRange, B, M, or E."
                }
            }
            else {
                $Choices = if ($HasViewToggle) {
                    "Choose $SelectionRange, S, B, M, or Q."
                }
                else {
                    "Choose $SelectionRange, B, M, or Q."
                }
            }
            Write-InvalidSelection -Selection $Selection -Choices $Choices
        }
    }
}

function Select-RemoveVersion {
    $script:BackToMain = $false
    $SdkVersions = @(Get-IsolatedSdkVersion)

    if (-not $SdkVersions) {
        Write-ToolInfo "No isolated SDKs are installed under $SdkRoot."
        return $false
    }

    while ($true) {
        Write-ToolHeading 'Select an isolated SDK to remove:'
        Write-ToolDisplay

        for ($Index = 0; $Index -lt $SdkVersions.Count; $Index++) {
            Write-ToolDisplay ("  {0}. {1}" -f ($Index + 1), $SdkVersions[$Index])
        }

        Write-ToolDisplay
        if ($script:InteractiveSession) {
            Write-ToolDisplay '  B. Back to Main'
            Write-ToolDisplay '  E. Exit'
        }
        else {
            Write-ToolDisplay '  Q. Cancel'
        }
        Write-ToolDisplay

        $Selection = Read-ToolInput 'Selection'

        if ($Selection -match '^[Bb]$' -and $script:InteractiveSession) {
            $script:BackToMain = $true
            return $false
        }

        if ($Selection -match '^[Ee]$' -and $script:InteractiveSession) {
            $script:ExitRequested = $true
            Write-ToolInfo 'Exiting.'
            return $false
        }

        if ($Selection -match '^[Qq]$' -and -not $script:InteractiveSession) {
            return $false
        }

        $Number = 0
        if ([int]::TryParse($Selection, [ref]$Number) -and
            $Number -ge 1 -and
            $Number -le $SdkVersions.Count) {
            $script:Version = $SdkVersions[$Number - 1]
            Assert-ValidVersion
            return $true
        }

        $SelectionRange = Get-SelectionRange -Count $SdkVersions.Count
        $Choices = if ($script:InteractiveSession) {
            "Choose $SelectionRange, B, or E."
        }
        else {
            "Choose $SelectionRange or Q."
        }
        Write-InvalidSelection -Selection $Selection -Choices $Choices
        Write-ToolDisplay
    }
}

function Resolve-InstallVersion {
    if (-not [string]::IsNullOrWhiteSpace($script:Version)) {
        Assert-ValidVersion
        return $true
    }

    if (-not (Select-InstallVersion)) {
        if (-not $script:BackToMain -and -not $script:ExitRequested) {
            Write-ToolInfo 'Installation cancelled.'
        }
        return $false
    }

    return $true
}

function Resolve-RemoveVersion {
    if (-not [string]::IsNullOrWhiteSpace($script:Version)) {
        Assert-ValidVersion
        return $true
    }

    if (-not (Select-RemoveVersion)) {
        if (-not $script:BackToMain -and -not $script:ExitRequested) {
            Write-ToolInfo 'Removal cancelled.'
        }
        return $false
    }

    return $true
}

function Get-SdkChannel {
    if ($Version -notmatch '^(?<major>[0-9]+)\.(?<minor>[0-9]+)\.') {
        throw "Unable to determine the .NET release channel for SDK $Version."
    }

    return "$($Matches.major).$($Matches.minor)"
}

function Get-SdkRid {
    $architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    $arch = switch ($architecture) {
        ([System.Runtime.InteropServices.Architecture]::X64) { 'x64'; break }
        ([System.Runtime.InteropServices.Architecture]::X86) { 'x86'; break }
        ([System.Runtime.InteropServices.Architecture]::Arm64) { 'arm64'; break }
        ([System.Runtime.InteropServices.Architecture]::Arm) { 'arm'; break }
        default { throw "Unable to map architecture $architecture to a Microsoft SDK artifact." }
    }

    return "win-$arch"
}

function Resolve-SdkArtifact {
    param(
        [Parameter(Mandatory)]
        [psobject]$Metadata,
        [Parameter(Mandatory)]
        [string]$SdkVersion,
        [Parameter(Mandatory)]
        [string]$Rid
    )

    $expectedUrl = "https://builds.dotnet.microsoft.com/dotnet/Sdk/$SdkVersion/dotnet-sdk-$SdkVersion-$Rid.zip"
    $candidates = [System.Collections.Generic.List[string]]::new()

    foreach ($release in @($Metadata.releases)) {
        $sdkEntries = [System.Collections.Generic.List[object]]::new()
        if ($null -ne $release.sdk) {
            $sdkEntries.Add($release.sdk)
        }
        foreach ($sdk in @($release.sdks)) {
            if ($null -ne $sdk) {
                $sdkEntries.Add($sdk)
            }
        }

        foreach ($sdk in $sdkEntries) {
            if ([string]$sdk.version -ne $SdkVersion) {
                continue
            }

            foreach ($file in @($sdk.files)) {
                if ([string]$file.rid -eq $Rid -and [string]$file.url -eq $expectedUrl) {
                    $candidates.Add("$([string]$file.url)|$([string]$file.hash)")
                }
            }
        }
    }

    $uniqueCandidates = @($candidates | Sort-Object -Unique)
    if ($uniqueCandidates.Count -ne 1) {
        throw "Microsoft release metadata did not contain exactly one SDK archive for $SdkVersion and $Rid."
    }

    $parts = $uniqueCandidates[0].Split('|', 2)
    $url = $parts[0]
    $hash = $parts[1]

    if ($url -ne $expectedUrl) {
        throw "Microsoft release metadata returned an unexpected SDK archive URL for $SdkVersion and $Rid."
    }
    if ($hash -notmatch '^[0-9A-Fa-f]{128}$') {
        throw "Microsoft release metadata contained an invalid SHA-512 hash for SDK $SdkVersion and $Rid."
    }

    return [pscustomobject]@{
        Url  = $url
        Hash = $hash.ToLowerInvariant()
    }
}

function Install-IsolatedSdk {
    $SelectedInteractively = [string]::IsNullOrWhiteSpace($script:Version)
    if (-not (Resolve-InstallVersion)) {
        return
    }

    if ($SelectedInteractively) {
        Write-ToolDisplay
    }

    $InstallDir = Join-Path $SdkRoot $Version
    $IsolatedDotNet = Get-IsolatedDotNetPath -SdkVersion $Version

    Write-ToolLabelValue -Label 'Target SDK:' -Value $Version
    Write-ToolLabelValue -Label 'Isolated install directory:' -Value $InstallDir
    Write-ToolDisplay

    Write-ToolInfo 'Checking existing installations...'
    Write-ToolDisplay

    $SystemSdks = @(Get-SystemSdkInventory)
    $SystemSdk = $SystemSdks |
        Where-Object { $_.Version -eq $Version } |
        Select-Object -First 1

    $IsolatedInstalled = $false
    if (Test-Path -LiteralPath $IsolatedDotNet -PathType Leaf) {
        $IsolatedSdks = & $IsolatedDotNet --list-sdks
        $ExitCode = $LASTEXITCODE
        if ($ExitCode -ne 0) {
            throw "Unable to inspect existing isolated SDK $Version with exit code $ExitCode."
        }

        $IsolatedVersions = @($IsolatedSdks | ForEach-Object { ($_ -split '\s+')[0] })
        $IsolatedInstalled = $IsolatedVersions -contains $Version
    }

    if ($IsolatedInstalled) {
        Write-ToolLabelValue -Label 'Isolated SDK:' -Value 'Already installed'
        Write-ToolLabelValue -Label 'Location:' -Value $InstallDir
    }
    else {
        Write-ToolLabelValue -Label 'Isolated SDK:' -Value 'Not installed'
    }

    Write-ToolDisplay

    if ($SystemSdk) {
        Write-ToolLabelValue -Label 'System SDK:' -Value 'Already installed'
        if (-not [string]::IsNullOrWhiteSpace($SystemSdk.Path)) {
            Write-ToolLabelValue -Label 'Location:' -Value (Join-Path $SystemSdk.Path $SystemSdk.Version)
        }
    }
    else {
        Write-ToolLabelValue -Label 'System SDK:' -Value 'Not installed'
    }
    Write-ToolDisplay

    if ($IsolatedInstalled) {
        return
    }

    if (Test-Path -LiteralPath $InstallDir) {
        throw "Isolated SDK destination already exists and cannot be replaced: $InstallDir"
    }

    if ($SystemSdk) {
        if (-not (Confirm-Action -Prompt 'Install an isolated copy in addition to the System SDK?')) {
            Write-ToolInfo 'Installation cancelled.'
            return
        }

        Write-ToolDisplay
    }

    $Channel = Get-SdkChannel
    $Rid = Get-SdkRid
    $MetadataUrl = "https://builds.dotnet.microsoft.com/dotnet/release-metadata/$Channel/releases.json"
    $MetadataPath = Join-Path $SdkRoot ('.release-metadata-{0}-{1}.json' -f $Version, [guid]::NewGuid().ToString('N'))
    $ArchivePath = Join-Path $SdkRoot ('.sdk-payload-{0}-{1}.zip' -f $Version, [guid]::NewGuid().ToString('N'))
    $StagingDir = Join-Path $SdkRoot ('.install-{0}-{1}' -f $Version, [guid]::NewGuid().ToString('N'))
    $StagedDotNet = Join-Path $StagingDir 'dotnet.exe'
    $PrimaryFailure = $null
    $CleanupFailure = $null

    try {
        Write-ToolInfo "Loading Microsoft release metadata for SDK $Version..."
        try {
            Invoke-WebRequest $MetadataUrl -OutFile $MetadataPath
            $Metadata = Get-Content -LiteralPath $MetadataPath -Raw | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw "Unable to load valid Microsoft release metadata for SDK ${Version}: $($_.Exception.Message)"
        }

        $Artifact = Resolve-SdkArtifact -Metadata $Metadata -SdkVersion $Version -Rid $Rid

        Write-ToolInfo "Downloading .NET SDK $Version payload..."
        try {
            Invoke-WebRequest $Artifact.Url -OutFile $ArchivePath
        }
        catch {
            throw "Unable to download the .NET SDK $Version payload: $($_.Exception.Message)"
        }

        try {
            $ActualHash = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA512).Hash.ToLowerInvariant()
        }
        catch {
            throw "Unable to verify the .NET SDK $Version payload: $($_.Exception.Message)"
        }

        if ($ActualHash -ne $Artifact.Hash) {
            throw "Integrity verification failed for the .NET SDK $Version payload."
        }

        New-Item -ItemType Directory -Path $StagingDir -WhatIf:$false -Confirm:$false | Out-Null
        Write-ToolInfo "Extracting verified .NET SDK $Version payload..."
        try {
            Expand-Archive -LiteralPath $ArchivePath -DestinationPath $StagingDir -Force
        }
        catch {
            throw "Unable to extract the verified .NET SDK $Version payload: $($_.Exception.Message)"
        }

        Write-ToolDisplay
        Write-ToolInfo 'Verifying the isolated SDK...'

        if (-not (Test-Path -LiteralPath $StagedDotNet -PathType Leaf)) {
            throw "The isolated dotnet executable was not found at $StagedDotNet"
        }

        $IsolatedSdks = & $StagedDotNet --list-sdks
        $ExitCode = $LASTEXITCODE
        if ($ExitCode -ne 0) {
            throw "Unable to verify isolated SDK $Version with exit code $ExitCode."
        }

        foreach ($IsolatedSdk in $IsolatedSdks) {
            Write-ToolDisplay $IsolatedSdk
        }

        $IsolatedVersions = @($IsolatedSdks | ForEach-Object { ($_ -split '\s+')[0] })
        if ($IsolatedVersions -notcontains $Version) {
            throw "SDK $Version was not found after installation."
        }

        if (Test-Path -LiteralPath $InstallDir) {
            throw "Isolated SDK destination already exists and cannot be replaced: $InstallDir"
        }

        try {
            Move-Item -LiteralPath $StagingDir -Destination $InstallDir -WhatIf:$false -Confirm:$false
            $StagingDir = $null
        }
        catch {
            throw "Unable to promote isolated SDK $Version into ${InstallDir}: $($_.Exception.Message)"
        }
    }
    catch {
        $PrimaryFailure = $_
    }
    finally {
        foreach ($TemporaryPath in @($MetadataPath, $ArchivePath)) {
            if ($TemporaryPath -and (Test-Path -LiteralPath $TemporaryPath)) {
                try {
                    Remove-Item -LiteralPath $TemporaryPath -Force -WhatIf:$false -Confirm:$false
                }
                catch {
                    Write-ToolWarning "Unable to clean install transaction file ${TemporaryPath}: $($_.Exception.Message)"
                    if ($null -eq $CleanupFailure) {
                        $CleanupFailure = $_
                    }
                }
            }
        }

        if ($StagingDir -and (Test-Path -LiteralPath $StagingDir)) {
            try {
                Remove-Item -LiteralPath $StagingDir -Recurse -Force -WhatIf:$false -Confirm:$false
            }
            catch {
                Write-ToolWarning "Unable to clean install staging directory ${StagingDir}: $($_.Exception.Message)"
                if ($null -eq $CleanupFailure) {
                    $CleanupFailure = $_
                }
            }
        }
    }

    if ($null -ne $PrimaryFailure) {
        throw $PrimaryFailure
    }

    if ($null -ne $CleanupFailure) {
        throw "Isolated SDK $Version was installed, but transaction cleanup failed: $($CleanupFailure.Exception.Message)"
    }

    Write-ToolDisplay
    Write-ToolSuccess 'Isolated SDK installation completed successfully.'
    Write-ToolLabelValue -Label 'Location:' -Value $InstallDir
}

function Test-IsolatedSdk {
    if ([string]::IsNullOrWhiteSpace($script:Version)) {
        throw '-Version is required with -Action Verify.'
    }

    Assert-ValidVersion

    $InstallDir = Join-Path $SdkRoot $Version
    $IsolatedDotNet = Get-IsolatedDotNetPath -SdkVersion $Version

    if (-not (Test-Path -LiteralPath $InstallDir -PathType Container)) {
        throw "Isolated SDK $Version is not installed under $SdkRoot."
    }

    if (-not (Test-Path -LiteralPath $IsolatedDotNet -PathType Leaf)) {
        throw "Isolated SDK $Version is incomplete: expected dotnet host was not found at $IsolatedDotNet."
    }

    try {
        $IsolatedSdks = & $IsolatedDotNet --list-sdks
        $ExitCode = $LASTEXITCODE
    }
    catch {
        throw "Unable to launch isolated SDK $Version host at ${IsolatedDotNet}: $($_.Exception.Message)"
    }

    if ($ExitCode -ne 0) {
        throw "Unable to verify isolated SDK $Version with exit code $ExitCode."
    }

    $IsolatedVersions = @($IsolatedSdks | ForEach-Object { ($_ -split '\s+')[0] })
    if ($IsolatedVersions -notcontains $Version) {
        throw "Isolated SDK $Version failed verification: the host did not report SDK $Version."
    }

    Write-ToolSuccess "Isolated SDK $Version is healthy."
    Write-ToolLabelValue -Label 'Location:' -Value $InstallDir
}

function Invoke-IsolatedSdkBuildServerShutdown {
    param(
        [string]$DotNetPath,
        [string]$SdkVersion
    )

    $EnvironmentOverrides = @{
        DOTNET_NOLOGO                      = 'true'
        DOTNET_GENERATE_ASPNET_CERTIFICATE = 'false'
        DOTNET_ADD_GLOBAL_TOOLS_TO_PATH    = 'false'
    }
    $PreviousEnvironment = @{}

    try {
        foreach ($Name in $EnvironmentOverrides.Keys) {
            $PreviousEnvironment[$Name] = [Environment]::GetEnvironmentVariable($Name, 'Process')
            [Environment]::SetEnvironmentVariable($Name, $EnvironmentOverrides[$Name], 'Process')
        }

        $null = & $DotNetPath build-server shutdown
        $ExitCode = $LASTEXITCODE
    }
    finally {
        foreach ($Name in $EnvironmentOverrides.Keys) {
            [Environment]::SetEnvironmentVariable($Name, $PreviousEnvironment[$Name], 'Process')
        }
    }

    if ($ExitCode -ne 0) {
        throw "Build-server shutdown failed for SDK $SdkVersion with exit code $ExitCode."
    }
}

function Invoke-IsolatedSdkDirectoryRemoval {
    param([string]$InstallDirectory)

    Remove-Item `
        -LiteralPath $InstallDirectory `
        -Recurse `
        -Force `
        -WhatIf:$false `
        -Confirm:$false

    if (Test-Path -LiteralPath $InstallDirectory) {
        throw "SDK directory still exists after removal: $InstallDirectory"
    }
}

# Removal is intentionally scoped to the selected version directory under SDK_ROOT.
function Remove-IsolatedSdk {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([switch]$Yes)

    if (-not (Resolve-RemoveVersion)) {
        return
    }

    $InstallDir = Join-Path $SdkRoot $Version
    $IsolatedDotNet = Get-IsolatedDotNetPath -SdkVersion $Version

    if (-not (Test-Path $IsolatedDotNet)) {
        throw "Isolated SDK $Version was not found at $InstallDir"
    }

    Write-ToolDisplay
    Write-ToolWarning "Isolated SDK $Version will be removed from $InstallDir"
    Write-ToolDisplay

    $ConfirmWasSpecified = $PSBoundParameters.ContainsKey('Confirm')
    if (-not $PSCmdlet.ShouldProcess($InstallDir, "Remove isolated .NET SDK $Version")) {
        return
    }

    $UseToolConfirmation = -not $Yes -and
    -not $ConfirmWasSpecified -and
    $ConfirmPreference -in @(
        [System.Management.Automation.ConfirmImpact]::High,
        [System.Management.Automation.ConfirmImpact]::None)

    if ($UseToolConfirmation -and -not (Confirm-Action -Prompt 'Continue?')) {
        Write-ToolInfo 'Removal cancelled.'
        return
    }

    Write-ToolInfo "Shutting down build servers for SDK $Version..."
    Invoke-IsolatedSdkBuildServerShutdown `
        -DotNetPath $IsolatedDotNet `
        -SdkVersion $Version

    Write-ToolInfo "Removing $InstallDir..."
    Invoke-IsolatedSdkDirectoryRemoval -InstallDirectory $InstallDir

    Write-ToolSuccess "Isolated SDK $Version was removed."
}

function Invoke-SelectedAction {
    Assert-ActionParameterUsage

    switch ($script:Action) {
        'Install' { Install-IsolatedSdk }
        'Remove' {
            $RemoveArguments = @{}
            if ($Yes) {
                $RemoveArguments.Yes = $true
            }
            if ($script:ConfirmWasSpecified) {
                $RemoveArguments.Confirm = $script:ConfirmValue
            }
            if ($script:WhatIfWasSpecified) {
                $RemoveArguments.WhatIf = $script:WhatIfValue
            }

            Remove-IsolatedSdk @RemoveArguments
        }
        'List' { Show-InstalledSdk }
        'Verify' { Test-IsolatedSdk }
    }
}

Install-ToolIfNeeded

if ($script:Bootstrapped) {
    return
}

New-Item `
    -ItemType Directory `
    -Path $SdkRoot `
    -Force `
    -WhatIf:$false `
    -Confirm:$false | Out-Null

# Keep execution outside the caller's repository so a local global.json cannot
# influence SDK resolution during the tool's work.
Push-Location $SdkRoot
try {
    try {
        if ($script:InteractiveSession) {
            while ($true) {
                $script:Action = $null
                $script:Version = $null
                $script:BackToMain = $false
                $script:ExitRequested = $false

                if (-not (Select-Action)) {
                    return
                }

                Write-ToolDisplay
                Invoke-SelectedAction
                if ($script:ExitRequested) {
                    return
                }
                Write-ToolDisplay
            }
        }

        if (-not (Select-Action)) {
            return
        }

        Invoke-SelectedAction
    }
    catch {
        Write-Error -Message $_.Exception.Message -ErrorAction Continue
        exit 1
    }
}
finally {
    Pop-Location
}
