<#
.SYNOPSIS
Installs and manages isolated .NET SDK versions on Windows with PowerShell 7.

.DESCRIPTION
Installs exact .NET SDK versions under the current user's dotnet-sdks directory without modifying the system-wide .NET installation or PATH. Isolated SDKs remain under that user-owned root and are not added to PATH.

Supported product actions are Install, Remove, List, Verify, and Audit. Audit is an explicit online, read-only lifecycle and servicing assessment for installed Isolated and System SDKs. When Action and SdkVersion are both omitted, the tool starts a persistent interactive session. With interactive terminal input and output, a normal completed result or cancellation/no-change result remains visible until Enter is pressed, then the session returns to the immediate parent screen that launched the result. List and Audit return to Main; Verify and Remove return to their SDK lists; Install returns to the selected channel's SDK list. Redirected, piped, or captured execution never waits for that acknowledgement. When Action is omitted and SdkVersion is supplied, Install is selected. Explicit actions and exact-version requests remain one-shot. Explicit List with SdkVersion is invalid. Direct Verify requires an exact SdkVersion; interactive Verify selects an installed isolated SDK from Main and runs the same read-only health check. Install or Remove without a resolved version may require interactive selection.

Yes skips supported confirmation prompts only; it does not choose a missing action or version. PowerShell WhatIf and Confirm are supported only for Remove. Required interactive input that is unavailable is an operational failure. Explicit cancellation is a successful no-change result. Operational failures return a nonzero exit status.

Exact-version installs bypass release-metadata discovery. Interactive install selection uses Microsoft's published .NET release metadata. List reports recognized isolated SDKs first and then the read-only SDK inventory returned by the normally resolved dotnet --list-sdks host. System SDK discovery is supplemental rather than an exhaustive filesystem inventory, and system SDKs are never managed by Remove or targeted by Verify.

.PARAMETER Action
Specifies the operation to perform: Install, Remove, List, Verify, or Audit. When omitted, the script starts the persistent interactive session unless SdkVersion is supplied, in which case Install is selected.

.PARAMETER SdkVersion
Specifies an exact .NET SDK version. When omitted for Install or Remove, the script provides an interactive version selection workflow. Direct Verify requires SdkVersion; interactive Verify selects from installed isolated SDKs. SdkVersion is invalid with explicit List or Audit actions. The parameter is positional, so a bare exact SDK version has the same meaning as -SdkVersion.

.PARAMETER Yes
Skips confirmation prompts that support automatic confirmation. It does not supply a missing action or version.

.PARAMETER AllowUnsupportedShutdown
Deprecated Remove-only compatibility option, accepted for existing scripts but no longer required. Verified historical SDK shutdown incompatibility is handled automatically after ordinary Remove confirmation. Any unexpected or supported shutdown failure still blocks removal.

.PARAMETER Version
Shows the isolated-dotnet-sdk release/source identity and exits without bootstrap, network access, SDK discovery, prompting, or mutation. This is distinct from SdkVersion, which selects the .NET SDK to install, verify, or remove.

.EXAMPLE
.\isolated-dotnet-sdk.ps1 -Version

Shows the tool release/source identity and exits.

.EXAMPLE
.\isolated-dotnet-sdk.ps1 -Action List

Lists recognized isolated SDKs and SDKs reported by the normally resolved system dotnet host once and exits.

.EXAMPLE
.\isolated-dotnet-sdk.ps1 -Action Install -SdkVersion 10.0.100

Installs .NET SDK 10.0.100 in an isolated directory.

.EXAMPLE
.\isolated-dotnet-sdk.ps1 -Action Verify -SdkVersion 10.0.100

Reports the SDK lifecycle and validates its isolated host, exact SDK origin, and exact SDK resolution. Microsoft metadata unavailability does not fail a locally valid SDK.

.EXAMPLE
.\isolated-dotnet-sdk.ps1 -Action Remove -SdkVersion 10.0.100 -Yes

Removes the isolated .NET SDK 10.0.100 without the tool-owned confirmation prompt.

.EXAMPLE
.\isolated-dotnet-sdk.ps1 -Action Remove -SdkVersion 1.0.4 -AllowUnsupportedShutdown -Yes

For backward compatibility, this legacy option is accepted but no longer needed; -Yes skips the ordinary deletion confirmation.

.EXAMPLE
.\isolated-dotnet-sdk.ps1 -Action Remove -SdkVersion 10.0.100 -WhatIf

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
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', PositionalBinding = $false)]
param(
    [string]$Action,
    [Parameter(Position = 0)]
    [string]$SdkVersion,
    [switch]$Yes,
    [switch]$Version,
    [switch]$AllowUnsupportedShutdown
)

$ErrorActionPreference = 'Stop'

$RepositoryRawBase = 'https://raw.githubusercontent.com/infoconex/isolated-dotnet-sdk/main'
$ReleaseIndexUrl = 'https://builds.dotnet.microsoft.com/dotnet/release-metadata/releases-index.json'
$ReleaseScheduleUrl = 'https://raw.githubusercontent.com/dotnet/core/main/release-notes/README.md'
$ToolName = 'isolated-dotnet-sdk.ps1'
$ToolReleaseIdentity = 'development'
$SdkRoot = Join-Path $HOME 'dotnet-sdks'
$ToolPath = Join-Path $SdkRoot $ToolName
$script:Bootstrapped = $false
$script:ActionWasSpecified = $PSBoundParameters.ContainsKey('Action')
$script:SdkVersionWasSpecified = $PSBoundParameters.ContainsKey('SdkVersion')
$script:InteractiveSession = -not $script:ActionWasSpecified -and -not $script:SdkVersionWasSpecified
$script:BackToMain = $false
$script:ExitRequested = $false
$script:InstallResumeChannel = $null
$script:InstallResumeReleaseIndex = $null
$script:InstallResumeChannelMetadata = $null
$script:InstallResultParent = 'Main'
$script:ConfirmWasSpecified = $PSBoundParameters.ContainsKey('Confirm')
$script:ConfirmValue = if ($script:ConfirmWasSpecified) { [bool]$PSBoundParameters['Confirm'] } else { $false }
$script:WhatIfWasSpecified = $PSBoundParameters.ContainsKey('WhatIf')
$script:WhatIfValue = if ($script:WhatIfWasSpecified) { [bool]$PSBoundParameters['WhatIf'] } else { $false }

function Get-ToolVersionText {
    if ($ToolReleaseIdentity -eq 'development') {
        return 'isolated-dotnet-sdk development (main)'
    }

    if ($ToolReleaseIdentity -match '^v[0-9]+\.[0-9]+\.[0-9]+$') {
        return "isolated-dotnet-sdk $ToolReleaseIdentity"
    }

    throw "Invalid tool release identity: $ToolReleaseIdentity"
}

function Get-ToolMenuIdentity {
    if ($ToolReleaseIdentity -eq 'development') {
        return 'Isolated .NET SDK development (main)'
    }

    if ($ToolReleaseIdentity -match '^v[0-9]+\.[0-9]+\.[0-9]+$') {
        return "Isolated .NET SDK $ToolReleaseIdentity"
    }

    throw "Invalid tool release identity: $ToolReleaseIdentity"
}

function Write-ToolDisplay {
    param(
        [AllowEmptyString()]
        [string]$Message = ''
    )

    Write-Information -MessageData $Message -InformationAction Continue
}

# Render readable contextual diagnostics through the information stream.
# The original native exception is emitted once by Write-Error below, where
# the error stream and failure exit code remain available to callers.
function Write-ToolRemovalFailure {
    param([string]$Message)

    $Sections = $Message -split "`nDiagnostics:`n", 2
    # The exception stays in the original failure record for Write-Error;
    # do not print it again in the application diagnostics.
    $DiagnosticText = ($Sections[1] -split "`nDetails: ", 2)[0]

    Write-ToolDisplay
    Write-ToolDisplay (Format-ToolMessage -Kind Error -Message 'Error:')
    Write-ToolDisplay "  $($Sections[0])"
    Write-ToolDisplay
    Write-ToolDisplay (Format-ToolMessage -Kind Diagnostics -Message 'Diagnostics:')
    $NestedHeadings = @('Possible causes:', 'To find a file-lock holder:', 'To inspect filesystem permissions:')
    foreach ($Line in ($DiagnosticText -split "`n")) {
        $NestedHeading = $null
        foreach ($Candidate in $NestedHeadings) {
            if ($Line.StartsWith($Candidate, [StringComparison]::Ordinal)) {
                $NestedHeading = $Candidate
                break
            }
        }
        if ($null -ne $NestedHeading) {
            Write-ToolDisplay
            Write-ToolDisplay "  $(Format-ToolMessage -Kind DiagnosticSubheading -Message $NestedHeading)"
            $Explanation = $Line.Substring($NestedHeading.Length).TrimStart()
            if (-not [string]::IsNullOrWhiteSpace($Explanation)) {
                Write-ToolDisplay "    $Explanation"
            }
        }
        else {
            Write-ToolDisplay "  $Line"
        }
    }
    Write-ToolDisplay
}

function Format-ToolMessage {
    param(
        [ValidateSet('Heading', 'Accent', 'Success', 'Error', 'Diagnostics', 'DiagnosticSubheading')]
        [string]$Kind,
        [string]$Message
    )

    if ($null -eq $PSStyle) {
        return $Message
    }

    $SupportsVirtualTerminal = $null -ne $Host.UI -and $Host.UI.SupportsVirtualTerminal
    $UseAnsi = $PSStyle.OutputRendering -eq 'Ansi'
    if (-not $UseAnsi -and $PSStyle.OutputRendering -eq 'Host') {
        $UseAnsi = -not [Console]::IsOutputRedirected -and $SupportsVirtualTerminal
    }

    if (-not $UseAnsi) {
        return $Message
    }

    $Foreground = switch ($Kind) {
        'Success' { $PSStyle.Foreground.Green }
        'Error' { $PSStyle.Foreground.Red }
        'Diagnostics' { $PSStyle.Foreground.Yellow }
        default { $PSStyle.Foreground.Cyan }
    }

    return "$Foreground$Message$($PSStyle.Reset)"
}

function Write-ToolInfo {
    param([string]$Message)
    Write-ToolDisplay $Message
}

function Write-ToolExit {
    Write-ToolDisplay
    Write-ToolInfo 'Exiting.'
    Write-ToolDisplay
}

function Write-ToolLabelValue {
    param(
        [string]$Label,
        [AllowEmptyString()]
        [string]$Value = '',
        [switch]$SuccessValue
    )

    $AccentLabel = Format-ToolMessage -Kind Accent -Message $Label
    if ([string]::IsNullOrEmpty($Value)) {
        Write-ToolDisplay $AccentLabel
        return
    }

    $RenderedValue = if ($SuccessValue) {
        Format-ToolMessage -Kind Success -Message $Value
    }
    else {
        $Value
    }
    Write-ToolDisplay "$AccentLabel $RenderedValue"
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

    if ($script:Action -notin @('Install', 'Remove', 'List', 'Verify', 'Audit')) {
        throw "Invalid action: $script:Action"
    }
}

function Assert-ValidSdkVersion {
    if ($script:SdkVersion -notmatch '^[0-9A-Za-z][0-9A-Za-z.+-]*$') {
        throw "Invalid SDK version: $script:SdkVersion"
    }
}

function Read-ToolInput {
    param(
        [AllowEmptyString()]
        [string]$Prompt = ''
    )

    try {
        if ([string]::IsNullOrEmpty($Prompt)) {
            return Read-Host
        }

        return Read-Host $Prompt
    }
    catch {
        throw 'Interactive input is unavailable.'
    }
}

function Wait-ForInteractiveResultAcknowledgement {
    param(
        [string]$Destination = 'Main',
        [bool]$InputRedirected = [Console]::IsInputRedirected,
        [bool]$OutputRedirected = [Console]::IsOutputRedirected
    )

    if (-not $script:InteractiveSession -or $InputRedirected -or $OutputRedirected) {
        return
    }

    Write-ToolDisplay
    Write-ToolDisplay "Press Enter to return to $Destination..."
    [void](Read-ToolInput)
}

