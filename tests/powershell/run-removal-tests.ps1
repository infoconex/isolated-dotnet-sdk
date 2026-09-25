$ErrorActionPreference = 'Stop'

$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$ToolScript = Join-Path $RepositoryRoot 'isolated-dotnet-sdk.ps1'
$TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-removal-tests-{0}" -f [guid]::NewGuid())
$TestHome = Join-Path $TestRoot 'home'
$ToolRoot = Join-Path $TestHome 'dotnet-sdks'
$InstalledToolPath = Join-Path $ToolRoot 'isolated-dotnet-sdk.ps1'
$RemovalVersion = '99.0.0-removal-test'
$HomeVariableName = if ($IsWindows) { 'USERPROFILE' } else { 'HOME' }
$OriginalHomeValue = [Environment]::GetEnvironmentVariable($HomeVariableName, 'Process')
$Failure = $null

function Write-Pass {
    param([string]$Message)
    Write-Output "PASS: $Message"
}

function Import-ToolFunctionDefinition {
    $Tokens = $null
    $Errors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $ToolScript,
        [ref]$Tokens,
        [ref]$Errors)

    if ($Errors.Count -gt 0) {
        throw "Unable to parse product script for removal tests: $($Errors[0].Message)"
    }

    $FunctionDefinitions = $Ast.FindAll(
        {
            param($Node)
            $Node -is [System.Management.Automation.Language.FunctionDefinitionAst]
        },
        $true)

    foreach ($FunctionDefinition in $FunctionDefinitions) {
        . ([scriptblock]::Create($FunctionDefinition.Extent.Text))
    }
}

function Reset-RemovalTarget {
    $InstallDirectory = Join-Path $script:SdkRoot $script:Version
    if (Test-Path -LiteralPath $InstallDirectory) {
        Microsoft.PowerShell.Management\Remove-Item -LiteralPath $InstallDirectory -Recurse -Force
    }

    New-Item -ItemType Directory -Path $InstallDirectory -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $InstallDirectory 'dotnet.exe') -Force | Out-Null
    return $InstallDirectory
}

