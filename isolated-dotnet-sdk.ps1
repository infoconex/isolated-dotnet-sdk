<#
.SYNOPSIS
Installs and manages isolated .NET SDK versions.

.DESCRIPTION
Installs exact .NET SDK versions under the current user's dotnet-sdks directory without modifying the system-wide .NET installation or PATH. The script can install, remove, and list isolated SDKs and provides an interactive workflow when an action or version is not supplied.

.PARAMETER Action
Specifies the operation to perform: Install, Remove, or List. When omitted, the script prompts for an action unless Version is supplied, in which case Install is selected.

.PARAMETER Version
Specifies an exact .NET SDK version. When omitted for Install or Remove, the script provides an interactive version selection workflow.

.PARAMETER Yes
Skips confirmation prompts that support automatic confirmation.

.EXAMPLE
.\isolated-dotnet-sdk.ps1 -Action List

Lists SDKs installed in the isolated SDK directory.

.EXAMPLE
.\isolated-dotnet-sdk.ps1 -Action Install -Version 10.0.100

Installs .NET SDK 10.0.100 in an isolated directory.

.EXAMPLE
.\isolated-dotnet-sdk.ps1 -Action Remove -Version 10.0.100 -Yes

Removes the isolated .NET SDK 10.0.100 without prompting for confirmation.

.EXAMPLE
.\isolated-dotnet-sdk.ps1

Starts the interactive workflow.

.LINK
https://github.com/infoconex/isolated-dotnet-sdk
#>
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
$InstallScript = Join-Path $SdkRoot 'dotnet-install.ps1'
$script:Bootstrapped = $false
$script:ActionWasSpecified = $PSBoundParameters.ContainsKey('Action')
$script:VersionWasSpecified = $PSBoundParameters.ContainsKey('Version')

function Write-ToolInfo {
    param([string]$Message)
    Write-Host 'isolated-dotnet-sdk:' -ForegroundColor Cyan -NoNewline
    Write-Host " $Message"
}

function Write-ToolWarning {
    param([string]$Message)
    Write-Host 'isolated-dotnet-sdk:' -ForegroundColor Yellow -NoNewline
    Write-Host " $Message"
}

function Write-ToolSuccess {
    param([string]$Message)
    Write-Host 'isolated-dotnet-sdk:' -ForegroundColor Green -NoNewline
    Write-Host " $Message"
}

function Write-ToolError {
    param([string]$Message)
    Write-Host 'isolated-dotnet-sdk:' -ForegroundColor Red -NoNewline
    Write-Host " $Message"
}

function Assert-ValidAction {
    if ([string]::IsNullOrWhiteSpace($script:Action)) {
        return
    }

    if ($script:Action -notin @('Install', 'Remove', 'List')) {
        throw "Invalid action: $script:Action"
    }
}

function Assert-ValidVersion {
    if ($script:Version -notmatch '^[0-9A-Za-z][0-9A-Za-z.+-]*$') {
        throw "Invalid SDK version: $script:Version"
    }
}

function Confirm-Action {
    param([string]$Prompt)

    if ($Yes) {
        return $true
    }

    $Response = Read-Host "isolated-dotnet-sdk: $Prompt [y/N]"
    return $Response -match '^[Yy]$'
}

function Install-ToolIfNeeded {
    New-Item -ItemType Directory -Path $SdkRoot -Force | Out-Null

    $CurrentPath = $null
    if ($PSCommandPath) {
        $CurrentPath = [System.IO.Path]::GetFullPath($PSCommandPath)
    }

    $ExpectedPath = [System.IO.Path]::GetFullPath($ToolPath)

    if ($CurrentPath -eq $ExpectedPath) {
        return
    }

    Write-ToolInfo "Installing tool to $ToolPath"

    if ($CurrentPath -and (Test-Path -LiteralPath $CurrentPath)) {
        Copy-Item -LiteralPath $CurrentPath -Destination $ToolPath -Force
    }
    else {
        Invoke-WebRequest `
            "$RepositoryRawBase/$ToolName" `
            -OutFile $ToolPath
    }

    if (Get-Command Unblock-File -ErrorAction SilentlyContinue) {
        Unblock-File -Path $ToolPath
    }

    Write-ToolSuccess 'Tool installed.'

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

    & $ToolPath @Arguments
    $script:Bootstrapped = $true
}