function Clear-InteractiveScreen {
    param(
        [bool]$InputRedirected = [Console]::IsInputRedirected,
        [bool]$OutputRedirected = [Console]::IsOutputRedirected
    )

    if (-not $script:InteractiveSession -or $InputRedirected -or $OutputRedirected) {
        return
    }

    # Terminal control is optional: unsupported hosts continue with scrolling.
    try {
        Clear-Host -ErrorAction Stop
    }
    catch {
        return
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
    if ($script:SdkVersionWasSpecified) {
        $Arguments.SdkVersion = $SdkVersion
    }
    if ($Yes) {
        $Arguments.Yes = $true
    }
    if ($AllowUnsupportedShutdown) {
        $Arguments.AllowUnsupportedShutdown = $true
    }
    if ($script:ConfirmWasSpecified) {
        $Arguments.Confirm = $script:ConfirmValue
    }
    if ($script:WhatIfWasSpecified) {
        $Arguments.WhatIf = $script:WhatIfValue
    }

    & $ToolPath @Arguments
    # The child is a PowerShell script, not a native executable. Optional host
    # diagnostics may leave $LASTEXITCODE nonzero even when the child action
    # succeeds; use the child invocation's success state instead.
    if (-not $?) {
        $ChildExitCode = if ($LASTEXITCODE -ne 0) { $LASTEXITCODE } else { 1 }
        exit $ChildExitCode
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

function Test-RemovableSdkVersion {
    param([string]$Version)
    return $Version -cmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z][0-9A-Za-z.+-]*)?$'
}

function Get-RemoveSdkCandidateVersion {
    if (-not (Test-Path -LiteralPath $SdkRoot -PathType Container)) {
        return @()
    }
    $Directories = Get-ChildItem -LiteralPath $SdkRoot -Directory -ErrorAction Stop |
        Where-Object {
            (Test-RemovableSdkVersion -Version $_.Name) -and
            -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)
        }
    return @($Directories | ForEach-Object { $_.Name })
}

