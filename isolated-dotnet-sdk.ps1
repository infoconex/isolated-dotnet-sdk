param(
    [ValidateSet('Install', 'Remove', 'List')]
    [string]$Action = 'Install',

    [string]$Version,

    [switch]$Yes
)

$ErrorActionPreference = 'Stop'

$RepositoryRawBase = 'https://raw.githubusercontent.com/infoconex/isolated-dotnet-sdk/main'
$ToolName = 'isolated-dotnet-sdk.ps1'
$SdkRoot = Join-Path $HOME 'dotnet-sdks'
$ToolPath = Join-Path $SdkRoot $ToolName
$InstallScript = Join-Path $SdkRoot 'dotnet-install.ps1'

function Write-Info {
    param([string]$Message)

    Write-Host 'isolated-dotnet-sdk:' -ForegroundColor Cyan -NoNewline
    Write-Host " $Message"
}

function Write-WarningMessage {
    param([string]$Message)

    Write-Host 'isolated-dotnet-sdk:' -ForegroundColor Yellow -NoNewline
    Write-Host " $Message"
}

function Write-Success {
    param([string]$Message)

    Write-Host 'isolated-dotnet-sdk:' -ForegroundColor Green -NoNewline
    Write-Host " $Message"
}

function Assert-ValidVersion {
    if ($script:Version -notmatch '^[0-9A-Za-z][0-9A-Za-z.+-]*$') {
        throw "Invalid SDK version: $script:Version"
    }
}

function Get-VersionIfNeeded {
    if ([string]::IsNullOrWhiteSpace($script:Version)) {
        $script:Version = Read-Host 'isolated-dotnet-sdk: .NET SDK version'

        if ([string]::IsNullOrWhiteSpace($script:Version)) {
            throw 'An SDK version is required.'
        }
    }

    Assert-ValidVersion
}

function Confirm-Action {
    param([string]$Prompt)

    if ($Yes) {
        return $true
    }

    $Response = Read-Host "isolated-dotnet-sdk: $Prompt [y/N]"
    return $Response -match '^[Yy]$'
}

$script:Bootstrapped = $false

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

    Write-Info "Installing tool to $ToolPath"

    Invoke-WebRequest `
        "$RepositoryRawBase/$ToolName" `
        -OutFile $ToolPath

    if (Get-Command Unblock-File -ErrorAction SilentlyContinue) {
        Unblock-File -Path $ToolPath
    }

    Write-Success 'Tool installed.'

    $Arguments = @{
        Action = $Action
    }

    if (-not [string]::IsNullOrWhiteSpace($Version)) {
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

    $InstallDir = Join-Path $SdkRoot $SdkVersion
    return Join-Path $InstallDir 'dotnet.exe'
}

function Show-IsolatedSdks {
    Write-Info "Isolated SDKs under ${SdkRoot}:"

    $SdkDirectories = Get-ChildItem `
        -Path $SdkRoot `
        -Directory `
        -ErrorAction SilentlyContinue |
        Where-Object {
            Test-Path (Join-Path $_.FullName 'dotnet.exe')
        } |
        Sort-Object Name

    if (-not $SdkDirectories) {
        Write-Host '  None'
        return
    }

    foreach ($Directory in $SdkDirectories) {
        Write-Host "  $($Directory.Name)"
    }
}

function Install-IsolatedSdk {
    Get-VersionIfNeeded

    $InstallDir = Join-Path $SdkRoot $Version
    $IsolatedDotNet = Get-IsolatedDotNetPath -SdkVersion $Version

    Write-Info "Target SDK: $Version"
    Write-Info "Isolated install directory: $InstallDir"
    Write-Host

    Write-Info 'Checking SDKs installed through the normal dotnet host...'

    $DotNetCommand = Get-Command dotnet -ErrorAction SilentlyContinue
    $InstalledVersions = @()

    if ($DotNetCommand) {
        $InstalledSdks = dotnet --list-sdks
        $InstalledSdks
        Write-Host

        $InstalledVersions = $InstalledSdks |
            ForEach-Object { ($_ -split '\s+')[0] }
    }
    else {
        Write-WarningMessage 'No system dotnet installation was found.'
        Write-Host
    }

    Write-Info 'Checking for an existing isolated SDK...'

    if (Test-Path $IsolatedDotNet) {
        $IsolatedVersions = & $IsolatedDotNet --list-sdks |
            ForEach-Object { ($_ -split '\s+')[0] }

        if ($IsolatedVersions -contains $Version) {
            Write-Success "Isolated SDK $Version is already installed."
            Write-Info "Location: $InstallDir"
            return
        }
    }

    Write-Info 'No existing isolated copy was found.'
    Write-Host

    if ($InstalledVersions -contains $Version) {
        Write-WarningMessage ".NET SDK $Version is already installed normally."

        if (-not (Confirm-Action -Prompt 'Install an isolated copy too?')) {
            Write-Info 'Installation cancelled.'
            return
        }

        Write-Host
    }

    Write-Info "Downloading Microsoft's dotnet-install.ps1 script..."

    Invoke-WebRequest `
        'https://dot.net/v1/dotnet-install.ps1' `
        -OutFile $InstallScript

    if (Get-Command Unblock-File -ErrorAction SilentlyContinue) {
        Unblock-File -Path $InstallScript
    }

    Write-Info "Installing .NET SDK $Version..."

    & $InstallScript `
        -Version $Version `
        -InstallDir $InstallDir `
        -NoPath

    Write-Host
    Write-Info 'Verifying the isolated SDK...'

    if (-not (Test-Path $IsolatedDotNet)) {
        throw "The isolated dotnet executable was not found at $IsolatedDotNet"
    }

    $IsolatedSdks = & $IsolatedDotNet --list-sdks
    $IsolatedSdks

    $IsolatedVersions = $IsolatedSdks |
        ForEach-Object { ($_ -split '\s+')[0] }

    if ($IsolatedVersions -notcontains $Version) {
        throw "SDK $Version was not found after installation."
    }

    Write-Host
    Write-Success 'Isolated SDK installation completed successfully.'
    Write-Info "Location: $InstallDir"
}

function Remove-IsolatedSdk {
    Get-VersionIfNeeded

    $InstallDir = Join-Path $SdkRoot $Version
    $IsolatedDotNet = Get-IsolatedDotNetPath -SdkVersion $Version

    if (-not (Test-Path $IsolatedDotNet)) {
        throw "Isolated SDK $Version was not found at $InstallDir"
    }

    Write-WarningMessage "Isolated SDK $Version will be removed from $InstallDir"

    if (-not (Confirm-Action -Prompt 'Continue?')) {
        Write-Info 'Removal cancelled.'
        return
    }

    Write-Info "Shutting down build servers for SDK $Version..."
    & $IsolatedDotNet build-server shutdown

    Write-Info "Removing $InstallDir..."
    Remove-Item -Path $InstallDir -Recurse -Force

    if (Test-Path $InstallDir) {
        throw "SDK directory still exists after removal: $InstallDir"
    }

    Write-Success "Isolated SDK $Version was removed."
}

Install-ToolIfNeeded

if ($script:Bootstrapped) {
    return
}

New-Item -ItemType Directory -Path $SdkRoot -Force | Out-Null

Push-Location $SdkRoot
try {
    switch ($Action) {
        'Install' {
            Install-IsolatedSdk
        }
        'Remove' {
            Remove-IsolatedSdk
        }
        'List' {
            Show-IsolatedSdks
        }
    }
}
finally {
    Pop-Location
}