function Get-IsolatedDotNetPath {
    param([string]$SdkVersion)
    return Join-Path (Join-Path $SdkRoot $SdkVersion) 'dotnet.exe'
}

function Get-SystemSdkVersions {
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        return @()
    }

    return @(dotnet --list-sdks | ForEach-Object { ($_ -split '\s+')[0] })
}

function Get-IsolatedSdkVersions {
    $SdkDirectories = Get-ChildItem `
        -Path $SdkRoot `
        -Directory `
        -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName 'dotnet.exe') } |
        Sort-Object Name

    return @($SdkDirectories | ForEach-Object { $_.Name })
}

function Show-IsolatedSdks {
    Write-ToolInfo "Isolated SDKs under ${SdkRoot}:"
    $Versions = @(Get-IsolatedSdkVersions)

    if (-not $Versions) {
        Write-Host '  None'
        return
    }

    foreach ($SdkVersion in $Versions) {
        Write-Host "  $SdkVersion"
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
        Write-ToolInfo 'What would you like to do?'
        Write-Host
        Write-Host '  1. Install an SDK'
        Write-Host '  2. Remove an isolated SDK'
        Write-Host '  3. List isolated SDKs'
        Write-Host '  4. Exit'
        Write-Host

        $Selection = Read-Host 'Selection'

        switch ($Selection) {
            '1' { $script:Action = 'Install'; return $true }
            '2' { $script:Action = 'Remove'; return $true }
            '3' { $script:Action = 'List'; return $true }
            '4' { Write-ToolInfo 'Exiting.'; return $false }
            'q' { Write-ToolInfo 'Exiting.'; return $false }
            'Q' { Write-ToolInfo 'Exiting.'; return $false }
            default { Write-ToolWarning 'Please choose 1, 2, 3, or 4.' }
        }
    }
}

function Get-ReleaseIndex {
    Write-ToolInfo 'Loading available .NET SDK releases from Microsoft...'
    return Invoke-RestMethod -Uri $ReleaseIndexUrl
}

function Get-ChannelSdkVersions {
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
    $script:Version = Read-Host 'isolated-dotnet-sdk: .NET SDK version'
    if ([string]::IsNullOrWhiteSpace($script:Version)) {
        throw 'An SDK version is required.'
    }

    Assert-ValidVersion
}

function Select-InstallVersion {
    $ReleaseIndex = Get-ReleaseIndex
    $AllChannels = @($ReleaseIndex.'releases-index')
    $ShowArchived = $false

    while ($true) {
        Write-Host

        if ($ShowArchived) {
            Write-ToolInfo 'Select an end-of-life .NET channel:'
            $Channels = @($AllChannels | Where-Object { $_.'support-phase' -eq 'eol' })
        }
        else {
            Write-ToolInfo 'Select a supported or development .NET channel:'
            $Channels = @($AllChannels | Where-Object { $_.'support-phase' -ne 'eol' })
        }

        Write-Host

        for ($Index = 0; $Index -lt $Channels.Count; $Index++) {
            $Channel = $Channels[$Index]
            $ReleaseType = ([string]$Channel.'release-type').ToUpperInvariant()
            $SupportPhase = Format-SupportPhase ([string]$Channel.'support-phase')

            Write-Host ("  {0}. .NET {1}  {2}  {3}  latest SDK {4}" -f `
                ($Index + 1), `
                $Channel.'channel-version', `
                $ReleaseType, `
                $SupportPhase, `
                $Channel.'latest-sdk')
        }

        Write-Host
        if ($ShowArchived) {
            Write-Host '  S. Show supported/development channels'
        }
        else {
            Write-Host '  A. Show end-of-life channels'
        }
        Write-Host '  M. Enter an exact SDK version manually'
        Write-Host '  Q. Cancel'
        Write-Host

        $Selection = Read-Host 'Selection'

        if ($Selection -match '^[Mm]$') {
            Read-ManualVersion
            return $true
        }

        if ($Selection -match '^[Qq]$') {
            return $false
        }

        if ($Selection -match '^[Aa]$' -and -not $ShowArchived) {
            $ShowArchived = $true
            continue
        }

        if ($Selection -match '^[Ss]$' -and $ShowArchived) {
            $ShowArchived = $false
            continue
        }

        $Number = 0
        if (-not [int]::TryParse($Selection, [ref]$Number) -or
            $Number -lt 1 -or
            $Number -gt $Channels.Count) {
            Write-ToolWarning 'Invalid selection.'
            continue
        }

        $SelectedChannel = $Channels[$Number - 1]
        $ChannelMetadata = Invoke-RestMethod -Uri $SelectedChannel.'releases.json'
        $SdkVersions = @(Get-ChannelSdkVersions $ChannelMetadata)

        if (-not $SdkVersions) {
            throw "No SDK versions were found for .NET $($SelectedChannel.'channel-version')."
        }

        $SystemVersions = @(Get-SystemSdkVersions)
        $IsolatedVersions = @(Get-IsolatedSdkVersions)

        while ($true) {
            Write-Host
            Write-ToolInfo "Available .NET $($SelectedChannel.'channel-version') SDKs:"
            Write-Host

            for ($Index = 0; $Index -lt $SdkVersions.Count; $Index++) {
                $SdkVersion = $SdkVersions[$Index]
                $Markers = [System.Collections.Generic.List[string]]::new()

                if ($SdkVersion -eq $SelectedChannel.'latest-sdk') {
                    $Markers.Add('latest')
                }
                if ($SystemVersions -contains $SdkVersion) {
                    $Markers.Add('system')
                }
                if ($IsolatedVersions -contains $SdkVersion) {
                    $Markers.Add('isolated')
                }

                if ($Markers.Count -gt 0) {
                    Write-Host ("  {0}. {1} ({2})" -f ($Index + 1), $SdkVersion, ($Markers -join ', '))
                }
                else {
                    Write-Host ("  {0}. {1}" -f ($Index + 1), $SdkVersion)
                }
            }

            Write-Host
            Write-Host '  B. Back to .NET channels'
            Write-Host '  M. Enter an exact SDK version manually'
            Write-Host '  Q. Cancel'
            Write-Host

            $Selection = Read-Host 'Selection'

            if ($Selection -match '^[Bb]$') {
                break
            }

            if ($Selection -match '^[Mm]$') {
                Read-ManualVersion
                return $true
            }

            if ($Selection -match '^[Qq]$') {
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

            Write-ToolWarning 'Invalid selection.'
        }
    }
}