function Get-IsolatedSdkVersion {
    $SdkDirectories = Get-ChildItem `
        -Path $SdkRoot `
        -Directory `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -notlike '.removing-*' -and
            $_.Name -ne '.pending-removals' -and
            -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
            (Test-Path (Join-Path $_.FullName 'dotnet.exe'))
        } |
        Sort-Object Name

    return @($SdkDirectories | ForEach-Object { $_.Name })
}

function Show-InstalledSdk {
    $IsolatedVersions = @(Get-OrderedSdkVersion @(Get-IsolatedSdkVersion))
    $SystemSdks = @(Get-OrderedSdkInventory @(Get-SystemSdkInventory))

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

function Get-OrderedSdkInventory {
    param([object[]]$Inventory)

    return @(
        $Inventory |
            ForEach-Object {
                [pscustomobject]@{
                    Item    = $_
                    SortKey = Get-SdkVersionSortKey ([string]$_.Version)
                }
            } |
            Sort-Object `
            @{ Expression = 'SortKey'; Descending = $true }, `
            @{ Expression = { [string]$_.Item.Version }; Descending = $true } |
            ForEach-Object { $_.Item }
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

    if (-not [string]::IsNullOrWhiteSpace($script:SdkVersion)) {
        $script:Action = 'Install'
        return $true
    }

    while ($true) {
        Write-ToolHeading (Get-ToolMenuIdentity)
        Write-ToolDisplay
        Write-ToolHeading 'What would you like to do?'
        Write-ToolDisplay
        Write-ToolDisplay '  I. Install an SDK'
        Write-ToolDisplay '  R. Remove an isolated SDK'
        Write-ToolDisplay '  L. List installed SDKs'
        Write-ToolDisplay '  V. Verify an isolated SDK'
        Write-ToolDisplay '  A. Audit installed SDKs'
        Write-ToolDisplay
        Write-ToolDisplay '  E. Exit'
        Write-ToolDisplay

        $Selection = Read-ToolInput 'Selection'

        switch ($Selection) {
            'i' { $script:Action = 'Install'; return $true }
            'I' { $script:Action = 'Install'; return $true }
            'r' { $script:Action = 'Remove'; return $true }
            'R' { $script:Action = 'Remove'; return $true }
            'l' { $script:Action = 'List'; return $true }
            'L' { $script:Action = 'List'; return $true }
            'v' { $script:Action = 'Verify'; return $true }
            'V' { $script:Action = 'Verify'; return $true }
            'a' { $script:Action = 'Audit'; return $true }
            'A' { $script:Action = 'Audit'; return $true }
            'e' { Write-ToolExit; return $false }
            'E' { Write-ToolExit; return $false }
            default {
                Write-InvalidSelection -Selection $Selection -Choices 'Choose I, R, L, V, A, or E.'
                Write-ToolDisplay
            }
        }
    }
}

function Assert-ActionParameterUsage {
    if ($script:Action -in @('List', 'Audit') -and $script:SdkVersionWasSpecified) {
        throw '-SdkVersion is supported only with -Action Install, Remove, or Verify.'
    }

    if ($script:Action -eq 'Verify' -and
        -not $script:InteractiveSession -and
        [string]::IsNullOrWhiteSpace($script:SdkVersion)) {
        throw '-SdkVersion is required with -Action Verify.'
    }

    if ($script:Action -eq 'Remove') {
        return
    }

    if ($AllowUnsupportedShutdown) {
        throw '-AllowUnsupportedShutdown is supported only with -Action Remove.'
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


# SDK 2.1.0-2.1.202 belong to .NET Core 2.0, not the .NET Core 2.1
# channel (which starts with the SDK 2.1.300 feature band).
function Test-IsEarlyDotNet2Sdk {
    param([string]$Version)

    if ($Version -match '^2\.0\.') {
        return $true
    }

    $Match = [regex]::Match($Version, '^2\.1\.(?<feature>[0-9]+)(?:-|$)')
    if (-not $Match.Success) {
        return $false
    }

    $Feature = [long]0
    return ([long]::TryParse($Match.Groups['feature'].Value, [ref]$Feature) -and $Feature -lt 300)
}

function Get-SdkChannelFromVersion {
    param([string]$Version)

    $Match = [regex]::Match($Version, '^(?<major>[0-9]+)\.(?<minor>[0-9]+)\.')
    if (-not $Match.Success) {
        return $null
    }

    if (Test-IsEarlyDotNet2Sdk -Version $Version) {
        return '2.0'
    }

    return "$($Match.Groups['major'].Value).$($Match.Groups['minor'].Value)"
}

function Compare-SdkVersion {
    param(
        [string]$Left,
        [string]$Right
    )

    return [string]::CompareOrdinal(
        (Get-SdkVersionSortKey $Left),
        (Get-SdkVersionSortKey $Right))
}

function Get-ReleaseSdkVersion {
    param($Release)

    $Versions = [System.Collections.Generic.List[string]]::new()
    $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    if ($Release.sdk -and -not [string]::IsNullOrWhiteSpace([string]$Release.sdk.version)) {
        $Version = [string]$Release.sdk.version
        if ($Seen.Add($Version)) {
            $Versions.Add($Version)
        }
    }

    foreach ($Sdk in @($Release.sdks)) {
        if ($Sdk -and -not [string]::IsNullOrWhiteSpace([string]$Sdk.version)) {
            $Version = [string]$Sdk.version
            if ($Seen.Add($Version)) {
                $Versions.Add($Version)
            }
        }
    }

    return @($Versions)
}

function Test-SecurityUpdateAvailable {
    param(
        $ChannelMetadata,
        [string]$InstalledVersion
    )

    $KnownVersions = @(Get-ChannelSdkVersion $ChannelMetadata)
    if ($KnownVersions -notcontains $InstalledVersion) {
        return $false
    }

    foreach ($Release in @($ChannelMetadata.releases)) {
        if ($Release.security -ne $true) {
            continue
        }

        foreach ($Version in @(Get-ReleaseSdkVersion $Release)) {
            if ((Compare-SdkVersion -Left $Version -Right $InstalledVersion) -gt 0) {
                return $true
            }
        }
    }

    return $false
}

function Get-SdkPrereleaseLabel {
    param([string]$Version)

    $Match = [regex]::Match($Version, '-(?<label>preview|rc)\.(?<sequence>[0-9]+)(?:\.|$)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $Match.Success) {
        return $null
    }

    $Sequence = $Match.Groups['sequence'].Value
    if ($Match.Groups['label'].Value -ieq 'rc') {
        return "RC$Sequence"
    }

    return "Preview $Sequence"
}

function Get-SdkReleaseDate {
    param(
        $ChannelMetadata,
        [string]$Version
    )

    foreach ($Release in @($ChannelMetadata.releases)) {
        if (@(Get-ReleaseSdkVersion $Release) -contains $Version) {
            $ReleaseDate = [string]$Release.'release-date'
            if (-not [string]::IsNullOrWhiteSpace($ReleaseDate)) {
                return $ReleaseDate
            }
            return $null
        }
    }

    return $null
}

function Get-AuditGoLiveDate {
    param(
        [string]$ChannelVersion,
        [hashtable]$Cache
    )

    if ($Cache.ContainsKey($ChannelVersion)) {
        return [string]$Cache[$ChannelVersion]
    }

    if (-not $Cache.ContainsKey('__schedule')) {
        try {
            $Schedule = Invoke-RestMethod -Uri $ReleaseScheduleUrl
            $Cache['__schedule'] = [string]$Schedule
        }
        catch {
            $Cache['__schedule'] = ''
        }
    }

    $ScheduleText = [string]$Cache['__schedule']
    if ([string]::IsNullOrWhiteSpace($ScheduleText)) {
        $Cache[$ChannelVersion] = ''
        return $null
    }

    $Pattern = '(?m)^\|\s*\[\.NET\s+' +
    [regex]::Escape($ChannelVersion) +
    '\]\([^)]+\)\s*\|\s*(?<date>[^|]+)\|\s*[^|]+\|\s*Go-Live\s*\|'
    $Match = [regex]::Match($ScheduleText, $Pattern)
    if (-not $Match.Success) {
        $Cache[$ChannelVersion] = ''
        return $null
    }

    $DateText = $Match.Groups['date'].Value.Trim()
    $LinkMatch = [regex]::Match($DateText, '^\[(?<text>[^\]]+)\]\([^)]+\)$')
    if ($LinkMatch.Success) {
        $DateText = $LinkMatch.Groups['text'].Value.Trim()
    }

    $ParsedDate = [datetime]::MinValue
    if (-not [datetime]::TryParseExact(
            $DateText,
            'MMMM d, yyyy',
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::None,
            [ref]$ParsedDate)) {
        $Cache[$ChannelVersion] = ''
        return $null
    }

    $Result = $ParsedDate.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    $Cache[$ChannelVersion] = $Result
    return $Result
}

function Get-SdkAuditClassification {
    param(
        [string]$Version,
        $ChannelEntry,
        $ChannelMetadata,
        [hashtable]$GoLiveCache
    )

    $ChannelVersion = [string]$ChannelEntry.'channel-version'
    $SupportPhase = [string]$ChannelEntry.'support-phase'
    $LatestSdk = [string]$ChannelEntry.'latest-sdk'
    $ReleaseTypeValue = [string]$ChannelEntry.'release-type'

    if ($ReleaseTypeValue -notin @('lts', 'sts')) {
        throw "Invalid .NET release metadata for .NET $ChannelVersion."
    }

    $ReleaseType = $ReleaseTypeValue.ToUpperInvariant()
    $ReleaseDate = Get-SdkReleaseDate -ChannelMetadata $ChannelMetadata -Version $Version
    $EndOfSupportDate = [string]$ChannelEntry.'eol-date'
    if ([string]::IsNullOrWhiteSpace($EndOfSupportDate)) {
        $EndOfSupportDate = ''
    }

    $GoLiveDate = ''
    if ($SupportPhase -eq 'go-live') {
        $ResolvedGoLiveDate = Get-AuditGoLiveDate -ChannelVersion $ChannelVersion -Cache $GoLiveCache
        if (-not [string]::IsNullOrWhiteSpace($ResolvedGoLiveDate)) {
            $GoLiveDate = $ResolvedGoLiveDate
        }
    }

    if ($SupportPhase -eq 'eol') {
        return [pscustomobject]@{
            Version          = $Version
            ReleaseType      = $ReleaseType
            ServicingStatus  = ''
            StatusToken      = 'EOL'
            ReleaseDate      = $ReleaseDate
            GoLiveDate       = $GoLiveDate
            EndOfSupportDate = $EndOfSupportDate
        }
    }

    $Comparison = Compare-SdkVersion -Left $Version -Right $LatestSdk
    if ($Comparison -gt 0) {
        $Servicing = 'Newer than known metadata'
    }
    elseif ($Comparison -eq 0) {
        $Servicing = 'Current'
    }
    else {
        $Servicing = "Update available -> $LatestSdk"
        $IsPrerelease = $Version.Contains('-') -or $SupportPhase -eq 'preview'
        if (-not $IsPrerelease -and
            (Test-SecurityUpdateAvailable -ChannelMetadata $ChannelMetadata -InstalledVersion $Version)) {
            $Servicing = "Security update available -> $LatestSdk"
        }
    }

    $PrereleaseLabel = Get-SdkPrereleaseLabel -Version $Version
    $StatusToken = if (-not [string]::IsNullOrWhiteSpace($PrereleaseLabel)) {
        $PrereleaseLabel
    }
    else {
        switch ($SupportPhase) {
            'maintenance' { 'Maintenance' }
            'preview' { 'Preview' }
            'go-live' { 'Go Live' }
            'active' { if ($Servicing -eq 'Current') { 'Current' } else { 'Active' } }
            default { 'Unsupported' }
        }
    }

    if ($Servicing -eq 'Current') {
        if ([string]::IsNullOrWhiteSpace($StatusToken)) {
            $StatusToken = 'Current'
        }
        $Servicing = ''
    }

    return [pscustomobject]@{
        Version          = $Version
        ReleaseType      = $ReleaseType
        ServicingStatus  = $Servicing
        StatusToken      = $StatusToken
        ReleaseDate      = $ReleaseDate
        GoLiveDate       = $GoLiveDate
        EndOfSupportDate = $EndOfSupportDate
    }
}

function Get-AuditChannelRecord {
    param(
        [string]$ChannelVersion,
        [string]$MetadataUrl,
        [hashtable]$Cache
    )

    if ($Cache.ContainsKey($ChannelVersion)) {
        return $Cache[$ChannelVersion]
    }

    try {
        $Metadata = Invoke-RestMethod -Uri $MetadataUrl
    }
    catch {
        throw "Unable to load release metadata for .NET $ChannelVersion."
    }

    if ($null -eq $Metadata -or $null -eq $Metadata.releases) {
        throw "Invalid release metadata for .NET $ChannelVersion."
    }

    $Versions = @(Get-ChannelSdkVersion $Metadata)
    if (-not $Versions) {
        throw "Invalid release metadata for .NET $ChannelVersion."
    }

    $Cache[$ChannelVersion] = $Metadata
    return $Metadata
}

function Format-AuditStatusToken {
    param([string]$StatusToken)

    if ($StatusToken -notin @('Current', 'Maintenance', 'EOL') -or $null -eq $PSStyle) {
        return $StatusToken
    }

    $SupportsVirtualTerminal = $null -ne $Host.UI -and $Host.UI.SupportsVirtualTerminal
    $UseAnsi = $PSStyle.OutputRendering -eq 'Ansi'
    if (-not $UseAnsi -and $PSStyle.OutputRendering -eq 'Host') {
        $UseAnsi = -not [Console]::IsOutputRedirected -and $SupportsVirtualTerminal
    }

    if (-not $UseAnsi) {
        return $StatusToken
    }

    $Foreground = switch ($StatusToken) {
        'Current' { $PSStyle.Foreground.Green }
        'Maintenance' { $PSStyle.Foreground.Yellow }
        'EOL' { $PSStyle.Foreground.Red }
    }

    return "$Foreground$StatusToken$($PSStyle.Reset)"
}

function Get-SdkAuditDisplayLayout {
    param([object[]]$Classifications)

    $Layout = [ordered]@{
        Version     = 0
        ReleaseType = 0
        Lifecycle   = 0
    }

    foreach ($Classification in $Classifications) {
        $Version = [string]$Classification.Version
        $ReleaseType = [string]$Classification.ReleaseType
        $Lifecycle = [string]$Classification.StatusToken

        $Layout.Version = [Math]::Max($Layout.Version, $Version.Length)
        $Layout.ReleaseType = [Math]::Max($Layout.ReleaseType, $ReleaseType.Length)
        $Layout.Lifecycle = [Math]::Max($Layout.Lifecycle, $Lifecycle.Length)
    }

    return [pscustomobject]$Layout
}

function Format-SdkAuditRow {
    param(
        $Classification,
        $Layout
    )

    $Version = [string]$Classification.Version
    $ReleaseType = [string]$Classification.ReleaseType
    $Lifecycle = [string]$Classification.StatusToken
    $Servicing = [string]$Classification.ServicingStatus
    $RenderedLifecycle = if ([string]::IsNullOrWhiteSpace($Lifecycle)) {
        ''
    }
    else {
        Format-AuditStatusToken -StatusToken $Lifecycle
    }

    $Line = '  ' + $Version.PadRight($Layout.Version)
    if ($Layout.ReleaseType -gt 0) {
        $Line += '  ' + $ReleaseType.PadRight($Layout.ReleaseType)
    }
    if ($Layout.Lifecycle -gt 0) {
        $Line += '  ' + $RenderedLifecycle
        $Line += ' ' * [Math]::Max(0, ($Layout.Lifecycle - $Lifecycle.Length))
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Classification.ReleaseDate)) {
        $Line += "  Release: $($Classification.ReleaseDate)"
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Classification.GoLiveDate)) {
        $Line += "  Go Live: $($Classification.GoLiveDate)"
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Classification.EndOfSupportDate)) {
        $Line += "  EOS: $($Classification.EndOfSupportDate)"
    }

    if (-not [string]::IsNullOrWhiteSpace($Servicing)) {
        $ServicingDisplay = $Servicing
        $ServicingMatch = [regex]::Match(
            $Servicing,
            '^(?:Security update available|Update available) -> (?<version>\S+)$')
        if ($ServicingMatch.Success) {
            $ServicingDisplay = "Update -> $($ServicingMatch.Groups['version'].Value)"
        }
        $Line += '  ' + $ServicingDisplay
    }

    return $Line.TrimEnd()
}

function Invoke-SdkAudit {
    $IsolatedVersions = @(Get-OrderedSdkVersion @(Get-IsolatedSdkVersion))
    $SystemSdks = @(Get-OrderedSdkInventory @(Get-SystemSdkInventory))

    if (-not $IsolatedVersions -and -not $SystemSdks) {
        Write-ToolHeading '.NET SDK audit'
        Write-ToolDisplay
        Write-ToolHeading 'Isolated SDKs:'
        Write-ToolDisplay '  None'
        Write-ToolDisplay
        Write-ToolHeading 'System SDKs:'
        Write-ToolDisplay '  None'
        return
    }

    $ReleaseIndex = Get-ReleaseIndex
    $ChannelEntries = @{}
    foreach ($Entry in @($ReleaseIndex.'releases-index')) {
        $ChannelVersion = [string]$Entry.'channel-version'
        if (-not [string]::IsNullOrWhiteSpace($ChannelVersion) -and
            -not $ChannelEntries.ContainsKey($ChannelVersion)) {
            $ChannelEntries[$ChannelVersion] = $Entry
        }
    }

    $MetadataCache = @{}
    $GoLiveCache = @{}
    $ClassificationByVersion = @{}
    $AllVersions = @($IsolatedVersions) + @($SystemSdks | ForEach-Object { $_.Version })
    foreach ($Version in @($AllVersions | Select-Object -Unique)) {
        $ChannelVersion = Get-SdkChannelFromVersion -Version $Version
        if ([string]::IsNullOrWhiteSpace($ChannelVersion) -or
            -not $ChannelEntries.ContainsKey($ChannelVersion)) {
            $ClassificationByVersion[$Version] = [pscustomobject]@{
                Version          = $Version
                ReleaseType      = ''
                ServicingStatus  = ''
                StatusToken      = 'Unknown channel'
                ReleaseDate      = ''
                GoLiveDate       = ''
                EndOfSupportDate = ''
            }
            continue
        }

        $Entry = $ChannelEntries[$ChannelVersion]
        $LatestSdk = [string]$Entry.'latest-sdk'
        $SupportPhase = [string]$Entry.'support-phase'
        $ReleaseType = [string]$Entry.'release-type'
        $MetadataUrl = [string]$Entry.'releases.json'
        if ([string]::IsNullOrWhiteSpace($LatestSdk) -or
            [string]::IsNullOrWhiteSpace($SupportPhase) -or
            $ReleaseType -notin @('lts', 'sts') -or
            [string]::IsNullOrWhiteSpace($MetadataUrl)) {
            throw "Invalid .NET release metadata for .NET $ChannelVersion."
        }

        $ChannelMetadata = Get-AuditChannelRecord -ChannelVersion $ChannelVersion -MetadataUrl $MetadataUrl -Cache $MetadataCache
        if (@(Get-ChannelSdkVersion $ChannelMetadata) -notcontains $LatestSdk) {
            throw "Invalid release metadata for .NET $ChannelVersion."
        }

        $ClassificationByVersion[$Version] = Get-SdkAuditClassification -Version $Version -ChannelEntry $Entry -ChannelMetadata $ChannelMetadata -GoLiveCache $GoLiveCache
    }

    $Layout = Get-SdkAuditDisplayLayout -Classifications @($ClassificationByVersion.Values)

    Write-ToolHeading '.NET SDK audit'
    Write-ToolDisplay
    Write-ToolHeading 'Isolated SDKs:'
    if (-not $IsolatedVersions) {
        Write-ToolDisplay '  None'
    }
    else {
        foreach ($Version in $IsolatedVersions) {
            Write-ToolDisplay (Format-SdkAuditRow -Classification $ClassificationByVersion[$Version] -Layout $Layout)
        }
    }

    Write-ToolDisplay
    Write-ToolHeading 'System SDKs:'
    if (-not $SystemSdks) {
        Write-ToolDisplay '  None'
    }
    else {
        foreach ($Sdk in $SystemSdks) {
            Write-ToolDisplay (Format-SdkAuditRow -Classification $ClassificationByVersion[$Sdk.Version] -Layout $Layout)
        }
    }
}

function Read-ManualVersion {
    $script:SdkVersion = Read-ToolInput '.NET SDK version'
    if ([string]::IsNullOrWhiteSpace($script:SdkVersion)) {
        throw 'An SDK version is required.'
    }

    Assert-ValidSdkVersion
}

# Select from Microsoft's release index when no exact SDK version was supplied.
function Select-InstallVersion {
    $script:BackToMain = $false
    # Consume previously validated remote discovery only when resuming this picker.
    $PickerReleaseIndex = $script:InstallResumeReleaseIndex
    $script:InstallResumeReleaseIndex = $null
    if ($null -eq $PickerReleaseIndex) {
        $PickerReleaseIndex = Get-ReleaseIndex
    }
    $AllChannels = @(
        $PickerReleaseIndex.'releases-index' |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace([string]$_.'channel-version') -and
                -not [string]::IsNullOrWhiteSpace([string]$_.'support-phase') -and
                -not [string]::IsNullOrWhiteSpace([string]$_.'releases.json')
            }
    )

    if (-not $AllChannels) {
        throw 'No selectable .NET channels were found in Microsoft release metadata.'
    }

    # Sort complete channel records, not detached display names or latest SDKs.
    # Keep malformed channel versions after numeric entries in encounter order.
    $EncounterIndex = 0
    $AllChannels = @(
        $AllChannels |
            ForEach-Object {
                $Channel = $_
                $Match = [regex]::Match([string]$Channel.'channel-version', '^([0-9]+)\.([0-9]+)$')
                $Major = [long]0
                $Minor = [long]0
                $IsNumeric = $Match.Success -and
                [long]::TryParse($Match.Groups[1].Value, [ref]$Major) -and
                [long]::TryParse($Match.Groups[2].Value, [ref]$Minor)
                [pscustomobject]@{
                    Entry   = $Channel
                    Numeric = [int]$IsNumeric
                    Major   = $Major
                    Minor   = $Minor
                    Index   = $EncounterIndex
                }
                $EncounterIndex++
            } |
            Sort-Object -Property @(
                @{ Expression = 'Numeric'; Descending = $true },
                @{ Expression = 'Major'; Descending = $true },
                @{ Expression = 'Minor'; Descending = $true },
                @{ Expression = 'Index'; Descending = $false }
            ) |
            ForEach-Object { $_.Entry }
    )

    $ShowArchived = $false
    $ResumeChannel = $script:InstallResumeChannel
    $ResumeMetadata = $script:InstallResumeChannelMetadata
    $script:InstallResumeChannel = $null
    $script:InstallResumeChannelMetadata = $null
    $ClearChannelScreen = $true

    while ($true) {
        $PickerChannelMetadata = $null
        if ($null -ne $ResumeChannel) {
            $SelectedChannel = $ResumeChannel
            $ResumeChannel = $null
            $PickerChannelMetadata = $ResumeMetadata
            $ResumeMetadata = $null
        }
        else {
            Write-ToolDisplay
            if ($ClearChannelScreen) {
                Clear-InteractiveScreen
                $ClearChannelScreen = $false
            }

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
                $script:InstallResultParent = '.NET channels'
                return $true
            }

            if ($Selection -match '^[Ee]$' -and $script:InteractiveSession) {
                $script:ExitRequested = $true
                Write-ToolExit
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
                $ClearChannelScreen = $true
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
        }
        $ChannelVersion = [string]$SelectedChannel.'channel-version'
        $LatestSdk = [string]$SelectedChannel.'latest-sdk'
        $ChannelMetadataUrl = [string]$SelectedChannel.'releases.json'

        if ($null -eq $PickerChannelMetadata) {
            try {
                $PickerChannelMetadata = Invoke-RestMethod -Uri $ChannelMetadataUrl
            }
            catch {
                throw "Unable to load release metadata for .NET $ChannelVersion."
            }
        }

        if ($null -eq $PickerChannelMetadata -or
            $null -eq $PickerChannelMetadata.releases) {
            throw "Invalid release metadata for .NET $ChannelVersion."
        }

        $DiscoveredSdkVersions = @(Get-ChannelSdkVersion $PickerChannelMetadata)
        if (-not $DiscoveredSdkVersions) {
            throw "No SDK versions were found for .NET $ChannelVersion."
        }

        $AllSdkVersions = @(Get-OrderedSdkVersion $DiscoveredSdkVersions)
        $FeaturedSdkVersions = @(Get-FeaturedSdkVersion `
                -OrderedSdkVersions $AllSdkVersions `
                -LatestSdk $LatestSdk)
        # The selected channel's latest SDK is authoritative only when it is in
        # that channel's discovered release set. Otherwise classify the newest
        # discovered SDK, without fabricating an authoritative latest marker.
        $CurrentSdk = if (-not [string]::IsNullOrWhiteSpace($LatestSdk) -and
            $AllSdkVersions -contains $LatestSdk) {
            $LatestSdk
        }
        else {
            $AllSdkVersions[0]
        }
        $ShowAllVersions = $CurrentSdk -match '-(?:preview|rc)\.[0-9]+(?:\.|$)'
        $SystemVersions = @(Get-SystemSdkVersion)
        $IsolatedVersions = @(Get-IsolatedSdkVersion)
        $ClearSdkScreen = $true

        while ($true) {
            Write-ToolDisplay
            if ($ClearSdkScreen) {
                Clear-InteractiveScreen
                $ClearSdkScreen = $false
            }
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
                    $Markers.Add('installed system-sdk')
                }
                if ($IsolatedVersions -contains $SdkVersion) {
                    $Markers.Add('installed isolated-sdk')
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
                $script:InstallResumeChannel = $null
                $ClearChannelScreen = $true
                break
            }

            if ($Selection -match '^[Ss]$' -and
                $FeaturedSdkVersions.Count -lt $AllSdkVersions.Count) {
                $ShowAllVersions = -not $ShowAllVersions
                $ClearSdkScreen = $true
                continue
            }

            if ($Selection -match '^[Mm]$') {
                Read-ManualVersion
                $script:InstallResumeChannel = $SelectedChannel
                $script:InstallResumeReleaseIndex = $PickerReleaseIndex
                $script:InstallResumeChannelMetadata = $PickerChannelMetadata
                $script:InstallResultParent = 'SDK selection'
                return $true
            }

            if ($Selection -match '^[Ee]$' -and $script:InteractiveSession) {
                $script:ExitRequested = $true
                Write-ToolExit
                return $false
            }

            if ($Selection -match '^[Qq]$' -and -not $script:InteractiveSession) {
                return $false
            }

            $Number = 0
            if ([int]::TryParse($Selection, [ref]$Number) -and
                $Number -ge 1 -and
                $Number -le $SdkVersions.Count) {
                $script:SdkVersion = $SdkVersions[$Number - 1]
                Assert-ValidSdkVersion
                $script:InstallResumeChannel = $SelectedChannel
                $script:InstallResumeReleaseIndex = $PickerReleaseIndex
                $script:InstallResumeChannelMetadata = $PickerChannelMetadata
                $script:InstallResultParent = 'SDK selection'
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
    $SdkVersions = @(Get-OrderedSdkVersion @(
            @(Get-RemoveSdkCandidateVersion) + @(Get-PendingRemovalVersion) |
                Sort-Object -Unique
        ))

    if (-not $SdkVersions) {
        Write-ToolInfo "No isolated SDKs are installed under $SdkRoot."
        return $false
    }

    while ($true) {
        Write-ToolHeading 'Select an isolated SDK to remove:'
        Write-ToolDisplay

        for ($Index = 0; $Index -lt $SdkVersions.Count; $Index++) {
            $Version = $SdkVersions[$Index]
            $Record = Join-Path (Join-Path $SdkRoot '.pending-removals') $Version
            if ($null -ne (Get-Item -LiteralPath $Record -Force -ErrorAction SilentlyContinue)) {
                Write-ToolDisplay ("  {0}. {1} (incomplete removal)" -f ($Index + 1), $Version)
            }
            elseif (-not (Test-Path -LiteralPath (Get-IsolatedDotNetPath -SdkVersion $Version) -PathType Leaf)) {
                Write-ToolDisplay ("  {0}. {1} (incomplete)" -f ($Index + 1), $Version)
            }
            else {
                Write-ToolDisplay ("  {0}. {1}" -f ($Index + 1), $Version)
            }
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
            Write-ToolExit
            return $false
        }

        if ($Selection -match '^[Qq]$' -and -not $script:InteractiveSession) {
            return $false
        }

        $Number = 0
        if ([int]::TryParse($Selection, [ref]$Number) -and
            $Number -ge 1 -and
            $Number -le $SdkVersions.Count) {
            $script:SdkVersion = $SdkVersions[$Number - 1]
            Assert-ValidSdkVersion
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

function Select-VerifyVersion {
    $SdkVersions = @(Get-OrderedSdkVersion @(Get-IsolatedSdkVersion))

    if (-not $SdkVersions) {
        Write-ToolInfo "No isolated SDKs are installed under $SdkRoot."
        return $false
    }

    while ($true) {
        Write-ToolHeading 'Select an isolated SDK to verify:'
        Write-ToolDisplay

        for ($Index = 0; $Index -lt $SdkVersions.Count; $Index++) {
            Write-ToolDisplay ("  {0}. {1}" -f ($Index + 1), $SdkVersions[$Index])
        }

        Write-ToolDisplay
        Write-ToolDisplay '  B. Back to Main'
        Write-ToolDisplay '  E. Exit'
        Write-ToolDisplay

        $Selection = Read-ToolInput 'Selection'

        if ($Selection -match '^[Bb]$') {
            $script:BackToMain = $true
            return $false
        }

        if ($Selection -match '^[Ee]$') {
            $script:ExitRequested = $true
            Write-ToolExit
            return $false
        }

        $Number = 0
        if ([int]::TryParse($Selection, [ref]$Number) -and
            $Number -ge 1 -and
            $Number -le $SdkVersions.Count) {
            $script:SdkVersion = $SdkVersions[$Number - 1]
            Assert-ValidSdkVersion
            return $true
        }

        $SelectionRange = Get-SelectionRange -Count $SdkVersions.Count
        Write-InvalidSelection -Selection $Selection -Choices "Choose $SelectionRange, B, or E."
        Write-ToolDisplay
    }
}

function Resolve-InstallVersion {
    if (-not [string]::IsNullOrWhiteSpace($script:SdkVersion)) {
        Assert-ValidSdkVersion
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
    if (-not [string]::IsNullOrWhiteSpace($script:SdkVersion)) {
        Assert-ValidSdkVersion
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
    $Channel = Get-SdkChannelFromVersion -Version $SdkVersion
    if ([string]::IsNullOrWhiteSpace($Channel)) {
        throw "Unable to determine the .NET release channel for SDK $SdkVersion."
    }

    return $Channel
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

    # Match the exact SDK entry and RID, not runtime records or URL substrings.
    # Legacy SDKs use dotnet-dev-<rid>.<version> URLs with an unversioned name.
    $extension = if ($Rid.StartsWith('win-')) { '.zip' } else { '.tar.gz' }
    $baseUrl = "https://builds.dotnet.microsoft.com/dotnet/Sdk/$SdkVersion/"
    $modernUrl = "$($baseUrl)dotnet-sdk-$SdkVersion-$Rid$extension"
    $validNames = @("dotnet-sdk-$Rid$extension", "dotnet-dev-$Rid$extension")
    $candidates = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

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
            if ([string]$sdk.version -cne $SdkVersion) {
                continue
            }

            foreach ($file in @($sdk.files)) {
                if ([string]$file.rid -cne $Rid) {
                    continue
                }

                $name = [string]$file.name
                $url = [string]$file.url
                if ($name -and $name -cnotin $validNames) {
                    continue
                }

                # Retain modern fixture compatibility when name is absent.
                # Legacy URLs must have an explicit Microsoft artifact name.
                $legacyUrl = if ($name) {
                    $stem = $name.Substring(0, $name.Length - $extension.Length)
                    "$baseUrl$stem.$SdkVersion$extension"
                }
                else {
                    ''
                }

                if ($url -cne $modernUrl -and $url -cne $legacyUrl) {
                    continue
                }
                if ($url -ceq $modernUrl -and $name -and
                    $name -cne "dotnet-sdk-$Rid$extension") {
                    continue
                }

                [void]$candidates.Add("$url|$([string]$file.hash)")
            }
        }
    }

    if ($candidates.Count -ne 1) {
        throw "Microsoft release metadata did not contain exactly one SDK archive for $SdkVersion and $Rid."
    }

    $parts = @($candidates)[0].Split('|', 2)
    $url = $parts[0]
    $hash = $parts[1]

    $algorithm = if ($hash -cmatch '^[0-9A-Fa-f]{128}$') {
        'SHA512'
    }
    elseif ($hash -cmatch '^[0-9A-Fa-f]{64}$') {
        if ($SdkVersion -notmatch '^1\.') {
            throw "Microsoft release metadata published SHA-256 for SDK $SdkVersion and $Rid; SHA-256 is supported only for historical .NET 1.x SDKs."
        }
        'SHA256'
    }
    else {
        throw "Microsoft release metadata contained an unsupported or malformed checksum for SDK $SdkVersion and $Rid."
    }

    return [pscustomobject]@{
        Url       = $url
        Hash      = $hash.ToLowerInvariant()
        Algorithm = $algorithm
    }
}

function Install-IsolatedSdk {
    $SelectedInteractively = [string]::IsNullOrWhiteSpace($script:SdkVersion)
    if (-not (Resolve-InstallVersion)) {
        return
    }

    if ($SelectedInteractively) {
        Write-ToolDisplay
        Clear-InteractiveScreen
    }

    $InstallDir = Join-Path $SdkRoot $SdkVersion
    $RecoveryRecord = Join-Path (Join-Path $SdkRoot '.pending-removals') $SdkVersion
    if ($null -ne (Get-Item -LiteralPath $RecoveryRecord -Force -ErrorAction SilentlyContinue)) {
        throw "SDK $SdkVersion has an incomplete removal; finish Remove before installing this version."
    }
    $IsolatedDotNet = Get-IsolatedDotNetPath -SdkVersion $SdkVersion

    Write-ToolLabelValue -Label 'Target SDK:' -Value $SdkVersion
    Write-ToolLabelValue -Label 'Isolated install directory:' -Value $InstallDir
    Write-ToolDisplay

    Write-ToolInfo 'Checking existing installations...'
    Write-ToolDisplay

    $SystemSdks = @(Get-SystemSdkInventory)
    $SystemSdk = $SystemSdks |
        Where-Object { $_.Version -eq $SdkVersion } |
        Select-Object -First 1

    # An existing version is owned by this isolated root only if the shared
    # local proof succeeds. Invalid targets are never replaced below.
    $IsolatedInstalled = $false
    if (Test-Path -LiteralPath $IsolatedDotNet -PathType Leaf) {
        $Validation = Get-LocalIsolatedSdkValidation -Version $SdkVersion -InstallDirectory $InstallDir -DotNetPath $IsolatedDotNet
        $IsolatedInstalled = -not [bool]$Validation.Failure
    }

    if ($IsolatedInstalled) {
        Write-ToolLabelValue -Label 'Isolated SDK:' -Value 'Already installed' -SuccessValue
        Write-ToolLabelValue -Label 'Location:' -Value $InstallDir
    }
    else {
        Write-ToolLabelValue -Label 'Isolated SDK:' -Value 'Not installed'
    }

    Write-ToolDisplay

    if ($SystemSdk) {
        Write-ToolLabelValue -Label 'System SDK:' -Value 'Already installed' -SuccessValue
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
    $MetadataPath = Join-Path $SdkRoot ('.release-metadata-{0}-{1}.json' -f $SdkVersion, [guid]::NewGuid().ToString('N'))
    $ArchivePath = Join-Path $SdkRoot ('.sdk-payload-{0}-{1}.zip' -f $SdkVersion, [guid]::NewGuid().ToString('N'))
    $StagingDir = Join-Path $SdkRoot ('.install-{0}-{1}' -f $SdkVersion, [guid]::NewGuid().ToString('N'))
    $StagedDotNet = Join-Path $StagingDir 'dotnet.exe'
    $PrimaryFailure = $null
    $CleanupFailure = $null

    try {
        Write-ToolInfo "Loading Microsoft release metadata for SDK $SdkVersion..."
        try {
            Invoke-WebRequest $MetadataUrl -OutFile $MetadataPath
            $Metadata = Get-Content -LiteralPath $MetadataPath -Raw | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw "Unable to load valid Microsoft release metadata for SDK ${SdkVersion}: $($_.Exception.Message)"
        }

        $Artifact = Resolve-SdkArtifact -Metadata $Metadata -SdkVersion $SdkVersion -Rid $Rid

        Write-ToolInfo "Downloading .NET SDK $SdkVersion payload..."
        try {
            Invoke-WebRequest $Artifact.Url -OutFile $ArchivePath
        }
        catch {
            throw "Unable to download the .NET SDK $SdkVersion payload: $($_.Exception.Message)"
        }

        try {
            $ActualHash = (Get-FileHash -LiteralPath $ArchivePath -Algorithm $Artifact.Algorithm).Hash.ToLowerInvariant()
        }
        catch {
            throw "Unable to verify the .NET SDK $SdkVersion payload: $($_.Exception.Message)"
        }

        if ($ActualHash -ne $Artifact.Hash) {
            throw "Integrity verification failed for the .NET SDK $SdkVersion payload."
        }

        New-Item -ItemType Directory -Path $StagingDir -WhatIf:$false -Confirm:$false | Out-Null
        Write-ToolInfo "Extracting verified .NET SDK $SdkVersion payload..."
        try {
            Expand-Archive -LiteralPath $ArchivePath -DestinationPath $StagingDir -Force
        }
        catch {
            throw "Unable to extract the verified .NET SDK $SdkVersion payload: $($_.Exception.Message)"
        }

        Write-ToolDisplay
        Write-ToolInfo 'Verifying the isolated SDK...'

        if (-not (Test-Path -LiteralPath $StagedDotNet -PathType Leaf)) {
            throw "The isolated dotnet executable was not found at $StagedDotNet"
        }

        # Validate the extracted root, not an SDK of the same version
        # discovered by the staged host elsewhere. Never promote on failure.
        $Validation = Get-LocalIsolatedSdkValidation -Version $SdkVersion -InstallDirectory $StagingDir -DotNetPath $StagedDotNet
        if ($Validation.Failure) {
            throw "Staged SDK verification failed at ${StagingDir}: $($Validation.Failure)"
        }

        if (Test-Path -LiteralPath $InstallDir) {
            throw "Isolated SDK destination already exists and cannot be replaced: $InstallDir"
        }

        try {
            Move-Item -LiteralPath $StagingDir -Destination $InstallDir -WhatIf:$false -Confirm:$false
            $StagingDir = $null
        }
        catch {
            throw "Unable to promote isolated SDK $SdkVersion into ${InstallDir}: $($_.Exception.Message)"
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
        throw "Isolated SDK $SdkVersion was installed, but transaction cleanup failed: $($CleanupFailure.Exception.Message)"
    }

    Write-ToolDisplay
    Write-ToolSuccess 'Isolated SDK installation completed successfully.'
    Write-ToolLabelValue -Label 'Location:' -Value $InstallDir
}

# Local SDK proof stays independent of online metadata and report presentation.
# Used by Verify and both correctness-significant Install boundaries.
function Get-LocalIsolatedSdkValidation {
    param(
        [string]$Version,
        [string]$InstallDirectory,
        [string]$DotNetPath
    )

    $Checks = [System.Collections.Generic.List[object]]::new()
    $Result = [ordered]@{ Checks = $Checks; Failure = '' }

    if (-not (Test-Path -LiteralPath $InstallDirectory -PathType Container)) {
        $Checks.Add([pscustomobject]@{ Label = 'Installation directory'; Status = 'FAIL'; Detail = $InstallDirectory })
        $Result.Failure = "Isolated SDK $Version is not installed under $SdkRoot."
        return [pscustomobject]$Result
    }
    $Checks.Add([pscustomobject]@{ Label = 'Installation directory'; Status = 'OK'; Detail = $InstallDirectory })

    if (-not (Test-Path -LiteralPath $DotNetPath -PathType Leaf)) {
        $Checks.Add([pscustomobject]@{ Label = '.NET host'; Status = 'FAIL'; Detail = $DotNetPath })
        $Result.Failure = "Isolated SDK $Version is incomplete: expected dotnet host was not found at $DotNetPath."
        return [pscustomobject]$Result
    }

    $WorkDirectory = $null
    $PreviousMultiLevel = [Environment]::GetEnvironmentVariable('DOTNET_MULTILEVEL_LOOKUP', 'Process')
    $PreviousDotNetRoot = [Environment]::GetEnvironmentVariable('DOTNET_ROOT', 'Process')
    $LocationPushed = $false
    try {
        # Avoid ambient global.json (including one under the isolated SDK root)
        # and disable old Windows multi-level SDK lookup for both host commands.
        $WorkDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-verify-{0}" -f [guid]::NewGuid())
        New-Item -ItemType Directory -Path $WorkDirectory -ErrorAction Stop | Out-Null
        Push-Location -LiteralPath $WorkDirectory
        $LocationPushed = $true
        [Environment]::SetEnvironmentVariable('DOTNET_MULTILEVEL_LOOKUP', '0', 'Process')
        [Environment]::SetEnvironmentVariable('DOTNET_ROOT', $InstallDirectory, 'Process')

        # Original 1.x and early 2.x hosts cannot enumerate SDKs.
        # Share exact --version and --info origin proof with Verify's check labels.
        if ($Version -match '^1\.' -or (Test-IsEarlyDotNet2Sdk -Version $Version)) {
            @{ sdk = @{ version = $Version } } |
                ConvertTo-Json -Depth 3 |
                Set-Content -LiteralPath (Join-Path $WorkDirectory 'global.json') -Encoding utf8 -ErrorAction Stop

            $VersionOutput = @()
            $ExitCode = 0
            try {
                $VersionOutput = @(& $DotNetPath --version 2>&1)
                $ExitCode = $LASTEXITCODE
            }
            catch {
                $Result.Failure = "Unable to launch isolated SDK $Version host at ${DotNetPath}: $($_.Exception.Message)"
            }
            if (-not $Result.Failure -and $ExitCode -ne 0) {
                $Result.Failure = "Isolated SDK $Version failed verification: --version exited with code $ExitCode."
            }
            if ($Result.Failure) {
                $Checks.Add([pscustomobject]@{ Label = '.NET host'; Status = 'FAIL'; Detail = $DotNetPath })
                return [pscustomobject]$Result
            }
            $Checks.Add([pscustomobject]@{ Label = '.NET host'; Status = 'OK'; Detail = $DotNetPath })

            $VersionLines = @($VersionOutput | ForEach-Object { ([string]$_).Trim() } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if ($VersionLines.Count -ne 1 -or $VersionLines[0] -cne $Version) {
                $Result.Failure = "Isolated SDK $Version failed verification: legacy --version did not resolve the exact requested SDK."
                $Checks.Add([pscustomobject]@{ Label = 'SDK resolution'; Status = 'FAIL'; Detail = $Result.Failure })
                return [pscustomobject]$Result
            }
            $Checks.Add([pscustomobject]@{ Label = 'SDK resolution'; Status = 'OK'; Detail = $Version })

            $ExpectedBase = Join-Path (Join-Path $InstallDirectory 'sdk') $Version
            if (-not (Test-Path -LiteralPath $ExpectedBase -PathType Container)) {
                $Result.Failure = "Isolated SDK $Version failed verification: isolated SDK Base Path is missing at $ExpectedBase."
                $Checks.Add([pscustomobject]@{ Label = 'SDK origin'; Status = 'FAIL'; Detail = $Result.Failure })
                return [pscustomobject]$Result
            }
            try {
                $InfoOutput = @(& $DotNetPath --info 2>&1)
                $InfoExitCode = $LASTEXITCODE
                if ($InfoExitCode -ne 0) {
                    throw "legacy --info exited with code $InfoExitCode."
                }
                $BasePaths = @($InfoOutput | ForEach-Object {
                        if ([string]$_ -match '^\s*Base Path:\s*(.*?)\s*$') { $Matches[1].Trim() }
                    })
                if ($BasePaths.Count -ne 1 -or [string]::IsNullOrWhiteSpace($BasePaths[0])) {
                    throw 'legacy --info did not report exactly one SDK Base Path.'
                }
                if (-not [System.IO.Path]::IsPathFullyQualified($BasePaths[0]) -or
                    -not (Test-Path -LiteralPath $BasePaths[0] -PathType Container)) {
                    throw 'legacy --info reported an invalid or missing SDK Base Path.'
                }
                $ActualBase = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $BasePaths[0] -ErrorAction Stop).Path).TrimEnd('\', '/')
                $ExpectedCanonical = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ExpectedBase -ErrorAction Stop).Path).TrimEnd('\', '/')
                $PathComparison = if ($IsWindows) {
                    [System.StringComparison]::OrdinalIgnoreCase
                }
                else {
                    [System.StringComparison]::Ordinal
                }
                $CanonicalInstall = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $InstallDirectory -ErrorAction Stop).Path).TrimEnd('\', '/')
                $ContainedBase = [System.IO.Path]::GetFullPath((Join-Path (Join-Path $CanonicalInstall 'sdk') $Version)).TrimEnd('\', '/')
                # Reject an SDK subdirectory linked outside the isolated tree.
                if (-not [string]::Equals($ExpectedCanonical, $ContainedBase, $PathComparison) -or
                    -not [string]::Equals($ActualBase, $ExpectedCanonical, $PathComparison)) {
                    throw 'legacy SDK Base Path does not match the isolated directory.'
                }
                $Checks.Add([pscustomobject]@{ Label = 'SDK origin'; Status = 'OK'; Detail = $ExpectedCanonical })
            }
            catch {
                $Result.Failure = "Isolated SDK $Version failed verification: $($_.Exception.Message)"
                $Checks.Add([pscustomobject]@{ Label = 'SDK origin'; Status = 'FAIL'; Detail = $Result.Failure })
            }
            return [pscustomobject]$Result
        }

        $Inventory = @()
        $ExitCode = 0
        try {
            $Inventory = @(& $DotNetPath --list-sdks)
            $ExitCode = $LASTEXITCODE
        }
        catch {
            $Result.Failure = "Unable to launch isolated SDK $Version host at ${DotNetPath}: $($_.Exception.Message)"
        }

        if (-not $Result.Failure -and $ExitCode -ne 0) {
            $Result.Failure = "Unable to verify isolated SDK $Version with exit code $ExitCode."
        }

        if ($Result.Failure) {
            $Checks.Add([pscustomobject]@{ Label = '.NET host'; Status = 'FAIL'; Detail = $DotNetPath })
        }
        else {
            $Checks.Add([pscustomobject]@{ Label = '.NET host'; Status = 'OK'; Detail = $DotNetPath })
            $ExpectedOrigin = [System.IO.Path]::GetFullPath((Join-Path $InstallDirectory 'sdk')).TrimEnd(
                [System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
            $PathComparison = if ($IsWindows) {
                [System.StringComparison]::OrdinalIgnoreCase
            }
            else {
                [System.StringComparison]::Ordinal
            }
            $ExpectedOriginExists = Test-Path -LiteralPath $ExpectedOrigin -PathType Container
            $FoundVersion = $false
            $FoundOrigin = $false
            foreach ($Line in $Inventory) {
                $InventoryMatch = [regex]::Match([string]$Line, '^(?<version>\S+)\s+\[(?<path>.+)\]\s*$')
                if (-not $InventoryMatch.Success -or $InventoryMatch.Groups['version'].Value -cne $Version) {
                    continue
                }
                $FoundVersion = $true
                try {
                    $ReportedOrigin = [System.IO.Path]::GetFullPath($InventoryMatch.Groups['path'].Value).TrimEnd(
                        [System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
                    if ($ExpectedOriginExists -and [string]::Equals($ExpectedOrigin, $ReportedOrigin, $PathComparison)) {
                        $FoundOrigin = $true
                        break
                    }
                }
                catch {
                    # A malformed reported origin cannot satisfy the installed SDK check.
                    continue
                }
            }

            if (-not $FoundVersion) {
                $Checks.Add([pscustomobject]@{ Label = 'SDK inventory'; Status = 'FAIL'; Detail = "$Version missing" })
                $Result.Failure = "Isolated SDK $Version failed verification: the host did not report SDK $Version."
            }
            elseif (-not $FoundOrigin) {
                $Checks.Add([pscustomobject]@{ Label = 'SDK inventory'; Status = 'FAIL'; Detail = 'unexpected SDK root' })
                $Result.Failure = "Isolated SDK $Version failed verification: SDK $Version was not reported from $ExpectedOrigin."
            }
            else {
                $Checks.Add([pscustomobject]@{ Label = 'SDK inventory'; Status = 'OK'; Detail = "$Version from $ExpectedOrigin" })
                try {
                    $ResolvedVersion = @(& $DotNetPath --version)
                    $ExitCode = $LASTEXITCODE
                    if ($ExitCode -ne 0) {
                        $Result.Failure = "Isolated SDK $Version failed verification: --version exited with code $ExitCode."
                    }
                    elseif (($ResolvedVersion -join '').Trim() -cne $Version) {
                        $Result.Failure = "Isolated SDK $Version failed verification: --version resolved $($ResolvedVersion -join '') instead of $Version."
                    }
                }
                catch {
                    $Result.Failure = "Unable to launch isolated SDK $Version host at ${DotNetPath}: $($_.Exception.Message)"
                }

                if ($Result.Failure) {
                    $Checks.Add([pscustomobject]@{ Label = 'SDK resolution'; Status = 'FAIL'; Detail = $Result.Failure })
                }
                else {
                    $Checks.Add([pscustomobject]@{ Label = 'SDK resolution'; Status = 'OK'; Detail = $Version })
                }
            }
        }
    }
    catch {
        if (-not $Result.Failure) {
            $Result.Failure = "Unable to perform isolated SDK $Version verification: $($_.Exception.Message)"
            $Checks.Add([pscustomobject]@{ Label = '.NET host'; Status = 'FAIL'; Detail = $DotNetPath })
        }
    }
    finally {
        if ($LocationPushed) {
            Pop-Location
        }
        [Environment]::SetEnvironmentVariable('DOTNET_MULTILEVEL_LOOKUP', $PreviousMultiLevel, 'Process')
        [Environment]::SetEnvironmentVariable('DOTNET_ROOT', $PreviousDotNetRoot, 'Process')
        if ($WorkDirectory -and (Test-Path -LiteralPath $WorkDirectory)) {
            Remove-Item -LiteralPath $WorkDirectory -Force -Recurse -ErrorAction SilentlyContinue
        }
    }
    return [pscustomobject]$Result
}

function Get-VerifyAuditClassification {
    param([string]$Version)

    $Index = Get-ReleaseIndex
    $ChannelVersion = Get-SdkChannelFromVersion -Version $Version
    $Entry = @($Index.'releases-index' | Where-Object { $_.'channel-version' -eq $ChannelVersion } | Select-Object -First 1)
    if (-not $Entry) {
        return [pscustomobject]@{
            Version          = $Version
            ReleaseType      = ''
            ServicingStatus  = ''
            StatusToken      = 'Unknown channel'
            ReleaseDate      = ''
            GoLiveDate       = ''
            EndOfSupportDate = ''
        }
    }

    $ChannelEntry = $Entry[0]
    $LatestSdk = [string]$ChannelEntry.'latest-sdk'
    $MetadataUrl = [string]$ChannelEntry.'releases.json'
    if ([string]::IsNullOrWhiteSpace($LatestSdk) -or
        [string]::IsNullOrWhiteSpace($MetadataUrl) -or
        [string]::IsNullOrWhiteSpace([string]$ChannelEntry.'support-phase')) {
        throw "Invalid .NET release metadata for .NET $ChannelVersion."
    }
    $Metadata = Get-AuditChannelRecord -ChannelVersion $ChannelVersion -MetadataUrl $MetadataUrl -Cache @{}
    if (@(Get-ChannelSdkVersion $Metadata) -notcontains $LatestSdk) {
        throw "Invalid release metadata for .NET $ChannelVersion."
    }
    return Get-SdkAuditClassification -Version $Version -ChannelEntry $ChannelEntry -ChannelMetadata $Metadata -GoLiveCache @{}
}

# Optional local component diagnostics; only runtimes from this isolated root are shown.
function Get-IsolatedSdkComponent {
    param(
        [string]$InstallDirectory,
        [string]$DotNetPath,
        [string]$Version = ''
    )
    $Result = [ordered]@{ HostVersion = ''; Architecture = ''; Rid = ''; Runtimes = @() }
    $PreviousMulti = [Environment]::GetEnvironmentVariable('DOTNET_MULTILEVEL_LOOKUP', 'Process')
    $PreviousRoot = [Environment]::GetEnvironmentVariable('DOTNET_ROOT', 'Process')
    $WorkDirectory = $null
    $LocationPushed = $false
    try {
        $WorkDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-components-{0}" -f [guid]::NewGuid())
        New-Item -ItemType Directory -Path $WorkDirectory -ErrorAction Stop | Out-Null
        Push-Location -LiteralPath $WorkDirectory
        $LocationPushed = $true
        [Environment]::SetEnvironmentVariable('DOTNET_MULTILEVEL_LOOKUP', '0', 'Process')
        [Environment]::SetEnvironmentVariable('DOTNET_ROOT', $InstallDirectory, 'Process')

        $InfoLines = @(& $DotNetPath --info 2>$null)
        if ($LASTEXITCODE -eq 0) {
            $Section = ''
            foreach ($Line in $InfoLines) {
                $Text = [string]$Line
                if ($Text -match '^\s*Host(?:\s+\(useful for support\))?:\s*$') {
                    $Section = 'Host'
                    continue
                }
                if ($Text -match '^\s*Runtime Environment:\s*$') {
                    $Section = 'Runtime Environment'
                    continue
                }
                if ($Text -match '^\S[^:]*:\s*$') {
                    $Section = ''
                    continue
                }
                if ($Section -eq 'Host' -and $Text -match '^\s*Version:\s*(\S+)') {
                    $Result.HostVersion = $Matches[1]
                }
                if ($Section -eq 'Host' -and $Text -match '^\s*Architecture:\s*(\S+)') {
                    $Result.Architecture = $Matches[1]
                }
                if ($Section -eq 'Runtime Environment' -and $Text -match '^\s*RID:\s*(\S+)') {
                    $Result.Rid = $Matches[1]
                }
            }
        }

        # Legacy hosts expose architecture in the RID but not as a separate field.
        if ([string]::IsNullOrWhiteSpace($Result.Architecture) -and
            $Result.Rid -match '-(x64|x86|arm64|arm)$') {
            $Result.Architecture = $Matches[1]
        }

        # Original 1.x and early 2.x hosts do not support --list-runtimes.
        # This diagnostic is optional; unsupported commands must not leak a
        # native failure status into an otherwise successful Verify invocation.
        if ($Version -match '^1\.' -or (Test-IsEarlyDotNet2Sdk -Version $Version)) {
            return [pscustomobject]$Result
        }

        $RuntimeLines = @(& $DotNetPath --list-runtimes 2>$null)
        if ($LASTEXITCODE -eq 0) {
            $Items = [System.Collections.Generic.List[object]]::new()
            $Comparison = if ($IsWindows) {
                [System.StringComparison]::OrdinalIgnoreCase
            }
            else {
                [System.StringComparison]::Ordinal
            }
            foreach ($Line in $RuntimeLines) {
                $Match = [regex]::Match([string]$Line, '^(?<name>\S+)\s+(?<version>\S+)\s+\[(?<path>.+)\]\s*$')
                if (-not $Match.Success) {
                    continue
                }
                try {
                    $Expected = [System.IO.Path]::GetFullPath((Join-Path (Join-Path $InstallDirectory 'shared') $Match.Groups['name'].Value))
                    $Reported = [System.IO.Path]::GetFullPath($Match.Groups['path'].Value)
                    if ([string]::Equals($Expected, $Reported, $Comparison) -and
                        (Test-Path -LiteralPath $Expected -PathType Container)) {
                        $Items.Add([pscustomobject]@{
                                Name    = $Match.Groups['name'].Value
                                Version = $Match.Groups['version'].Value
                            })
                    }
                }
                catch {
                    # Ignore malformed/unrelated runtime roots; these are optional data.
                    continue
                }
            }
            $Result.Runtimes = @($Items | Sort-Object Name, Version)
        }
    }
    catch {
        # Older/incomplete hosts may not provide optional diagnostics.
        return [pscustomobject]$Result
    }
    finally {
        if ($LocationPushed) {
            Pop-Location
        }
        [Environment]::SetEnvironmentVariable('DOTNET_MULTILEVEL_LOOKUP', $PreviousMulti, 'Process')
        [Environment]::SetEnvironmentVariable('DOTNET_ROOT', $PreviousRoot, 'Process')
        if ($WorkDirectory -and (Test-Path -LiteralPath $WorkDirectory)) {
            Remove-Item -LiteralPath $WorkDirectory -Force -Recurse -ErrorAction SilentlyContinue
        }
    }
    return [pscustomobject]$Result
}

function Test-IsolatedSdk {
    if ([string]::IsNullOrWhiteSpace($script:SdkVersion)) {
        throw '-SdkVersion is required with -Action Verify.'
    }
    Assert-ValidSdkVersion

    $InstallDir = Join-Path $SdkRoot $SdkVersion
    $IsolatedDotNet = Get-IsolatedDotNetPath -SdkVersion $SdkVersion
    $Validation = Get-LocalIsolatedSdkValidation -Version $SdkVersion -InstallDirectory $InstallDir -DotNetPath $IsolatedDotNet

    Write-ToolHeading 'Verify isolated .NET SDK'
    Write-ToolDisplay
    $Classification = $null
    try {
        $Classification = Get-VerifyAuditClassification -Version $SdkVersion
    }
    catch {
        # Microsoft lifecycle information is optional; local checks remain authoritative.
        $Classification = $null
    }
    Write-ToolDisplay
    Write-ToolHeading 'SDK information:'
    Write-ToolDisplay ('  {0,-19} {1}' -f 'SDK version', $SdkVersion)
    Write-ToolDisplay ('  {0,-19} {1}' -f '.NET channel', (Get-SdkChannelFromVersion -Version $SdkVersion))
    try {
        if ($null -eq $Classification) {
            throw 'Microsoft metadata unavailable.'
        }
        if ($Classification.ReleaseType) {
            Write-ToolDisplay ('  {0,-19} {1}' -f 'Support type', $Classification.ReleaseType)
        }
        Write-ToolDisplay ('  {0,-19} {1}' -f 'Status', (Format-AuditStatusToken -StatusToken $Classification.StatusToken))
        if ($Classification.ReleaseDate) {
            Write-ToolDisplay ('  {0,-19} {1}' -f 'SDK release date', $Classification.ReleaseDate)
        }
        if ($Classification.GoLiveDate) {
            Write-ToolDisplay ('  {0,-19} {1}' -f 'Go Live date', $Classification.GoLiveDate)
        }
        if ($Classification.EndOfSupportDate) {
            Write-ToolDisplay ('  {0,-19} {1}' -f 'Channel EOS date', $Classification.EndOfSupportDate)
        }
        if ($Classification.ServicingStatus) {
            $UpdateMatch = [regex]::Match(
                [string]$Classification.ServicingStatus,
                '^(?:Security update available|Update available) -> (?<version>\S+)$')
            if ($UpdateMatch.Success) {
                Write-ToolDisplay ('  {0,-19} {1}' -f 'Update available', $UpdateMatch.Groups['version'].Value)
            }
            else {
                Write-ToolDisplay ('  {0,-19} {1}' -f 'Servicing status', $Classification.ServicingStatus)
            }
        }
    }
    catch {
        Write-ToolDisplay '  Release/lifecycle   Unavailable (Microsoft metadata could not be loaded).'
    }
    Write-ToolDisplay
    Write-ToolHeading 'Installed components:'
    $Components = if (-not $Validation.Failure) {
        Get-IsolatedSdkComponent -InstallDirectory $InstallDir -DotNetPath $IsolatedDotNet -Version $SdkVersion
    }
    else {
        $null
    }
    foreach ($Field in @(
            @{ Label = 'Host version'; Value = $Components.HostVersion },
            @{ Label = 'Architecture'; Value = $Components.Architecture },
            @{ Label = 'Runtime identifier'; Value = $Components.Rid }
        )) {
        $Value = if ($Field.Value) { $Field.Value } else { 'Unavailable' }
        Write-ToolDisplay ('  {0,-19} {1}' -f $Field.Label, $Value)
    }
    Write-ToolDisplay
    Write-ToolDisplay '  .NET runtimes:'
    if ($Components -and @($Components.Runtimes).Count -gt 0) {
        $Width = ($Components.Runtimes | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum
        foreach ($Runtime in $Components.Runtimes) {
            $Name = ([string]$Runtime.Name).PadRight($Width)
            Write-ToolDisplay ("    $Name  $($Runtime.Version)")
        }
    }
    else {
        Write-ToolDisplay '    Unavailable'
    }
    Write-ToolDisplay
    Write-ToolHeading 'Verification:'
    foreach ($Check in $Validation.Checks) {
        $Status = [string]$Check.Status
        $RenderedStatus = if ($Status -eq 'OK') {
            Format-ToolMessage -Kind Success -Message 'OK'
        }
        else {
            $Status
        }
        $Detail = if ($Status -eq 'OK') {
            switch ($Check.Label) {
                '.NET host' { 'Host executable found and launched' }
                'SDK inventory' { 'Exact SDK found in isolated installation' }
                'SDK origin' { 'Exact SDK Base Path in isolated installation' }
                'SDK resolution' { 'Correct SDK selected' }
                default { $Check.Detail }
            }
        }
        else {
            $Check.Detail
        }
        Write-ToolDisplay ('  {0,-23} {1}  {2}' -f $Check.Label, $RenderedStatus, $Detail)
    }
    Write-ToolDisplay
    if ($Validation.Failure) {
        throw $Validation.Failure
    }
    Write-ToolSuccess "Isolated SDK $SdkVersion verified successfully."
}

# Public unified build-server shutdown arrived with SDK 2.1.300. Keep the
# compatibility window limited to documented stable servicing generations:
# 1.0.x/1.1.x, 2.0.x, SDK 2.1.1-4, 2.1.100-105, and 2.1.200-202.
# A matching version is only a candidate: actual capability probes, expected
# exact SDK payload, and targeted Roslyn shutdown remain mandatory.
function Test-PreUnifiedSdkVersion {
    param([string]$Version)
    return $Version -cmatch '^(?:1\.0\.[0-4]|1\.1\.(?:[0-9]|1[0-4])|2\.0\.[0-3]|2\.1\.(?:[0-4]|10[0-5]|20[0-2]))$'
}

function Test-PreUnifiedRoslynSdkVersion {
    param([string]$Version)
    return $Version -cmatch '^2\.1\.(?:10[0-5]|20[0-2])$'
}

function Invoke-IsolatedSdkBuildServerShutdown {
    param(
        [string]$DotNetPath,
        [string]$SdkVersion,
        [switch]$AllowUnsupportedShutdown
    )
    # Retained for backwards-compatible Remove callers. Verified legacy
    # fallback no longer requires a second authorization switch.
    $null = $AllowUnsupportedShutdown

    # Historic SDKs must not resolve ambient global.json or System SDKs.
    # A pre-unified servicing generation only enters the compatibility branch
    # after precise missing-command probes. Actual shutdown failure blocks.
    $WorkDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-shutdown-{0}" -f [guid]::NewGuid())
    $IsolatedRoot = Split-Path -Path $DotNetPath -Parent
    $EnvironmentOverrides = @{
        DOTNET_ROOT                        = $IsolatedRoot
        DOTNET_MULTILEVEL_LOOKUP           = '0'
        DOTNET_CLI_HOME                    = $WorkDirectory
        DOTNET_SKIP_FIRST_TIME_EXPERIENCE  = '1'
        DOTNET_CLI_TELEMETRY_OPTOUT        = '1'
        DOTNET_NOLOGO                      = 'true'
        DOTNET_GENERATE_ASPNET_CERTIFICATE = 'false'
        DOTNET_ADD_GLOBAL_TOOLS_TO_PATH    = 'false'
    }
    $PreviousEnvironment = @{}
    $LocationPushed = $false
    $ExitCode = $null
    $CleanupFailure = $null

    try {
        New-Item -ItemType Directory -Path $WorkDirectory -ErrorAction Stop | Out-Null
        Push-Location -LiteralPath $WorkDirectory
        $LocationPushed = $true

        foreach ($Name in $EnvironmentOverrides.Keys) {
            $PreviousEnvironment[$Name] = [Environment]::GetEnvironmentVariable($Name, 'Process')
            [Environment]::SetEnvironmentVariable($Name, $EnvironmentOverrides[$Name], 'Process')
        }

        if (Test-PreUnifiedSdkVersion -Version $SdkVersion) {
            $SdkPayload = Join-Path (Join-Path $IsolatedRoot 'sdk') $SdkVersion
            if (-not (Test-Path -LiteralPath $SdkPayload -PathType Container)) {
                throw "Unable to classify legacy shutdown for SDK $($SdkVersion): SDK payload missing."
            }

            $SupportedSpelling = $null
            foreach ($Spelling in @('build-server', 'buildserver')) {
                $ProbeOutput = @(& $DotNetPath $Spelling '--help' 2>&1)
                $ProbeStatus = $LASTEXITCODE
                if ($ProbeStatus -eq 0) {
                    $SupportedSpelling = $Spelling
                    break
                }
                $ExpectedMissing = 'No executable found matching command "' + "dotnet-$Spelling" + '"'
                if ($ProbeStatus -ne 1 -or
                    (($ProbeOutput -join [Environment]::NewLine).Trim() -ne $ExpectedMissing)) {
                    throw "Unable to classify legacy shutdown for SDK $($SdkVersion): $Spelling probe failed unexpectedly."
                }
            }

            if ($SupportedSpelling) {
                $null = & $DotNetPath $SupportedSpelling shutdown
                $ExitCode = $LASTEXITCODE
            }
            elseif (Test-PreUnifiedRoslynSdkVersion -Version $SdkVersion) {
                $Compiler = Join-Path $SdkPayload 'Roslyn/bincore/VBCSCompiler.dll'
                if (-not (Test-Path -LiteralPath $Compiler -PathType Leaf)) {
                    throw "Legacy compiler shutdown unavailable for SDK $SdkVersion; removal stopped."
                }
                Write-ToolWarning "Legacy SDK $SdkVersion lacks unified shutdown; using SDK-local Roslyn shutdown. Other build processes may remain and files in use may prevent complete removal."
                $null = & $DotNetPath exec $Compiler -shutdown
                $ExitCode = $LASTEXITCODE
            }
            else {
                $CompilerServers = @(Get-ChildItem -LiteralPath $SdkPayload -File -Recurse -Filter 'VBCSCompiler*' -ErrorAction Stop)
                if ($CompilerServers.Count -gt 0) {
                    throw "Unrecognized compiler-server payload in SDK $SdkVersion; removal stopped."
                }
                Write-ToolWarning "Legacy SDK $SdkVersion has no supported shutdown command. Other build processes may remain and files in use may prevent complete removal."
                $ExitCode = 0
            }
        }
        else {
            $null = & $DotNetPath build-server shutdown
            $ExitCode = $LASTEXITCODE
        }
    }
    finally {
        foreach ($Name in $PreviousEnvironment.Keys) {
            [Environment]::SetEnvironmentVariable($Name, $PreviousEnvironment[$Name], 'Process')
        }
        if ($LocationPushed) {
            Pop-Location
        }
        if (Test-Path -LiteralPath $WorkDirectory) {
            try {
                Remove-Item -LiteralPath $WorkDirectory -Recurse -Force -ErrorAction Stop
            }
            catch {
                $CleanupFailure = $_
            }
        }
    }

    if ($ExitCode -ne 0) {
        throw "Build-server shutdown failed for SDK $SdkVersion with exit code $ExitCode."
    }
    if ($CleanupFailure) {
        throw "Unable to clean temporary shutdown state for SDK $SdkVersion; removal stopped. $($CleanupFailure.Exception.Message)"
    }
}


function Get-PendingRemovalVersion {
    $Root = Join-Path $SdkRoot '.pending-removals'
    if (-not (Test-Path -LiteralPath $Root)) { return @() }
    $Info = Get-Item -LiteralPath $Root -Force -ErrorAction Stop
    if (-not $Info.PSIsContainer -or ($Info.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Unsafe incomplete-removal recovery directory: $Root"
    }
    return @(
        Get-ChildItem -LiteralPath $Root -Force -ErrorAction Stop | ForEach-Object {
            if ($_.PSIsContainer -or ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw "Invalid incomplete-removal recovery record: $($_.FullName)"
            }
            $_.Name
        }
    )
}

function Get-PendingRemoval {
    param([string]$Version)
    $Root = Join-Path $SdkRoot '.pending-removals'
    $Record = Join-Path $Root $Version
    $RootInfo = Get-Item -LiteralPath $Root -Force -ErrorAction Stop
    $Info = Get-Item -LiteralPath $Record -Force -ErrorAction Stop
    if (-not $RootInfo.PSIsContainer -or ($RootInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        $Info.PSIsContainer -or ($Info.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Unsafe incomplete-removal recovery record for SDK $Version."
    }
    $Token = ([IO.File]::ReadAllText($Record)).Trim()
    if ($Token -cnotmatch '^[0-9a-f]{32}$') {
        throw "Invalid incomplete-removal recovery token for SDK $Version."
    }
    $Stage = Join-Path $SdkRoot ".removing-$Version-$Token"
    $Proof = Join-Path $Stage ".isolated-sdk-remove-$Token"
    if ($null -ne (Get-Item -LiteralPath (Join-Path $SdkRoot $Version) -Force -ErrorAction SilentlyContinue)) {
        throw "SDK $Version was replaced during incomplete removal; manual recovery is required."
    }
    $StageInfo = Get-Item -LiteralPath $Stage -Force -ErrorAction SilentlyContinue
    if ($null -ne $StageInfo) {
        if (-not $StageInfo.PSIsContainer -or ($StageInfo.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Unsafe incomplete-removal target for SDK $Version."
        }
        $ProofInfo = Get-Item -LiteralPath $Proof -Force -ErrorAction SilentlyContinue
        if ($null -eq $ProofInfo) {
            if (@(Get-ChildItem -LiteralPath $Stage -Force -ErrorAction Stop).Count -gt 0) {
                throw "Removal proof missing while SDK $Version still has files; manual recovery is required."
            }
        }
        elseif ($ProofInfo.PSIsContainer -or ($ProofInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
            (([IO.File]::ReadAllText($Proof)).Trim() -cne "$($Version):$Token")) {
            throw "Removal proof mismatch for SDK $Version; manual recovery is required."
        }
    }
    return [pscustomobject]@{ Record = $Record; Stage = $Stage; Proof = $Proof }
}

# Diagnostics are advisory and read-only. Windows can report access denied
# for open handles as well as filesystem permissions; neither an ACL read
# nor an executable-path match conclusively identifies the blocking process.
function Get-SdkRemovalFailureDiagnostic {
    param(
        [string]$InstallDirectory,
        [System.Exception]$Failure
    )

    $Lines = [System.Collections.Generic.List[string]]::new()
    $NativeError = $Failure.GetBaseException()
    $Win32Code = $NativeError.HResult -band 0xFFFF

    if ($Win32Code -in @(32, 33)) {
        $Lines.Add('Windows reported a sharing or lock violation; a file may be in use.')
    }
    elseif ($Win32Code -eq 5) {
        $Lines.Add('Windows reported access denied. This alone does not distinguish a file lock from insufficient permissions.')
    }
    else {
        $Lines.Add('The filesystem operation failed; its error does not identify a single cause.')
    }
    $Lines.Add('Possible causes: open file handles, insufficient rename/delete permissions, security software, or filesystem restrictions.')

    if ($IsWindows) {
        try {
            $SdkPath = [IO.Path]::GetFullPath($InstallDirectory).TrimEnd([char]'\', [char]'/') + [IO.Path]::DirectorySeparatorChar
            $MatchingProcesses = @(
                Get-CimInstance -ClassName Win32_Process -ErrorAction Stop |
                    Where-Object {
                        $Executable = [string]$_.ExecutablePath
                        $Command = [string]$_.CommandLine
                        ($Executable.StartsWith($SdkPath, [StringComparison]::OrdinalIgnoreCase)) -or
                        ($Command.IndexOf($InstallDirectory, [StringComparison]::OrdinalIgnoreCase) -ge 0)
                    } |
                    Select-Object -First 5 ProcessId, Name
            )

            if ($MatchingProcesses.Count -gt 0) {
                $MatchingDescriptions = @($MatchingProcesses | ForEach-Object { "$($_.Name) (PID $($_.ProcessId))" })
                $Lines.Add("Processes referencing this SDK (not confirmed file-lock holders): $($MatchingDescriptions -join ', ')")
            }
            else {
                $Lines.Add('No running processes referencing the SDK were found; this does not rule out open file handles.')
            }
        }
        catch {
            $Lines.Add("Process inspection was unavailable: $($_.Exception.Message)")
        }

        try {
            $null = Get-Acl -LiteralPath $InstallDirectory -ErrorAction Stop
            $Lines.Add('Directory ACL is readable, but effective rename/delete permission has not been established.')
        }
        catch {
            $Lines.Add("Directory ACL could not be inspected: $($_.Exception.Message)")
        }

        $SdkSearchName = Split-Path -Path $InstallDirectory -Leaf
        $Lines.Add("To find a file-lock holder: in Resource Monitor (resmon.exe) > CPU > Associated Handles, search for '$SdkSearchName', 'dotnet-sdks', or a known filename. Search Handles matches parts of full paths; compare the process name and PID.")
        $Lines.Add("To inspect filesystem permissions: icacls `"$InstallDirectory`"")
    }

    return ($Lines -join "`n")
}

