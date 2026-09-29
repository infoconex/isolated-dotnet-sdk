Describe 'PowerShell SDK payload integrity' {
    BeforeEach {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:ToolScript = Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1'
        $script:HomeVariableName = 'USERPROFILE'
        $script:OriginalHomeValue = [Environment]::GetEnvironmentVariable($script:HomeVariableName, 'Process')
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-payload-integrity-{0}" -f [guid]::NewGuid())
        $script:TestHome = Join-Path $script:TestRoot 'home'
        $script:ToolRoot = Join-Path $script:TestHome 'dotnet-sdks'
        $script:ToolPath = Join-Path $script:ToolRoot 'isolated-dotnet-sdk.ps1'
        $script:Version = '99.0.100'
        $script:InstallDir = Join-Path $script:ToolRoot $script:Version
        New-Item -ItemType Directory -Path $script:ToolRoot -Force | Out-Null
        Copy-Item -LiteralPath $script:ToolScript -Destination $script:ToolPath -Force
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:TestHome, 'Process')
        $env:ISOLATED_DOTNET_SDK_TOOL_PATH = $script:ToolPath
        $env:ISOLATED_DOTNET_SDK_EXPAND_MARKER = Join-Path $script:TestHome 'expand-called.txt'
    }

    AfterEach {
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:OriginalHomeValue, 'Process')
        Remove-Item Env:ISOLATED_DOTNET_SDK_TOOL_PATH -ErrorAction SilentlyContinue
        Remove-Item Env:ISOLATED_DOTNET_SDK_EXPAND_MARKER -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'rejects a SDK payload checksum mismatch before extraction' {
        $failureOutput = @(& pwsh -NoProfile -Command '
function Invoke-WebRequest {
    param($Uri, $OutFile)
    if ([string]$Uri -like "*release-metadata*") {
        $rid = "win-x64"
        $url = "https://builds.dotnet.microsoft.com/dotnet/Sdk/99.0.100/dotnet-sdk-99.0.100-$rid.zip"
        @{ releases = @(@{ sdk = @{ version = "99.0.100"; files = @(@{ rid = $rid; url = $url; hash = ("a" * 128) }) } }) } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutFile
    }
    else {
        Set-Content -LiteralPath $OutFile -Value payload
    }
}
function Get-FileHash {
    param([string]$LiteralPath, [string]$Algorithm)
    [pscustomobject]@{ Hash = ("b" * 128) }
}
function Expand-Archive {
    param($LiteralPath, $DestinationPath, [switch]$Force)
    Set-Content -LiteralPath $env:ISOLATED_DOTNET_SDK_EXPAND_MARKER -Value called
}
& $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -Version 99.0.100 -Yes
' 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        ($failureOutput -join [Environment]::NewLine) |
            Should -Match 'Integrity verification failed for the \.NET SDK 99\.0\.100 payload\.'
        Test-Path -LiteralPath $env:ISOLATED_DOTNET_SDK_EXPAND_MARKER | Should -BeFalse
        Test-Path -LiteralPath $script:InstallDir | Should -BeFalse
        @(Get-ChildItem -LiteralPath $script:ToolRoot -Filter '.sdk-payload-*' -ErrorAction SilentlyContinue).Count |
            Should -Be 0
    }

    It 'fails closed when the SDK artifact checksum is malformed' {
        $failureOutput = @(& pwsh -NoProfile -Command '
function Invoke-WebRequest {
    param($Uri, $OutFile)
    if ([string]$Uri -like "*release-metadata*") {
        $rid = "win-x64"
        $url = "https://builds.dotnet.microsoft.com/dotnet/Sdk/99.0.100/dotnet-sdk-99.0.100-$rid.zip"
        @{ releases = @(@{ sdk = @{ version = "99.0.100"; files = @(@{ rid = $rid; url = $url; hash = "deadbeef" }) } }) } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutFile
    }
}
& $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -Version 99.0.100 -Yes
' 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        ($failureOutput -join [Environment]::NewLine) |
            Should -Match 'invalid SHA-512 hash for SDK 99\.0\.100 and win-x64'
        Test-Path -LiteralPath $script:InstallDir | Should -BeFalse
    }

    It 'fails closed when matching SDK artifact metadata is missing' {
        $failureOutput = @(& pwsh -NoProfile -Command '
function Invoke-WebRequest {
    param($Uri, $OutFile)
    if ([string]$Uri -like "*release-metadata*") {
        @{ releases = @(@{ sdk = @{ version = "99.0.100"; files = @(@{ rid = "win-arm64"; url = "https://builds.dotnet.microsoft.com/example.zip"; hash = ("a" * 128) }) } }) } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutFile
    }
}
& $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -Version 99.0.100 -Yes
' 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        ($failureOutput -join [Environment]::NewLine) |
            Should -Match 'did not contain exactly one SDK archive for 99\.0\.100 and win-x64'
        Test-Path -LiteralPath $script:InstallDir | Should -BeFalse
    }
}
