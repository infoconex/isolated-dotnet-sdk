Describe 'PowerShell native install command failures' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:ToolScript = Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1'
        $script:FixtureScript = Join-Path $PSScriptRoot 'sdk-payload-fixture.ps1'
        $script:HomeVariableName = if ($IsWindows) { 'USERPROFILE' } else { 'HOME' }
        $script:PwshPath = (Get-Command pwsh).Source
        $script:FakeHostOutput = $env:ISOLATED_DOTNET_SDK_SHARED_FAKE_HOST_ROOT
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
        $env:ISOLATED_DOTNET_SDK_PAYLOAD_FIXTURE = $script:FixtureScript
        $env:ISOLATED_DOTNET_SDK_FAKE_HOST_ROOT = $script:FakeHostOutput
        $env:FAKE_DOTNET_SDK_VERSION = $script:Version
        Remove-Item Env:FAKE_DOTNET_EXIT_CODE -ErrorAction SilentlyContinue
        Remove-Item Env:SDK_TEST_PAYLOAD_FAILURE -ErrorAction SilentlyContinue
        Remove-Item Env:SDK_TEST_EXTRACT_FAILURE -ErrorAction SilentlyContinue
    }

    AfterEach {
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:OriginalHomeValue, 'Process')
        foreach ($name in @('ISOLATED_DOTNET_SDK_TOOL_PATH','ISOLATED_DOTNET_SDK_PAYLOAD_FIXTURE','ISOLATED_DOTNET_SDK_FAKE_HOST_ROOT','FAKE_DOTNET_SDK_VERSION','FAKE_DOTNET_EXIT_CODE','SDK_TEST_PAYLOAD_FAILURE','SDK_TEST_EXTRACT_FAILURE')) {
            Remove-Item "Env:$name" -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'fails closed when the existing isolated host probe exits nonzero' {
        New-Item -ItemType Directory -Path $script:InstallDir -Force | Out-Null
        Copy-Item -LiteralPath $script:PwshPath -Destination (Join-Path $script:InstallDir 'dotnet.exe') -Force
        $failureOutput = @(& pwsh -NoProfile -Command 'function Invoke-WebRequest { throw "continued-to-download" }; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -Version 99.0.100 -Yes' 2>&1)
        $LASTEXITCODE | Should -Not -Be 0
        $text = $failureOutput -join [Environment]::NewLine
        $text | Should -Match 'Unable to inspect existing isolated SDK 99\.0\.100 with exit code -?[1-9][0-9]*\.'
        $text | Should -Not -Match 'continued-to-download'
        $text | Should -Not -Match 'installation completed successfully'
    }

    It 'reports payload download failure before verification or success' {
        $env:SDK_TEST_PAYLOAD_FAILURE = 'payload-download-failed'
        $failureOutput = @(& pwsh -NoProfile -Command '. $env:ISOLATED_DOTNET_SDK_PAYLOAD_FIXTURE; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -Version 99.0.100 -Yes' 2>&1)
        $LASTEXITCODE | Should -Not -Be 0
        $text = $failureOutput -join [Environment]::NewLine
        $text | Should -Match 'Unable to download the \.NET SDK 99\.0\.100 payload'
        $text | Should -Match 'payload-download-failed'
        $text | Should -Not -Match 'Extracting verified'
        $text | Should -Not -Match 'installation completed successfully'
    }

    It 'reports post-extraction host failure as verification failure' {
        $env:FAKE_DOTNET_EXIT_CODE = '74'
        $failureOutput = @(& pwsh -NoProfile -Command '. $env:ISOLATED_DOTNET_SDK_PAYLOAD_FIXTURE; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -Version 99.0.100 -Yes' 2>&1)
        $LASTEXITCODE | Should -Not -Be 0
        $text = $failureOutput -join [Environment]::NewLine
        $text | Should -Match 'Unable to verify isolated SDK 99\.0\.100 with exit code 74\.'
        $text | Should -Not -Match 'SDK 99\.0\.100 was not found after installation\.'
        $text | Should -Not -Match 'installation completed successfully'
    }
}