function Invoke-ConfirmedSdkRemovalStaging {
    param([string]$Version)
    $InstallDir = Join-Path $SdkRoot $Version
    $Root = Join-Path $SdkRoot '.pending-removals'
    $Record = Join-Path $Root $Version
    $Dir = Get-Item -LiteralPath $InstallDir -Force -ErrorAction Stop
    if (-not $Dir.PSIsContainer -or ($Dir.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Unsafe SDK removal target: $InstallDir"
    }
    if ($null -ne (Get-Item -LiteralPath $Record -Force -ErrorAction SilentlyContinue)) {
        throw "SDK $Version has an existing incomplete-removal record; removal stopped."
    }
    if (-not (Test-Path -LiteralPath $Root)) {
        New-Item -ItemType Directory -Path $Root -ErrorAction Stop | Out-Null
    }
    $RootInfo = Get-Item -LiteralPath $Root -Force -ErrorAction Stop
    if (-not $RootInfo.PSIsContainer -or ($RootInfo.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Unsafe removal recovery directory: $Root"
    }
    $Token = [guid]::NewGuid().ToString('N')
    $Stage = Join-Path $SdkRoot ".removing-$Version-$Token"
    $Proof = Join-Path $InstallDir ".isolated-sdk-remove-$Token"
    if ($null -ne (Get-Item -LiteralPath $Stage -Force -ErrorAction SilentlyContinue) -or
        $null -ne (Get-Item -LiteralPath $Proof -Force -ErrorAction SilentlyContinue)) {
        throw "Removal recovery identity conflict; removal stopped."
    }
    $Stream = [IO.File]::Open($Record, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $Bytes = [Text.Encoding]::UTF8.GetBytes($Token)
        $Stream.Write($Bytes, 0, $Bytes.Length)
    }
    finally { $Stream.Dispose() }
    $StagePhase = 'preparation'
    try {
        $ProofStream = [IO.File]::Open($Proof, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            $Bytes = [Text.Encoding]::UTF8.GetBytes("$($Version):$Token")
            $ProofStream.Write($Bytes, 0, $Bytes.Length)
        }
        finally { $ProofStream.Dispose() }
        # PowerShell Move-Item can move individual children before failing on a
        # locked Windows file, leaving a split SDK. Both paths are siblings on
        # the same volume; use an atomic directory rename instead.
        $StagePhase = 'rename'
        [System.IO.Directory]::Move($InstallDir, $Stage)
    }
    catch {
        # Preserve the exception text: an access error may have causes other
        # than a file lock, and the native message is useful for diagnosis.
        $OriginalError = $_.Exception.Message
        $OriginalExists = $null -ne (Get-Item -LiteralPath $InstallDir -Force -ErrorAction SilentlyContinue)
        $StageExists = $null -ne (Get-Item -LiteralPath $Stage -Force -ErrorAction SilentlyContinue)

        # Clean up a failed atomic rename only when no stage exists. If both
        # locations exist, retain the recovery identity for manual inspection.
        # Never discard the journal for a possibly incomplete staged removal.
        if ($OriginalExists -and -not $StageExists) {
            Remove-Item -LiteralPath $Proof -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $Record -Force -ErrorAction SilentlyContinue
        }

        $RecordExists = $null -ne (Get-Item -LiteralPath $Record -Force -ErrorAction SilentlyContinue)
        $ProofExists = $null -ne (Get-Item -LiteralPath $Proof -Force -ErrorAction SilentlyContinue)
        if ($OriginalExists -and -not $StageExists -and -not $RecordExists -and -not $ProofExists) {
            $Explanation = if ($StagePhase -eq 'rename') {
                'The installation directory could not be renamed.'
            }
            else {
                'Removal staging could not be prepared.'
            }
            $Diagnostics = Get-SdkRemovalFailureDiagnostic -InstallDirectory $InstallDir -Failure $_.Exception
            throw "Unable to remove isolated SDK $Version. $Explanation The original installation remains intact; no SDK files were removed. Close applications using this SDK, check filesystem permissions, and try Remove again.`nDiagnostics:`n$Diagnostics`nDetails: $OriginalError"
        }

        $Diagnostics = Get-SdkRemovalFailureDiagnostic -InstallDirectory $InstallDir -Failure $_.Exception
        throw "Unable to remove isolated SDK $Version. Removal staging did not complete, and the filesystem state could not be verified. Do not retry until the SDK and recovery directories have been inspected.`nDiagnostics:`n$Diagnostics`nDetails: $OriginalError"
    }
}

function Complete-PendingRemoval {
    param([string]$Version)
    $State = Get-PendingRemoval -Version $Version
    if (Test-Path -LiteralPath $State.Stage -PathType Container) {
        $script:RemovalProofPath = $State.Proof
        try {
            Invoke-IsolatedSdkDirectoryRemoval -InstallDirectory $State.Stage
        }
        catch {
            $Diagnostics = Get-SdkRemovalFailureDiagnostic -InstallDirectory $State.Stage -Failure $_.Exception
            throw "SDK $Version removal incomplete at $($State.Stage). Files may be in use or partially deleted. Free blocking processes, check filesystem permissions, and try Remove again.`nDiagnostics:`n$Diagnostics`nDetails: $($_.Exception.Message)"
        }
        finally { $script:RemovalProofPath = $null }
    }
    if ($null -ne (Get-Item -LiteralPath $State.Stage -Force -ErrorAction SilentlyContinue)) {
        throw "SDK $Version removal incomplete at $($State.Stage). Free blocking processes and retry Remove."
    }
    Remove-Item -LiteralPath $State.Record -Force -ErrorAction Stop
    $Root = Join-Path $SdkRoot '.pending-removals'
    if (@(Get-ChildItem -LiteralPath $Root -Force -ErrorAction Stop).Count -eq 0) {
        Remove-Item -LiteralPath $Root -Force -ErrorAction Stop
    }
}

function Invoke-IsolatedSdkDirectoryRemoval {
    param([string]$InstallDirectory)

    # Preserve proof until all other contents were removed; incomplete deletion
    # retains the in-directory proof for a later user-initiated retry.
    $ProofPath = $script:RemovalProofPath
    foreach ($Child in @(Get-ChildItem -LiteralPath $InstallDirectory -Force -ErrorAction Stop)) {
        if ($Child.FullName -ceq $ProofPath) { continue }
        Remove-Item -LiteralPath $Child.FullName -Recurse -Force -ErrorAction Stop -WhatIf:$false -Confirm:$false
    }
    if (Test-Path -LiteralPath $ProofPath -PathType Leaf) {
        Remove-Item -LiteralPath $ProofPath -Force -ErrorAction Stop -WhatIf:$false -Confirm:$false
    }
    Remove-Item -LiteralPath $InstallDirectory -Force -ErrorAction Stop -WhatIf:$false -Confirm:$false
    if (Test-Path -LiteralPath $InstallDirectory) {
        throw "SDK directory still exists after removal: $InstallDirectory"
    }
}

# Removal is intentionally scoped to the selected version directory under SDK_ROOT.
function Remove-IsolatedSdk {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [switch]$Yes,
        [switch]$AllowUnsupportedShutdown
    )

    $SelectedInteractively = [string]::IsNullOrWhiteSpace($script:SdkVersion)
    if (-not (Resolve-RemoveVersion)) {
        return
    }

    if ($SelectedInteractively) {
        Write-ToolDisplay
        Clear-InteractiveScreen
    }

    $InstallDir = Join-Path $SdkRoot $SdkVersion
    $IsolatedDotNet = Get-IsolatedDotNetPath -SdkVersion $SdkVersion

    if (-not (Test-RemovableSdkVersion -Version $SdkVersion)) {
        throw "Invalid SDK version for Remove: $SdkVersion"
    }
    $PendingRecord = Join-Path (Join-Path $SdkRoot '.pending-removals') $SdkVersion
    $Recovery = $null
    $HostAvailable = $false
    if ($null -ne (Get-Item -LiteralPath $PendingRecord -Force -ErrorAction SilentlyContinue)) {
        $Recovery = Get-PendingRemoval -Version $SdkVersion
    }
    else {
        $DirectoryInfo = Get-Item -LiteralPath $InstallDir -Force -ErrorAction SilentlyContinue
        if ($null -eq $DirectoryInfo -or -not $DirectoryInfo.PSIsContainer -or
            ($DirectoryInfo.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Unsafe or missing isolated SDK directory: $InstallDir"
        }
        $HostInfo = Get-Item -LiteralPath $IsolatedDotNet -Force -ErrorAction SilentlyContinue
        $HostAvailable = $null -ne $HostInfo -and -not $HostInfo.PSIsContainer -and
        -not ($HostInfo.Attributes -band [IO.FileAttributes]::ReparsePoint)
    }

    if (-not $SelectedInteractively) {
        Write-ToolDisplay
    }
    if ($Recovery) {
        Write-ToolWarning "SDK $SdkVersion has an incomplete removal. Remaining files in $($Recovery.Stage) will be removed."
    }
    else {
        Write-ToolWarning "Isolated SDK $SdkVersion will be removed from $InstallDir"
    }
    if (-not $Recovery -and -not $HostAvailable) {
        Write-ToolWarning "SDK $SdkVersion has no usable isolated dotnet host and cannot be shut down. Build processes may remain, and files in use may prevent removal."
    }
    Write-ToolDisplay

    $ConfirmWasSpecified = $PSBoundParameters.ContainsKey('Confirm')
    if (-not $PSCmdlet.ShouldProcess($InstallDir, "Remove isolated .NET SDK $SdkVersion")) {
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

    if ($Recovery) {
        Write-ToolInfo "Retrying incomplete removal of SDK $SdkVersion..."
        Complete-PendingRemoval -Version $SdkVersion
        Write-ToolSuccess "Isolated SDK $SdkVersion was removed."
        return
    }

    if (-not $HostAvailable) {
        Invoke-ConfirmedSdkRemovalStaging -Version $SdkVersion
        Write-ToolInfo "Removing $InstallDir..."
        Complete-PendingRemoval -Version $SdkVersion
        Write-ToolSuccess "Isolated SDK $SdkVersion was removed."
        return
    }

    Write-ToolInfo "Shutting down build servers for SDK $SdkVersion..."
    $ShutdownArguments = @{
        DotNetPath = $IsolatedDotNet
        SdkVersion = $SdkVersion
    }
    if ($AllowUnsupportedShutdown) {
        $ShutdownArguments.AllowUnsupportedShutdown = $true
    }
    Invoke-IsolatedSdkBuildServerShutdown @ShutdownArguments

    Invoke-ConfirmedSdkRemovalStaging -Version $SdkVersion
    Write-ToolInfo "Removing $InstallDir..."
    Complete-PendingRemoval -Version $SdkVersion

    Write-ToolSuccess "Isolated SDK $SdkVersion was removed."
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
            if ($AllowUnsupportedShutdown) {
                $RemoveArguments.AllowUnsupportedShutdown = $true
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
        'Audit' { Invoke-SdkAudit }
        'Verify' {
            if ($script:InteractiveSession -and [string]::IsNullOrWhiteSpace($script:SdkVersion)) {
                if (-not (Select-VerifyVersion)) {
                    return
                }
                Write-ToolDisplay
                Clear-InteractiveScreen
            }
            Test-IsolatedSdk
        }
    }
}

if ($Version) {
    if ($script:ActionWasSpecified -or
        $script:SdkVersionWasSpecified -or
        $Yes -or
        $AllowUnsupportedShutdown -or
        $script:ConfirmWasSpecified -or
        $script:WhatIfWasSpecified) {
        Write-Error -Message '-Version cannot be combined with action, SDK-version, confirmation, or WhatIf parameters.' -ErrorAction Continue
        exit 1
    }

    Write-Output (Get-ToolVersionText)
    return
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
            Clear-InteractiveScreen
            while ($true) {
                $script:Action = $null
                $script:SdkVersion = $null
                $script:BackToMain = $false
                $script:ExitRequested = $false
                $script:InstallResumeChannel = $null
                $script:InstallResumeReleaseIndex = $null
                $script:InstallResumeChannelMetadata = $null
                $script:InstallResultParent = 'Main'

                if (-not (Select-Action)) {
                    return
                }

                Write-ToolDisplay
                Clear-InteractiveScreen
                while ($true) {
                    Invoke-SelectedAction

                    if ($script:ExitRequested) {
                        return
                    }

                    if ($script:BackToMain) {
                        Write-ToolDisplay
                        Clear-InteractiveScreen
                        break
                    }

                    if ($script:Action -in @('Remove', 'Verify') -and
                        [string]::IsNullOrWhiteSpace($script:SdkVersion)) {
                        Wait-ForInteractiveResultAcknowledgement -Destination 'Main'
                        Write-ToolDisplay
                        Clear-InteractiveScreen
                        break
                    }

                    $Destination = switch ($script:Action) {
                        'Install' { $script:InstallResultParent }
                        'Remove' {
                            $RemainingRemoveVersions = @(
                                @(Get-RemoveSdkCandidateVersion) + @(Get-PendingRemovalVersion) |
                                    Sort-Object -Unique
                            )
                            if ($RemainingRemoveVersions.Count -gt 0) {
                                'Remove'
                            }
                            else {
                                'Main'
                            }
                        }
                        'Verify' { 'Verify' }
                        default { 'Main' }
                    }

                    Wait-ForInteractiveResultAcknowledgement -Destination $Destination
                    Write-ToolDisplay
                    Clear-InteractiveScreen

                    if ($script:Action -in @('List', 'Audit') -or
                        ($script:Action -eq 'Remove' -and $Destination -eq 'Main')) {
                        break
                    }

                    $script:SdkVersion = $null
                    $script:BackToMain = $false
                }
            }
        }

        if (-not (Select-Action)) {
            return
        }

        Invoke-SelectedAction
    }
    catch {
        $FailureMessage = $_.Exception.Message
        if (($FailureMessage.StartsWith('Unable to remove isolated SDK ', [StringComparison]::Ordinal) -or
                $FailureMessage -match '^SDK [^\r\n]+ removal incomplete at ') -and
            $FailureMessage.Contains("`nDiagnostics:`n") -and
            $FailureMessage.Contains("`nDetails: ")) {
            Write-ToolRemovalFailure -Message $FailureMessage
            # Emit the original native failure on the error stream once;
            # the report above contains context and advice without duplication.
            $NativeDetails = ($FailureMessage -split "`nDetails: ", 2)[1]
            Write-Error -Message "Unable to remove isolated SDK $script:SdkVersion. Underlying error: $NativeDetails" -ErrorAction Continue
        }
        else {
            Write-Error -Message $FailureMessage -ErrorAction Continue
        }
        exit 1
    }
}
finally {
    Pop-Location
}