Describe 'PowerShell installation finalization failures' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:ToolScript = Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1'
        $script:FixtureScript = Join-Path $PSScriptRoot 'sdk-payload-fixture.ps1'
        $script:HomeVariableName = if ($IsWindows) { 'USERPROFILE' } else { 'HOME' }
        $script:FakeHostOutput = $env:ISOLATED_DOTNET_SDK_SHARED_FAKE_HOST_ROOT
    }

    BeforeEach {
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-finalization-{0}" -f [guid]::NewGuid())
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
        $env:ISOLATED_DOTNET_SDK_PAYLOAD_FIXTURE = $script:FixtureScript
        $env:ISOLATED_DOTNET_SDK_FAKE_HOST_ROOT = $script:FakeHostOutput
        $env:FAKE_DOTNET_SDK_VERSION = $script:Version
        Remove-Item Env:SDK_TEST_PROMOTION_FAILURE -ErrorAction SilentlyContinue
        Remove-Item Env:SDK_TEST_CLEANUP_PATTERN -ErrorAction SilentlyContinue
    }

    AfterEach {
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:OriginalHomeValue, 'Process')
        foreach ($name in @('ISOLATED_DOTNET_SDK_TOOL_PATH','ISOLATED_DOTNET_SDK_PAYLOAD_FIXTURE','ISOLATED_DOTNET_SDK_FAKE_HOST_ROOT','FAKE_DOTNET_SDK_VERSION','SDK_TEST_PROMOTION_FAILURE','SDK_TEST_CLEANUP_PATTERN')) {
            Remove-Item "Env:$name" -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'cleans transaction state when promotion fails' {
        $env:SDK_TEST_PROMOTION_FAILURE = 'promotion-move-failed'
        $failureOutput = @(& pwsh -NoProfile -Command '. $env:ISOLATED_DOTNET_SDK_PAYLOAD_FIXTURE; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -SdkVersion 99.0.100 -Yes' 6>&1 2>&1)
        $LASTEXITCODE | Should -Not -Be 0
        $text = $failureOutput -join [Environment]::NewLine
        $text | Should -Match 'Unable to promote isolated SDK 99\.0\.100 into'
        $text | Should -Match 'promotion-move-failed'
        $text | Should -Not -Match 'installation completed successfully'
        Test-Path -LiteralPath $script:InstallDir | Should -BeFalse
        @(Get-ChildItem -LiteralPath $script:ToolRoot -Directory -Filter '.install-99.0.100-*' -ErrorAction SilentlyContinue).Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $script:ToolRoot -File -Filter '.sdk-payload-*' -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'fails after successful promotion when payload cleanup fails' {
        $env:SDK_TEST_CLEANUP_PATTERN = '.sdk-payload-'
        $failureOutput = @(& pwsh -NoProfile -Command '. $env:ISOLATED_DOTNET_SDK_PAYLOAD_FIXTURE; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -SdkVersion 99.0.100 -Yes' 6>&1 2>&1)
        $LASTEXITCODE | Should -Not -Be 0
        $text = $failureOutput -join [Environment]::NewLine
        $text | Should -Match 'Unable to clean install transaction file'
        $text | Should -Match 'Isolated SDK 99\.0\.100 was installed, but transaction cleanup failed'
        $text | Should -Match 'cleanup-remove-failed'
        $text | Should -Not -Match 'installation completed successfully'
        Test-Path -LiteralPath (Join-Path $script:InstallDir 'dotnet.exe') | Should -BeTrue
        @(Get-ChildItem -LiteralPath $script:ToolRoot -File -Filter '.sdk-payload-*' -ErrorAction SilentlyContinue).Count | Should -Be 1
    }
}