try {
    New-Item -ItemType Directory -Path $TestHome -Force | Out-Null
    [Environment]::SetEnvironmentVariable($HomeVariableName, $TestHome, 'Process')

    # Public contract: a source invocation must forward -WhatIf through bootstrap and
    # leave the selected SDK untouched.
    $PublicInstallDirectory = Join-Path $ToolRoot $RemovalVersion
    New-Item -ItemType Directory -Path $PublicInstallDirectory -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $PublicInstallDirectory 'dotnet.exe') -Force | Out-Null

    $WhatIfOutput = @(& pwsh -NoProfile -File $ToolScript -Action Remove -Version $RemovalVersion -WhatIf 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "public -WhatIf removal failed with exit code $LASTEXITCODE"
    }
    if (-not (Test-Path -LiteralPath $PublicInstallDirectory)) {
        throw 'public -WhatIf removal changed SDK state'
    }
    if (($WhatIfOutput -join [Environment]::NewLine) -notmatch 'What if:') {
        throw 'public -WhatIf removal did not describe the intended operation'
    }
    Write-Pass 'public -WhatIf bootstrap forwarding'

    # Risk-mitigation parameters are intentionally scoped to Remove until other actions
    # receive their own ShouldProcess contracts.
    $UnsupportedOutput = @(& pwsh -NoProfile -File $InstalledToolPath -Action List -WhatIf 2>&1)
    if ($LASTEXITCODE -eq 0) {
        throw 'List unexpectedly accepted -WhatIf'
    }
    if (($UnsupportedOutput -join [Environment]::NewLine) -notmatch 'supported only with.*Remove') {
        throw 'unsupported -WhatIf action did not produce the expected contract error'
    }
    Write-Pass 'risk-mitigation parameters reject unsupported actions'

    # Ordinary removal remains fail-safe in a non-interactive host.
    $NonInteractiveOutput = @(& pwsh -NoProfile -NonInteractive -File $InstalledToolPath -Action Remove -Version $RemovalVersion 2>&1)
    if ($LASTEXITCODE -eq 0) {
        throw 'non-interactive removal without approval unexpectedly succeeded'
    }
    if (-not (Test-Path -LiteralPath $PublicInstallDirectory)) {
        throw 'non-interactive removal without approval changed SDK state'
    }
    Write-Pass 'non-interactive removal is fail-safe'

    # Load repository functions without executing the script entry point. These focused
    # behavioral checks isolate confirmation/orchestration from a real SDK installation.
    Import-ToolFunctionDefinition
    $script:SdkRoot = Join-Path $TestRoot 'function-home'
    $script:Version = $RemovalVersion

    $RemoveCommand = Get-Command Remove-IsolatedSdk -CommandType Function
    if (-not $RemoveCommand.Parameters.ContainsKey('WhatIf')) {
        throw 'Remove-IsolatedSdk does not expose native -WhatIf'
    }
    if (-not $RemoveCommand.Parameters.ContainsKey('Confirm')) {
        throw 'Remove-IsolatedSdk does not expose native -Confirm'
    }
    Write-Pass 'Remove-IsolatedSdk exposes native risk-mitigation parameters'

    # Default cancellation keeps the SDK and performs no shutdown.
    $InstallDirectory = Reset-RemovalTarget
    $script:ConfirmationCallCount = 0
    $script:ShutdownCallCount = 0
    function Confirm-Action {
        param([string]$Prompt)
        $script:ConfirmationCallCount++
        return $false
    }
    function Stop-IsolatedSdkBuildServer {
        param([string]$DotNetPath, [string]$SdkVersion)
        $script:ShutdownCallCount++
        throw 'shutdown must not run after cancellation'
    }

    Remove-IsolatedSdk
    if ($script:ConfirmationCallCount -ne 1 -or $script:ShutdownCallCount -ne 0) {
        throw 'default cancellation did not preserve the confirmation-before-shutdown contract'
    }
    if (-not (Test-Path -LiteralPath $InstallDirectory)) {
        throw 'default cancellation removed the SDK directory'
    }
    Write-Pass 'default cancellation contract'

    # Default approval shuts down first and then removes the selected directory.
    $InstallDirectory = Reset-RemovalTarget
    $script:ConfirmationCallCount = 0
    $script:ShutdownCallCount = 0
    function Confirm-Action {
        param([string]$Prompt)
        $script:ConfirmationCallCount++
        return $true
    }
    function Stop-IsolatedSdkBuildServer {
        param([string]$DotNetPath, [string]$SdkVersion)
        $script:ShutdownCallCount++
    }

    Remove-IsolatedSdk
    if ($script:ConfirmationCallCount -ne 1 -or $script:ShutdownCallCount -ne 1) {
        throw 'default approval did not perform one confirmation and one shutdown'
    }
    if (Test-Path -LiteralPath $InstallDirectory) {
        throw 'default approved removal did not delete the SDK directory'
    }
    Write-Pass 'default approval contract'

    # Explicit -Confirm:$false is an automation path and must not invoke the tool prompt.
    $InstallDirectory = Reset-RemovalTarget
    $script:ShutdownCallCount = 0
    function Confirm-Action {
        param([string]$Prompt)
        throw 'tool-owned confirmation must not run for explicit -Confirm:$false'
    }
    function Stop-IsolatedSdkBuildServer {
        param([string]$DotNetPath, [string]$SdkVersion)
        $script:ShutdownCallCount++
    }

    Remove-IsolatedSdk -Confirm:$false
    if ($script:ShutdownCallCount -ne 1 -or (Test-Path -LiteralPath $InstallDirectory)) {
        throw 'explicit -Confirm:$false did not perform approved removal'
    }
    Write-Pass 'explicit confirmation suppression contract'

    # -Yes remains supported but cannot override -WhatIf.
    $InstallDirectory = Reset-RemovalTarget
    $script:ShutdownCallCount = 0
    function Confirm-Action {
        param([string]$Prompt)
        throw 'tool-owned confirmation must not run for -Yes'
    }
    function Stop-IsolatedSdkBuildServer {
        param([string]$DotNetPath, [string]$SdkVersion)
        $script:ShutdownCallCount++
    }

    Remove-IsolatedSdk -Yes
    if ($script:ShutdownCallCount -ne 1 -or (Test-Path -LiteralPath $InstallDirectory)) {
        throw '-Yes did not perform approved removal'
    }
    Write-Pass '-Yes removal contract'

    $InstallDirectory = Reset-RemovalTarget
    $script:ShutdownCallCount = 0
    function Stop-IsolatedSdkBuildServer {
        param([string]$DotNetPath, [string]$SdkVersion)
        $script:ShutdownCallCount++
        throw 'shutdown must not run under -WhatIf'
    }

    $WhatIfFunctionOutput = @(Remove-IsolatedSdk -Yes -WhatIf *>&1)
    if ($script:ShutdownCallCount -ne 0 -or -not (Test-Path -LiteralPath $InstallDirectory)) {
        throw '-WhatIf did not take precedence over -Yes'
    }
    if (($WhatIfFunctionOutput -join [Environment]::NewLine) -notmatch 'What if:') {
        throw 'function -WhatIf did not describe the intended operation'
    }
    Write-Pass '-WhatIf precedence over -Yes'

    # A shutdown failure is terminal and must leave the SDK directory intact.
    $InstallDirectory = Reset-RemovalTarget
    function Confirm-Action {
        param([string]$Prompt)
        return $true
    }
    function Stop-IsolatedSdkBuildServer {
        param([string]$DotNetPath, [string]$SdkVersion)
        throw 'simulated shutdown failure'
    }

    $ShutdownFailed = $false
    try {
        Remove-IsolatedSdk
    }
    catch {
        $ShutdownFailed = $true
        if ($_.Exception.Message -notmatch 'simulated shutdown failure') {
            throw
        }
    }
    if (-not $ShutdownFailed -or -not (Test-Path -LiteralPath $InstallDirectory)) {
        throw 'shutdown failure did not abort before deletion'
    }
    Write-Pass 'shutdown failure blocks deletion'

    # A deletion failure propagates and must not emit the success result.
    $InstallDirectory = Reset-RemovalTarget
    function Stop-IsolatedSdkBuildServer {
        param([string]$DotNetPath, [string]$SdkVersion)
    }
    function Remove-IsolatedSdkDirectory {
        param([string]$InstallDirectory)
        throw 'simulated deletion failure'
    }

    $DeletionFailed = $false
    $RemovalInformation = @()
    try {
        Remove-IsolatedSdk -InformationVariable RemovalInformation
    }
    catch {
        $DeletionFailed = $true
        if ($_.Exception.Message -notmatch 'simulated deletion failure') {
            throw
        }
    }
    if (-not $DeletionFailed -or -not (Test-Path -LiteralPath $InstallDirectory)) {
        throw 'deletion failure did not preserve the SDK directory'
    }
    if (($RemovalInformation.MessageData -join [Environment]::NewLine) -match 'was removed') {
        throw 'deletion failure emitted a success result'
    }
    Write-Pass 'deletion failure blocks success reporting'
}
catch {
    $Failure = $_.Exception.Message
}
finally {
    [Environment]::SetEnvironmentVariable($HomeVariableName, $OriginalHomeValue, 'Process')
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $TestRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($null -ne $Failure) {
    [Console]::Error.WriteLine("FAIL: $Failure")
    exit 1
}

Write-Output 'All PowerShell removal behavioral tests passed.'