function Select-RemoveVersion {
    $SdkVersions = @(Get-IsolatedSdkVersions)

    if (-not $SdkVersions) {
        Write-ToolInfo "No isolated SDKs are installed under $SdkRoot."
        return $false
    }

    while ($true) {
        Write-ToolInfo 'Select an isolated SDK to remove:'
        Write-Host

        for ($Index = 0; $Index -lt $SdkVersions.Count; $Index++) {
            Write-Host ("  {0}. {1}" -f ($Index + 1), $SdkVersions[$Index])
        }

        Write-Host
        Write-Host '  Q. Cancel'
        Write-Host

        $Selection = Read-Host 'Selection'

        if ($Selection -match '^[Qq]$') {
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

        Write-ToolWarning 'Invalid selection.'
    }
}

function Resolve-InstallVersion {
    if (-not [string]::IsNullOrWhiteSpace($script:Version)) {
        Assert-ValidVersion
        return $true
    }

    if (-not (Select-InstallVersion)) {
        Write-ToolInfo 'Installation cancelled.'
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
        Write-ToolInfo 'Removal cancelled.'
        return $false
    }

    return $true
}

function Install-IsolatedSdk {
    if (-not (Resolve-InstallVersion)) {
        return
    }

    $InstallDir = Join-Path $SdkRoot $Version
    $IsolatedDotNet = Get-IsolatedDotNetPath -SdkVersion $Version

    Write-ToolInfo "Target SDK: $Version"
    Write-ToolInfo "Isolated install directory: $InstallDir"
    Write-Host

    Write-ToolInfo 'Checking SDKs installed through the normal dotnet host...'

    $InstalledVersions = @()
    if (Get-Command dotnet -ErrorAction SilentlyContinue) {
        $InstalledSdks = dotnet --list-sdks
        $InstalledSdks
        Write-Host
        $InstalledVersions = @($InstalledSdks | ForEach-Object { ($_ -split '\s+')[0] })
    }
    else {
        Write-ToolWarning 'No system dotnet installation was found.'
        Write-Host
    }

    Write-ToolInfo 'Checking for an existing isolated SDK...'

    if (Test-Path $IsolatedDotNet) {
        $IsolatedVersions = @(& $IsolatedDotNet --list-sdks | ForEach-Object { ($_ -split '\s+')[0] })

        if ($IsolatedVersions -contains $Version) {
            Write-ToolSuccess "Isolated SDK $Version is already installed."
            Write-ToolInfo "Location: $InstallDir"
            return
        }
    }

    Write-ToolInfo 'No existing isolated copy was found.'
    Write-Host

    if ($InstalledVersions -contains $Version) {
        Write-ToolWarning ".NET SDK $Version is already installed normally."

        if (-not (Confirm-Action -Prompt 'Install an isolated copy too?')) {
            Write-ToolInfo 'Installation cancelled.'
            return
        }

        Write-Host
    }

    Write-ToolInfo "Downloading Microsoft's dotnet-install.ps1 script..."
    Invoke-WebRequest 'https://dot.net/v1/dotnet-install.ps1' -OutFile $InstallScript

    if (Get-Command Unblock-File -ErrorAction SilentlyContinue) {
        Unblock-File -Path $InstallScript
    }

    Write-ToolInfo "Installing .NET SDK $Version..."

    & $InstallScript `
        -Version $Version `
        -InstallDir $InstallDir `
        -NoPath

    Write-Host
    Write-ToolInfo 'Verifying the isolated SDK...'

    if (-not (Test-Path $IsolatedDotNet)) {
        throw "The isolated dotnet executable was not found at $IsolatedDotNet"
    }

    $IsolatedSdks = & $IsolatedDotNet --list-sdks
    $IsolatedSdks

    $IsolatedVersions = @($IsolatedSdks | ForEach-Object { ($_ -split '\s+')[0] })
    if ($IsolatedVersions -notcontains $Version) {
        throw "SDK $Version was not found after installation."
    }

    Write-Host
    Write-ToolSuccess 'Isolated SDK installation completed successfully.'
    Write-ToolInfo "Location: $InstallDir"
}

function Remove-IsolatedSdk {
    if (-not (Resolve-RemoveVersion)) {
        return
    }

    $InstallDir = Join-Path $SdkRoot $Version
    $IsolatedDotNet = Get-IsolatedDotNetPath -SdkVersion $Version

    if (-not (Test-Path $IsolatedDotNet)) {
        throw "Isolated SDK $Version was not found at $InstallDir"
    }

    Write-ToolWarning "Isolated SDK $Version will be removed from $InstallDir"

    if (-not (Confirm-Action -Prompt 'Continue?')) {
        Write-ToolInfo 'Removal cancelled.'
        return
    }

    Write-ToolInfo "Shutting down build servers for SDK $Version..."
    & $IsolatedDotNet build-server shutdown

    Write-ToolInfo "Removing $InstallDir..."
    Remove-Item -Path $InstallDir -Recurse -Force

    if (Test-Path $InstallDir) {
        throw "SDK directory still exists after removal: $InstallDir"
    }

    Write-ToolSuccess "Isolated SDK $Version was removed."
}

Install-ToolIfNeeded

if ($script:Bootstrapped) {
    return
}

New-Item -ItemType Directory -Path $SdkRoot -Force | Out-Null

Push-Location $SdkRoot
try {
    try {
        if (-not (Select-Action)) {
            return
        }

        switch ($Action) {
            'Install' { Install-IsolatedSdk }
            'Remove' { Remove-IsolatedSdk }
            'List' { Show-IsolatedSdks }
        }
    }
    catch {
        Write-ToolError $_.Exception.Message
        exit 1
    }
}
finally {
    Pop-Location
}
