Describe 'PowerShell installer integrity' {
    BeforeEach {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:ToolScript = Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1'
        $script:HomeVariableName = if ($IsWindows) { 'USERPROFILE' } else { 'HOME' }
        $script:OriginalHomeValue = [Environment]::GetEnvironmentVariable($script:HomeVariableName, 'Process')
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-integrity-tests-{0}" -f [guid]::NewGuid())
        $script:TestHome = Join-Path $script:TestRoot 'home'
        $script:ToolRoot = Join-Path $script:TestHome 'dotnet-sdks'
        $script:ToolPath = Join-Path $script:ToolRoot 'isolated-dotnet-sdk.ps1'
        $script:Version = '99.0.100'
        $script:InstallDir = Join-Path $script:ToolRoot $script:Version
        $script:UrlLog = Join-Path $script:TestHome 'installer-url.txt'
        $script:ExecutedMarker = Join-Path $script:TestHome 'helper-executed.txt'
        $script:ExpectedUrl = 'https://raw.githubusercontent.com/dotnet/install-scripts/da3ce11ba63f3dbb0fb835d41bda2665d5c48e84/src/dotnet-install.ps1'

        New-Item -ItemType Directory -Path $script:ToolRoot -Force | Out-Null
        Copy-Item -LiteralPath $script:ToolScript -Destination $script:ToolPath -Force
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:TestHome, 'Process')
        $env:ISOLATED_DOTNET_SDK_TOOL_PATH = $script:ToolPath
        $env:ISOLATED_DOTNET_SDK_URL_LOG = $script:UrlLog
        $env:ISOLATED_DOTNET_SDK_EXECUTED_MARKER = $script:ExecutedMarker
    }

    AfterEach {
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:OriginalHomeValue, 'Process')
        Remove-Item Env:ISOLATED_DOTNET_SDK_TOOL_PATH -ErrorAction SilentlyContinue
        Remove-Item Env:ISOLATED_DOTNET_SDK_URL_LOG -ErrorAction SilentlyContinue
        Remove-Item Env:ISOLATED_DOTNET_SDK_EXECUTED_MARKER -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'rejects a pinned Microsoft installer hash mismatch before execution' {
        $failureOutput = @(& pwsh -NoProfile -Command '
function Invoke-WebRequest {
    param($Uri, $OutFile)
    Set-Content -LiteralPath $env:ISOLATED_DOTNET_SDK_URL_LOG -Value ([string]$Uri)
    Set-Content -LiteralPath $OutFile -Value @"
param([string]`$Version, [string]`$InstallDir, [switch]`$NoPath)
Set-Content -LiteralPath `$env:ISOLATED_DOTNET_SDK_EXECUTED_MARKER -Value executed
exit 73
"@
}
function Get-FileHash {
    param([string]$LiteralPath, [string]$Algorithm)
    [pscustomobject]@{ Hash = ("0" * 64) }
}
& $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -Version 99.0.100 -Yes
' 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        (Get-Content -LiteralPath $script:UrlLog -Raw).Trim() | Should -Be $script:ExpectedUrl
        ($failureOutput -join [Environment]::NewLine) |
            Should -Match "Integrity verification failed for Microsoft's dotnet-install\.ps1 script\."
        Test-Path -LiteralPath $script:ExecutedMarker | Should -BeFalse
        Test-Path -LiteralPath $script:InstallDir | Should -BeFalse
        @(Get-ChildItem -LiteralPath $script:ToolRoot -Filter 'dotnet-install.*.ps1' -ErrorAction SilentlyContinue).Count |
            Should -Be 0
    }

    It 'records immutable Microsoft provenance in repository integrity config' {
        $config = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.config/remote-artifacts.json') -Raw |
            ConvertFrom-Json

        $config.dotnetInstall.commit | Should -Be 'da3ce11ba63f3dbb0fb835d41bda2665d5c48e84'
        $config.dotnetInstall.powershell.blob | Should -Be '0942202517385e2c756d3b32087291c48d078713'
        $config.dotnetInstall.powershell.sha256 | Should -Be '3bb07bc8025211836c1e4f9d3f6a044e55b1fb6eec518a6c78851d04e210442b'
        $config.dotnetInstall.powershell.url | Should -Be $script:ExpectedUrl
    }
}
