Describe 'PowerShell installation finalization failures' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:ToolScript = Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1'
        $script:HomeVariableName = if ($IsWindows) { 'USERPROFILE' } else { 'HOME' }
        $script:FakeHostOutput = $env:ISOLATED_DOTNET_SDK_SHARED_FAKE_HOST_ROOT
        if ([string]::IsNullOrWhiteSpace($script:FakeHostOutput) -or
            -not (Test-Path -LiteralPath $script:FakeHostOutput -PathType Container)) {
            throw 'Shared deterministic fake dotnet host is required. Run tests through tests/powershell/run-tests.ps1.'
        }
    }

    BeforeEach {
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-finalization-{0}" -f [guid]::NewGuid())
        $script:TestHome = Join-Path $script:TestRoot 'home'
        $script:ToolRoot = Join-Path $script:TestHome 'dotnet-sdks'
        $script:ToolPath = Join-Path $script:ToolRoot 'isolated-dotnet-sdk.ps1'
        $script:Version = '99.0.100'
        $script:InstallDir = Join-Path $script:ToolRoot $script:Version
        $script:InstallerPath = Join-Path $script:TestRoot 'fake-installer.ps1'
        $script:OriginalHomeValue = [Environment]::GetEnvironmentVariable($script:HomeVariableName, 'Process')

        New-Item -ItemType Directory -Path $script:ToolRoot -Force | Out-Null
        Copy-Item -LiteralPath $script:ToolScript -Destination $script:ToolPath -Force
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:TestHome, 'Process')
        $env:ISOLATED_DOTNET_SDK_TOOL_PATH = $script:ToolPath
        $env:ISOLATED_DOTNET_SDK_FAKE_INSTALLER = $script:InstallerPath
        $env:ISOLATED_DOTNET_SDK_FAKE_HOST_ROOT = $script:FakeHostOutput
        $env:FAKE_DOTNET_SDK_VERSION = $script:Version

        Set-Content -LiteralPath $script:InstallerPath -Value @'
param([string]$Version, [string]$InstallDir, [switch]$NoPath)
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Copy-Item -Path (Join-Path $env:ISOLATED_DOTNET_SDK_FAKE_HOST_ROOT '*') -Destination $InstallDir -Recurse -Force
exit 0
'@
    }

    AfterEach {
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:OriginalHomeValue, 'Process')
        Remove-Item Env:ISOLATED_DOTNET_SDK_TOOL_PATH -ErrorAction SilentlyContinue
        Remove-Item Env:ISOLATED_DOTNET_SDK_FAKE_INSTALLER -ErrorAction SilentlyContinue
        Remove-Item Env:ISOLATED_DOTNET_SDK_FAKE_HOST_ROOT -ErrorAction SilentlyContinue
        Remove-Item Env:FAKE_DOTNET_SDK_VERSION -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'cleans transaction state when promotion fails' {
        $failureOutput = @(& pwsh -NoProfile -Command '
            function Get-FileHash {
                param([string]$LiteralPath, [string]$Algorithm)
                [pscustomobject]@{ Hash = "3bb07bc8025211836c1e4f9d3f6a044e55b1fb6eec518a6c78851d04e210442b" }
            }
            function Invoke-WebRequest {
                param($Uri, $OutFile)
                Copy-Item -LiteralPath $env:ISOLATED_DOTNET_SDK_FAKE_INSTALLER -Destination $OutFile -Force
            }
            function Move-Item {
                param([string]$LiteralPath, [string]$Destination, [switch]$WhatIf, [switch]$Confirm)
                throw "promotion-move-failed"
            }
            & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -Version 99.0.100 -Yes
        ' 6>&1 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        $text = $failureOutput -join [Environment]::NewLine
        $text | Should -Match 'Unable to promote isolated SDK 99\.0\.100 into'
        $text | Should -Match 'promotion-move-failed'
        $text | Should -Not -Match 'installation completed successfully'
        Test-Path -LiteralPath $script:InstallDir | Should -BeFalse
        @(Get-ChildItem -LiteralPath $script:ToolRoot -Directory -Filter '.install-99.0.100-*' -ErrorAction SilentlyContinue).Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $script:ToolRoot -File -Filter 'dotnet-install.*.ps1' -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'fails after successful promotion when helper cleanup fails' {
        $failureOutput = @(& pwsh -NoProfile -Command '
            function Get-FileHash {
                param([string]$LiteralPath, [string]$Algorithm)
                [pscustomobject]@{ Hash = "3bb07bc8025211836c1e4f9d3f6a044e55b1fb6eec518a6c78851d04e210442b" }
            }
            function Invoke-WebRequest {
                param($Uri, $OutFile)
                Copy-Item -LiteralPath $env:ISOLATED_DOTNET_SDK_FAKE_INSTALLER -Destination $OutFile -Force
            }
            function Remove-Item {
                param(
                    [string]$LiteralPath,
                    [switch]$Recurse,
                    [switch]$Force,
                    [switch]$WhatIf,
                    [switch]$Confirm
                )
                if ($LiteralPath -like "*dotnet-install.*.ps1") {
                    throw "cleanup-remove-failed"
                }
                Microsoft.PowerShell.Management\Remove-Item -LiteralPath $LiteralPath -Recurse:$Recurse -Force:$Force
            }
            & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -Version 99.0.100 -Yes
        ' 6>&1 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        $text = $failureOutput -join [Environment]::NewLine
        $text | Should -Match 'Unable to clean install helper'
        $text | Should -Match 'Isolated SDK 99\.0\.100 was installed, but transaction cleanup failed'
        $text | Should -Match 'cleanup-remove-failed'
        $text | Should -Not -Match 'installation completed successfully'
        Test-Path -LiteralPath (Join-Path $script:InstallDir 'dotnet.exe') | Should -BeTrue
        @(Get-ChildItem -LiteralPath $script:ToolRoot -File -Filter 'dotnet-install.*.ps1' -ErrorAction SilentlyContinue).Count | Should -Be 1
    }
}
