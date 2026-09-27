Describe 'PowerShell native install command failures' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:ToolScript = Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1'
        $script:HomeVariableName = if ($IsWindows) { 'USERPROFILE' } else { 'HOME' }
        $script:PwshPath = (Get-Command pwsh).Source
    }

    BeforeEach {
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-native-tests-{0}" -f [guid]::NewGuid())
        $script:TestHome = Join-Path $script:TestRoot 'home'
        $script:ToolRoot = Join-Path $script:TestHome 'dotnet-sdks'
        $script:ToolPath = Join-Path $script:ToolRoot 'isolated-dotnet-sdk.ps1'
        $script:Version = '99.0.100'
        $script:InstallDir = Join-Path $script:ToolRoot $script:Version
        $script:OriginalHomeValue = [Environment]::GetEnvironmentVariable($script:HomeVariableName, 'Process')

        New-Item -ItemType Directory -Path $script:ToolRoot -Force | Out-Null
        Copy-Item -LiteralPath $script:ToolScript -Destination $script:ToolPath -Force
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:TestHome, 'Process')
        $env:ISOLATED_DOTNET_SDK_TOOL_PATH = $script:ToolPath
        $env:ISOLATED_DOTNET_SDK_FAKE_INSTALLER = Join-Path $script:TestRoot 'fake-installer.ps1'
    }

    AfterEach {
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:OriginalHomeValue, 'Process')
        Remove-Item Env:ISOLATED_DOTNET_SDK_TOOL_PATH -ErrorAction SilentlyContinue
        Remove-Item Env:ISOLATED_DOTNET_SDK_FAKE_INSTALLER -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'fails closed when the existing isolated host probe exits nonzero' {
        New-Item -ItemType Directory -Path $script:InstallDir -Force | Out-Null
        Copy-Item -LiteralPath $script:PwshPath -Destination (Join-Path $script:InstallDir 'dotnet.exe') -Force

        $failureOutput = @(& pwsh -NoProfile -Command 'function Invoke-WebRequest { throw "continued-to-download" }; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -Version 99.0.100 -Yes' 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        ($failureOutput -join [Environment]::NewLine) | Should -Match 'Unable to inspect existing isolated SDK 99\.0\.100 with exit code -?[1-9][0-9]*\.'
        ($failureOutput -join [Environment]::NewLine) | Should -Not -Match 'continued-to-download'
        ($failureOutput -join [Environment]::NewLine) | Should -Not -Match 'installation completed successfully'
    }

    It 'reports installer failure before verification or success' {
        Set-Content -LiteralPath $env:ISOLATED_DOTNET_SDK_FAKE_INSTALLER -Value @'
param(
    [string]$Version,
    [string]$InstallDir,
    [switch]$NoPath
)
exit 73
'@

        $failureOutput = @(& pwsh -NoProfile -Command 'function Get-FileHash { param([string]$LiteralPath, [string]$Algorithm) [pscustomobject]@{ Hash = "3bb07bc8025211836c1e4f9d3f6a044e55b1fb6eec518a6c78851d04e210442b" } }; function Invoke-WebRequest { param($Uri, $OutFile) Copy-Item -LiteralPath $env:ISOLATED_DOTNET_SDK_FAKE_INSTALLER -Destination $OutFile -Force }; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -Version 99.0.100 -Yes' 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        ($failureOutput -join [Environment]::NewLine) | Should -Match 'dotnet-install failed for SDK 99\.0\.100 with exit code 73\.'
        ($failureOutput -join [Environment]::NewLine) | Should -Not -Match 'Verifying the isolated SDK'
        ($failureOutput -join [Environment]::NewLine) | Should -Not -Match 'installation completed successfully'
    }

    It 'reports post-install host failure as verification failure' {
        Set-Content -LiteralPath $env:ISOLATED_DOTNET_SDK_FAKE_INSTALLER -Value @'
param(
    [string]$Version,
    [string]$InstallDir,
    [switch]$NoPath
)
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Copy-Item -LiteralPath (Get-Command pwsh).Source -Destination (Join-Path $InstallDir 'dotnet.exe') -Force
exit 0
'@

        $failureOutput = @(& pwsh -NoProfile -Command 'function Get-FileHash { param([string]$LiteralPath, [string]$Algorithm) [pscustomobject]@{ Hash = "3bb07bc8025211836c1e4f9d3f6a044e55b1fb6eec518a6c78851d04e210442b" } }; function Invoke-WebRequest { param($Uri, $OutFile) Copy-Item -LiteralPath $env:ISOLATED_DOTNET_SDK_FAKE_INSTALLER -Destination $OutFile -Force }; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -Version 99.0.100 -Yes' 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        ($failureOutput -join [Environment]::NewLine) | Should -Match 'Unable to verify isolated SDK 99\.0\.100 with exit code -?[1-9][0-9]*\.'
        ($failureOutput -join [Environment]::NewLine) | Should -Not -Match 'SDK 99\.0\.100 was not found after installation\.'
        ($failureOutput -join [Environment]::NewLine) | Should -Not -Match 'installation completed successfully'
    }
}
