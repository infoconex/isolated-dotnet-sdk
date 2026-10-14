Describe 'PowerShell transactional SDK installation' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:ToolScript = Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1'
        $script:FixtureScript = Join-Path $PSScriptRoot 'sdk-payload-fixture.ps1'
        $script:HomeVariableName = if ($IsWindows) { 'USERPROFILE' } else { 'HOME' }
        $script:FakeHostOutput = $env:ISOLATED_DOTNET_SDK_SHARED_FAKE_HOST_ROOT
    }

    BeforeEach {
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-transaction-tests-{0}" -f [guid]::NewGuid())
        $script:TestHome = Join-Path $script:TestRoot 'home'
        $script:ToolRoot = Join-Path $script:TestHome 'dotnet-sdks'
        $script:ToolPath = Join-Path $script:ToolRoot 'isolated-dotnet-sdk.ps1'
        $script:Version = '99.0.100'
        $script:InstallDir = Join-Path $script:ToolRoot $script:Version
        $script:OriginalHomeValue = [Environment]::GetEnvironmentVariable($script:HomeVariableName, 'Process')
        $script:StagingTargetPath = Join-Path $script:TestHome 'staging-target.txt'
        $script:DownloadTargetPath = Join-Path $script:TestHome 'download-target.txt'
        $script:MetadataUrlTargetPath = Join-Path $script:TestHome 'metadata-url.txt'
        New-Item -ItemType Directory -Path $script:ToolRoot -Force | Out-Null
        Copy-Item -LiteralPath $script:ToolScript -Destination $script:ToolPath -Force
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:TestHome, 'Process')
        $env:ISOLATED_DOTNET_SDK_TOOL_PATH = $script:ToolPath
        $env:ISOLATED_DOTNET_SDK_PAYLOAD_FIXTURE = $script:FixtureScript
        $env:ISOLATED_DOTNET_SDK_FAKE_HOST_ROOT = $script:FakeHostOutput
        $env:FAKE_DOTNET_SDK_VERSION = $script:Version
        $env:SDK_TEST_STAGING_TARGET = $script:StagingTargetPath
        $env:SDK_TEST_DOWNLOAD_TARGET = $script:DownloadTargetPath
        $env:SDK_TEST_METADATA_URL_TARGET = $script:MetadataUrlTargetPath
        foreach ($name in @('FAKE_DOTNET_EXIT_CODE','FAKE_DOTNET_CREATE_CONFLICT','SDK_TEST_METADATA_FAILURE','SDK_TEST_PAYLOAD_FAILURE','SDK_TEST_EXTRACT_FAILURE','SDK_TEST_MISSING_HOST','SDK_TEST_CLEANUP_PATTERN','SDK_TEST_LEGACY_VERSION','FAKE_DOTNET_LEGACY_HOST','FAKE_DOTNET_LEGACY_BASE_PATH','FAKE_DOTNET_RESOLVED_VERSION','SDK_TEST_HASH_MISMATCH')) {
            Remove-Item "Env:$name" -ErrorAction SilentlyContinue
        }
    }

    AfterEach {
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:OriginalHomeValue, 'Process')
        foreach ($name in @('ISOLATED_DOTNET_SDK_TOOL_PATH','ISOLATED_DOTNET_SDK_PAYLOAD_FIXTURE','ISOLATED_DOTNET_SDK_FAKE_HOST_ROOT','FAKE_DOTNET_SDK_VERSION','FAKE_DOTNET_EXIT_CODE','FAKE_DOTNET_CREATE_CONFLICT','SDK_TEST_STAGING_TARGET','SDK_TEST_DOWNLOAD_TARGET','SDK_TEST_METADATA_FAILURE','SDK_TEST_PAYLOAD_FAILURE','SDK_TEST_EXTRACT_FAILURE','SDK_TEST_MISSING_HOST','SDK_TEST_CLEANUP_PATTERN','SDK_TEST_LEGACY_VERSION','FAKE_DOTNET_LEGACY_HOST','FAKE_DOTNET_LEGACY_BASE_PATH','FAKE_DOTNET_RESOLVED_VERSION','SDK_TEST_HASH_MISMATCH','SDK_TEST_METADATA_URL_TARGET')) {
            Remove-Item "Env:$name" -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'keeps valid existing exact SDK behavior and skips download' {
        New-Item -ItemType Directory -Path $script:InstallDir -Force | Out-Null
        Copy-Item -Path (Join-Path $script:FakeHostOutput '*') -Destination $script:InstallDir -Recurse -Force
        $sentinel = Join-Path $script:InstallDir 'sentinel.txt'
        Set-Content -LiteralPath $sentinel -Value 'preserve-existing'
        $successOutput = @(& pwsh -NoProfile -Command 'function Invoke-WebRequest { throw "continued-to-download" }; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -SdkVersion 99.0.100 -Yes' 2>&1)
        $LASTEXITCODE | Should -Be 0
        ($successOutput -join [Environment]::NewLine) | Should -Match 'Isolated SDK: Already installed'
        ($successOutput -join [Environment]::NewLine) | Should -Not -Match 'continued-to-download'
        (Get-Content -LiteralPath $sentinel -Raw).Trim() | Should -Be 'preserve-existing'
    }

    It 'uses operation-scoped metadata state on download failure' {
        $env:SDK_TEST_METADATA_FAILURE = 'metadata-download-failed'
        $failureOutput = @(& pwsh -NoProfile -Command '. $env:ISOLATED_DOTNET_SDK_PAYLOAD_FIXTURE; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -SdkVersion 99.0.100 -Yes' 2>&1)
        $LASTEXITCODE | Should -Not -Be 0
        $downloadTarget = (Get-Content -LiteralPath $script:DownloadTargetPath -Raw).Trim()
        $downloadTarget | Should -Match ([regex]::Escape($script:ToolRoot) + '[\\/]\.release-metadata-99\.0\.100-[^\\/]+\.json$')
        Test-Path -LiteralPath $downloadTarget | Should -BeFalse
        ($failureOutput -join [Environment]::NewLine) | Should -Match 'metadata-download-failed'
    }

    It 'preserves a pre-existing non-valid destination and fails before download' {
        New-Item -ItemType Directory -Path $script:InstallDir -Force | Out-Null
        $sentinel = Join-Path $script:InstallDir 'sentinel.txt'
        Set-Content -LiteralPath $sentinel -Value 'preserve-me'
        $failureOutput = @(& pwsh -NoProfile -Command 'function Invoke-WebRequest { throw "continued-to-download" }; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -SdkVersion 99.0.100 -Yes' 2>&1)
        $LASTEXITCODE | Should -Not -Be 0
        $text = $failureOutput -join [Environment]::NewLine
        $text | Should -Match 'destination already exists'
        $text | Should -Not -Match 'continued-to-download'
        (Get-Content -LiteralPath $sentinel -Raw).Trim() | Should -Be 'preserve-me'
    }

    It 'uses staging for extraction failure and cleans the failed attempt' {
        $env:SDK_TEST_EXTRACT_FAILURE = 'extract-failed'
        $failureOutput = @(& pwsh -NoProfile -Command '. $env:ISOLATED_DOTNET_SDK_PAYLOAD_FIXTURE; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -SdkVersion 99.0.100 -Yes' 2>&1)
        $LASTEXITCODE | Should -Not -Be 0
        $text = $failureOutput -join [Environment]::NewLine
        $text | Should -Match 'Unable to extract the verified \.NET SDK 99\.0\.100 payload'
        $text | Should -Match 'extract-failed'
        Test-Path -LiteralPath $script:InstallDir | Should -BeFalse
        @(Get-ChildItem -LiteralPath $script:ToolRoot -Directory -Filter '.install-99.0.100-*' -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'reports cleanup failure without masking extraction failure' {
        $env:SDK_TEST_EXTRACT_FAILURE = 'extract-failed'
        $env:SDK_TEST_CLEANUP_PATTERN = '.sdk-payload-'
        $failureOutput = @(& pwsh -NoProfile -Command '. $env:ISOLATED_DOTNET_SDK_PAYLOAD_FIXTURE; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -SdkVersion 99.0.100 -Yes' 6>&1 2>&1)
        $LASTEXITCODE | Should -Not -Be 0
        $text = $failureOutput -join [Environment]::NewLine
        $text | Should -Match 'Unable to extract the verified \.NET SDK 99\.0\.100 payload'
        $text | Should -Match 'Unable to clean install transaction file'
        $text | Should -Match 'cleanup-remove-failed'
        $text | Should -Not -Match 'installation completed successfully'
    }

    It 'cleans staging when extraction does not produce a host' {
        $env:SDK_TEST_MISSING_HOST = '1'
        $failureOutput = @(& pwsh -NoProfile -Command '. $env:ISOLATED_DOTNET_SDK_PAYLOAD_FIXTURE; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -SdkVersion 99.0.100 -Yes' 2>&1)
        $LASTEXITCODE | Should -Not -Be 0
        ($failureOutput -join [Environment]::NewLine) | Should -Match 'isolated dotnet executable was not found'
        $target = (Get-Content -LiteralPath $script:StagingTargetPath -Raw).Trim()
        Test-Path -LiteralPath $target | Should -BeFalse
        Test-Path -LiteralPath $script:InstallDir | Should -BeFalse
    }

    It 'blocks promotion when the staged host exits nonzero' {
        $env:FAKE_DOTNET_EXIT_CODE = '74'
        $failureOutput = @(& pwsh -NoProfile -Command '. $env:ISOLATED_DOTNET_SDK_PAYLOAD_FIXTURE; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -SdkVersion 99.0.100 -Yes' 2>&1)
        $LASTEXITCODE | Should -Not -Be 0
        ($failureOutput -join [Environment]::NewLine) | Should -Match 'Unable to verify isolated SDK 99\.0\.100 with exit code 74\.'
        Test-Path -LiteralPath $script:InstallDir | Should -BeFalse
    }

    It 'blocks promotion when staged inventory omits the requested version' {
        $env:FAKE_DOTNET_SDK_VERSION = '98.0.100'
        $failureOutput = @(& pwsh -NoProfile -Command '. $env:ISOLATED_DOTNET_SDK_PAYLOAD_FIXTURE; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -SdkVersion 99.0.100 -Yes' 2>&1)
        $LASTEXITCODE | Should -Not -Be 0
        ($failureOutput -join [Environment]::NewLine) | Should -Match 'SDK 99\.0\.100 was not found after installation\.'
        Test-Path -LiteralPath $script:InstallDir | Should -BeFalse
    }

    It 'preserves a destination that appears before promotion' {
        $env:FAKE_DOTNET_CREATE_CONFLICT = $script:InstallDir
        $failureOutput = @(& pwsh -NoProfile -Command '. $env:ISOLATED_DOTNET_SDK_PAYLOAD_FIXTURE; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -SdkVersion 99.0.100 -Yes' 2>&1)
        $LASTEXITCODE | Should -Not -Be 0
        ($failureOutput -join [Environment]::NewLine) | Should -Match 'destination already exists'
        (Get-Content -LiteralPath (Join-Path $script:InstallDir 'sentinel.txt') -Raw).Trim() | Should -Be 'preserve-conflict'
    }

    It 'promotes only a verified staged installation' {
        $successOutput = @(& pwsh -NoProfile -Command '. $env:ISOLATED_DOTNET_SDK_PAYLOAD_FIXTURE; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -SdkVersion 99.0.100 -Yes' 2>&1)
        $LASTEXITCODE | Should -Be 0
        $text = $successOutput -join [Environment]::NewLine
        $text | Should -Match 'Extracting verified \.NET SDK 99\.0\.100 payload'
        $text | Should -Match 'Isolated SDK installation completed successfully\.'
        Test-Path -LiteralPath (Join-Path $script:InstallDir 'dotnet.exe') | Should -BeTrue
        @(Get-ChildItem -LiteralPath $script:ToolRoot -Filter '.sdk-payload-*' -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'retries deterministically after a failed clean-start attempt' {
        $env:SDK_TEST_EXTRACT_FAILURE = 'extract-failed'
        @(& pwsh -NoProfile -Command '. $env:ISOLATED_DOTNET_SDK_PAYLOAD_FIXTURE; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -SdkVersion 99.0.100 -Yes' 2>&1) | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
        Test-Path -LiteralPath $script:InstallDir | Should -BeFalse
        Remove-Item Env:SDK_TEST_EXTRACT_FAILURE
        $successOutput = @(& pwsh -NoProfile -Command '. $env:ISOLATED_DOTNET_SDK_PAYLOAD_FIXTURE; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -SdkVersion 99.0.100 -Yes' 2>&1)
        $LASTEXITCODE | Should -Be 0
        ($successOutput -join [Environment]::NewLine) | Should -Match 'installation completed successfully'
        Test-Path -LiteralPath (Join-Path $script:InstallDir 'dotnet.exe') | Should -BeTrue
    }

    It 'verifies and promotes historical SDK 1.1.14 using exact version and isolated Base Path' {
        $env:SDK_TEST_LEGACY_VERSION = '1.1.14'
        $env:FAKE_DOTNET_LEGACY_HOST = 'true'
        $env:FAKE_DOTNET_SDK_VERSION = '1.1.14'
        $target = Join-Path $script:ToolRoot '1.1.14'

        $successOutput = @(& pwsh -NoProfile -Command '. $env:ISOLATED_DOTNET_SDK_PAYLOAD_FIXTURE; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -SdkVersion 1.1.14 -Yes' 2>&1)
        $LASTEXITCODE | Should -Be 0
        ($successOutput -join [Environment]::NewLine) | Should -Match 'Isolated SDK installation completed successfully'
        Test-Path -LiteralPath (Join-Path $target 'dotnet.exe') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path (Join-Path $target 'sdk') '1.1.14') | Should -BeTrue
        @(Get-ChildItem -LiteralPath $script:ToolRoot -Filter '.sdk-host-verify-*' -ErrorAction SilentlyContinue).Count | Should -Be 0

        $secondOutput = @(& pwsh -NoProfile -Command 'function Invoke-WebRequest { throw "unexpected-download" }; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -SdkVersion 1.1.14 -Yes' 2>&1)
        $LASTEXITCODE | Should -Be 0
        ($secondOutput -join [Environment]::NewLine) | Should -Match 'Isolated SDK: Already installed'
        ($secondOutput -join [Environment]::NewLine) | Should -Not -Match 'unexpected-download'
    }

    It 'refuses legacy SDK promotion when the host reports another SDK version' {
        $env:SDK_TEST_LEGACY_VERSION = '1.1.14'
        $env:FAKE_DOTNET_LEGACY_HOST = 'true'
        $env:FAKE_DOTNET_SDK_VERSION = '1.1.14'
        $env:FAKE_DOTNET_RESOLVED_VERSION = '1.1.13'
        $output = @(& pwsh -NoProfile -Command '. $env:ISOLATED_DOTNET_SDK_PAYLOAD_FIXTURE; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -SdkVersion 1.1.14 -Yes' 2>&1)
        $LASTEXITCODE | Should -Not -Be 0
        ($output -join [Environment]::NewLine) | Should -Match 'legacy host did not report the requested exact SDK version'
        Test-Path -LiteralPath (Join-Path $script:ToolRoot '1.1.14') | Should -BeFalse
        @(Get-ChildItem -LiteralPath $script:ToolRoot -Filter '.sdk-host-verify-*' -ErrorAction SilentlyContinue).Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $script:ToolRoot -Filter '.install-1.1.14-*' -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'refuses legacy SDK promotion when the host SDK Base Path is external' {
        $env:SDK_TEST_LEGACY_VERSION = '1.1.14'
        $env:FAKE_DOTNET_LEGACY_HOST = 'true'
        $env:FAKE_DOTNET_SDK_VERSION = '1.1.14'
        $env:FAKE_DOTNET_LEGACY_BASE_PATH = $script:TestRoot
        $output = @(& pwsh -NoProfile -Command '. $env:ISOLATED_DOTNET_SDK_PAYLOAD_FIXTURE; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -SdkVersion 1.1.14 -Yes' 2>&1)
        $LASTEXITCODE | Should -Not -Be 0
        ($output -join [Environment]::NewLine) | Should -Match 'legacy host SDK Base Path does not match the isolated directory'
        Test-Path -LiteralPath (Join-Path $script:ToolRoot '1.1.14') | Should -BeFalse
        @(Get-ChildItem -LiteralPath $script:ToolRoot -Filter '.sdk-host-verify-*' -ErrorAction SilentlyContinue).Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $script:ToolRoot -Filter '.install-1.1.14-*' -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'installs historical SDK 1.0.4 with published SHA-256 before promotion' {
        $env:SDK_TEST_LEGACY_VERSION = '1.0.4'
        $env:FAKE_DOTNET_LEGACY_HOST = 'true'
        $env:FAKE_DOTNET_SDK_VERSION = '1.0.4'
        $target = Join-Path $script:ToolRoot '1.0.4'
        $output = @(& pwsh -NoProfile -Command '. $env:ISOLATED_DOTNET_SDK_PAYLOAD_FIXTURE; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -SdkVersion 1.0.4 -Yes' 2>&1)
        $LASTEXITCODE | Should -Be 0
        ($output -join [Environment]::NewLine) | Should -Match 'Isolated SDK installation completed successfully'
        Test-Path -LiteralPath (Join-Path $target 'dotnet.exe') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path (Join-Path $target 'sdk') '1.0.4') | Should -BeTrue
    }

    It 'rejects a mismatched historical SHA-256 archive before extraction' {
        $env:SDK_TEST_LEGACY_VERSION = '1.0.4'
        $env:FAKE_DOTNET_LEGACY_HOST = 'true'
        $env:FAKE_DOTNET_SDK_VERSION = '1.0.4'
        $env:SDK_TEST_HASH_MISMATCH = '1'
        $output = @(& pwsh -NoProfile -Command '. $env:ISOLATED_DOTNET_SDK_PAYLOAD_FIXTURE; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -SdkVersion 1.0.4 -Yes' 2>&1)
        $LASTEXITCODE | Should -Not -Be 0
        ($output -join [Environment]::NewLine) | Should -Match 'Integrity verification failed'
        Test-Path -LiteralPath (Join-Path $script:ToolRoot '1.0.4') | Should -BeFalse
        @(Get-ChildItem -LiteralPath $script:ToolRoot -Filter '.sdk-payload-1.0.4-*' -ErrorAction SilentlyContinue).Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $script:ToolRoot -Filter '.install-1.0.4-*' -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'maps early 2.1 SDK builds to Microsoft channel 2.0 and verifies the staged host without --list-sdks' -ForEach @(
        @{ Version = '2.1.4' }
        @{ Version = '2.1.105' }
        @{ Version = '2.1.202' }
    ) {
        $env:SDK_TEST_LEGACY_VERSION = $Version
        $env:FAKE_DOTNET_LEGACY_HOST = 'true'
        $env:FAKE_DOTNET_SDK_VERSION = $Version
        $output = @(& pwsh -NoProfile -Command '. $env:ISOLATED_DOTNET_SDK_PAYLOAD_FIXTURE; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -SdkVersion $env:SDK_TEST_LEGACY_VERSION -Yes' 2>&1)
        $LASTEXITCODE | Should -Be 0
        ($output -join [Environment]::NewLine) | Should -Match 'Isolated SDK installation completed successfully'
        (Get-Content -LiteralPath $script:MetadataUrlTargetPath -Raw).Trim() |
            Should -Be 'https://builds.dotnet.microsoft.com/dotnet/release-metadata/2.0/releases.json'
        Test-Path -LiteralPath (Join-Path (Join-Path $script:ToolRoot $Version) 'dotnet.exe') |
            Should -BeTrue
        @(Get-ChildItem -LiteralPath $script:ToolRoot -Filter '.sdk-host-verify-*' -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'maps SDK 2.1.300 to channel 2.1 and retains modern host inventory validation' {
        $env:SDK_TEST_LEGACY_VERSION = '2.1.300'
        $env:FAKE_DOTNET_SDK_VERSION = '2.1.300'
        $output = @(& pwsh -NoProfile -Command '. $env:ISOLATED_DOTNET_SDK_PAYLOAD_FIXTURE; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -SdkVersion 2.1.300 -Yes' 2>&1)
        $LASTEXITCODE | Should -Be 0
        ($output -join [Environment]::NewLine) | Should -Match 'Isolated SDK installation completed successfully'
        (Get-Content -LiteralPath $script:MetadataUrlTargetPath -Raw).Trim() |
            Should -Be 'https://builds.dotnet.microsoft.com/dotnet/release-metadata/2.1/releases.json'
    }

    It 'verifies SDK 2.0.3 with exact staged version and isolated Base Path without --list-sdks' {
        $env:SDK_TEST_LEGACY_VERSION = '2.0.3'
        $env:FAKE_DOTNET_LEGACY_HOST = 'true'
        $env:FAKE_DOTNET_SDK_VERSION = '2.0.3'
        $output = @(& pwsh -NoProfile -Command '. $env:ISOLATED_DOTNET_SDK_PAYLOAD_FIXTURE; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -SdkVersion 2.0.3 -Yes' 2>&1)
        $LASTEXITCODE | Should -Be 0
        ($output -join [Environment]::NewLine) | Should -Match 'Isolated SDK installation completed successfully'
        Test-Path -LiteralPath (Join-Path (Join-Path $script:ToolRoot '2.0.3') 'sdk/2.0.3') |
            Should -BeTrue
        (Get-Content -LiteralPath $script:MetadataUrlTargetPath -Raw).Trim() |
            Should -Be 'https://builds.dotnet.microsoft.com/dotnet/release-metadata/2.0/releases.json'
    }

    It 'rejects a staged 2.0.3 host that resolves the system SDK 10.0.402 and cleans the transaction' {
        $env:SDK_TEST_LEGACY_VERSION = '2.0.3'
        $env:FAKE_DOTNET_LEGACY_HOST = 'true'
        $env:FAKE_DOTNET_SDK_VERSION = '2.0.3'
        $env:FAKE_DOTNET_RESOLVED_VERSION = '10.0.402'
        $output = @(& pwsh -NoProfile -Command '. $env:ISOLATED_DOTNET_SDK_PAYLOAD_FIXTURE; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -SdkVersion 2.0.3 -Yes' 2>&1)
        $LASTEXITCODE | Should -Not -Be 0
        ($output -join [Environment]::NewLine) | Should -Match 'legacy host did not report the requested exact SDK version'
        Test-Path -LiteralPath (Join-Path $script:ToolRoot '2.0.3') | Should -BeFalse
        @(Get-ChildItem -LiteralPath $script:ToolRoot -Filter '.install-2.0.3-*' -ErrorAction SilentlyContinue).Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $script:ToolRoot -Filter '.sdk-host-verify-2.0.3-*' -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'rejects a staged 2.1.105 host that resolves an external SDK Base Path' {
        $env:SDK_TEST_LEGACY_VERSION = '2.1.105'
        $env:FAKE_DOTNET_LEGACY_HOST = 'true'
        $env:FAKE_DOTNET_SDK_VERSION = '2.1.105'
        $env:FAKE_DOTNET_LEGACY_BASE_PATH = $script:TestRoot
        $output = @(& pwsh -NoProfile -Command '. $env:ISOLATED_DOTNET_SDK_PAYLOAD_FIXTURE; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -SdkVersion 2.1.105 -Yes' 2>&1)
        $LASTEXITCODE | Should -Not -Be 0
        ($output -join [Environment]::NewLine) | Should -Match 'legacy host SDK Base Path does not match the isolated directory'
        Test-Path -LiteralPath (Join-Path $script:ToolRoot '2.1.105') | Should -BeFalse
    }
}
