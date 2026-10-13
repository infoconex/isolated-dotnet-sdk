Describe 'PowerShell isolated SDK verification' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:ToolScript = Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1'
        $script:HomeVariableName = if ($IsWindows) { 'USERPROFILE' } else { 'HOME' }

        function Install-TestTool {
            Copy-Item $script:ToolScript $script:SourceCopy -Force
            & pwsh -NoProfile -File $script:SourceCopy -Action List *> $null
            $LASTEXITCODE | Should -Be 0
        }

        function Install-FakeIsolatedHost {
            param(
                [Alias('SdkVersion')]
                [string]$Version = '99.0.100',
                [string]$ReportedVersion = '99.0.100'
            )

            $installDirectory = Join-Path $script:ToolRoot $Version
            New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
            Copy-Item `
                -Path (Join-Path $env:ISOLATED_DOTNET_SDK_SHARED_FAKE_HOST_ROOT '*') `
                -Destination $installDirectory `
                -Recurse `
                -Force
            New-Item -ItemType Directory -Path (Join-Path $installDirectory 'sdk') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $installDirectory 'shared/Microsoft.NETCore.App') -Force | Out-Null
            $env:FAKE_DOTNET_SDK_VERSION = $ReportedVersion
            return $installDirectory
        }

        function Invoke-VerifyTool {
            param([string]$Version = '')
            $env:VERIFY_TARGET_VERSION = $Version
            $env:VERIFY_TOOL_PATH = $script:ToolPath
            $command = @'
function Invoke-RestMethod {
    param([string]$Uri)
    if ($env:VERIFY_METADATA_ROOT) {
        $name = if ($Uri -like "*releases-index.json") { "index.json" } else { "channel.json" }
        $path = Join-Path $env:VERIFY_METADATA_ROOT $name
        if (Test-Path -LiteralPath $path) {
            return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        }
    }
    throw "Synthetic Microsoft metadata unavailable"
}
& $env:VERIFY_TOOL_PATH -Action Verify -SdkVersion $env:VERIFY_TARGET_VERSION
'@
            $lines = @(& pwsh -NoProfile -Command $command 2>&1)
            $script:VerifyExitCode = $LASTEXITCODE
            return $lines
        }
    }

    BeforeEach {
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-verify-tests-{0}" -f [guid]::NewGuid())
        $script:TestHome = Join-Path $script:TestRoot 'home'
        $script:ToolRoot = Join-Path $script:TestHome 'dotnet-sdks'
        $script:ToolPath = Join-Path $script:ToolRoot 'isolated-dotnet-sdk.ps1'
        $script:SourceCopy = Join-Path $script:TestRoot 'isolated-dotnet-sdk-source.ps1'
        $script:OriginalHomeValue = [Environment]::GetEnvironmentVariable($script:HomeVariableName, 'Process')

        New-Item -ItemType Directory -Path $script:TestHome -Force | Out-Null
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:TestHome, 'Process')
        Install-TestTool
    }

    AfterEach {
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:OriginalHomeValue, 'Process')
        Remove-Item Env:FAKE_DOTNET_EXIT_CODE -ErrorAction SilentlyContinue
        foreach ($name in @('FAKE_DOTNET_SDK_VERSION', 'FAKE_DOTNET_SDK_ORIGIN', 'FAKE_DOTNET_RESOLVED_VERSION', 'FAKE_DOTNET_EXPECT_MULTILEVEL_LOOKUP', 'FAKE_DOTNET_FORBIDDEN_WORK_DIR', 'VERIFY_METADATA_ROOT', 'VERIFY_TOOL_PATH', 'VERIFY_TARGET_VERSION', 'FAKE_DOTNET_EXTRA_RUNTIME_ROOT', 'FAKE_DOTNET_LEGACY_INFO')) {
            Remove-Item "Env:$name" -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'reports a healthy exact isolated SDK without mutating it' {
        $version = '99.0.100'
        $installDirectory = Install-FakeIsolatedHost -SdkVersion $version -ReportedVersion $version
        $sentinelPath = Join-Path $installDirectory 'verify-sentinel.txt'
        Set-Content -LiteralPath $sentinelPath -Value 'preserve-me' -NoNewline
        $fileCountBefore = @(Get-ChildItem -LiteralPath $installDirectory -File -Recurse -Force).Count

        $verifyOutput = @(Invoke-VerifyTool -Version $version)

        $script:VerifyExitCode | Should -Be 0
        ($verifyOutput -join [Environment]::NewLine) | Should -Match "Isolated SDK $([regex]::Escape($version)) verified successfully\."
        $outputText = $verifyOutput -join [Environment]::NewLine
        $outputText | Should -Match 'SDK information:'
        $outputText | Should -Match 'SDK version\s+99\.0\.100'
        $outputText | Should -Match 'Installed components:'
        $outputText | Should -Match 'Host version\s+99\.0\.9'
        $outputText | Should -Match 'Architecture\s+x64'
        $outputText | Should -Match 'Runtime identifier\s+win10-x64'
        $outputText | Should -Match 'Microsoft\.NETCore\.App\s+99\.0\.9'
        $outputText | Should -Match 'SDK inventory\s+OK\s+Exact SDK found in isolated installation'
        $outputText | Should -Match 'SDK resolution\s+OK\s+Correct SDK selected'
        $outputText | Should -Not -Match '(?m)^Location:'
        (Get-Content -LiteralPath $sentinelPath -Raw) | Should -Be 'preserve-me'
        @(Get-ChildItem -LiteralPath $installDirectory -File -Recurse -Force).Count | Should -Be $fileCountBefore
    }

    It 'reads legacy Host information and infers architecture from RID' {
        $version = '2.2.207'
        Install-FakeIsolatedHost -Version $version -ReportedVersion $version | Out-Null
        $env:FAKE_DOTNET_LEGACY_INFO = 'true'

        $verifyOutput = @(Invoke-VerifyTool -Version $version)

        $script:VerifyExitCode | Should -Be 0
        $outputText = $verifyOutput -join [Environment]::NewLine
        $outputText | Should -Match 'Host version\s+99\.0\.9'
        $outputText | Should -Match 'Architecture\s+x64'
        $outputText | Should -Match 'Runtime identifier\s+win10-x64'
        $outputText | Should -Match 'Isolated SDK 2\.2\.207 verified successfully'
    }

    It 'fails clearly when the selected version is not installed' {
        $version = '99.0.100'

        $verifyOutput = @(Invoke-VerifyTool -Version $version)

        $script:VerifyExitCode | Should -Not -Be 0
        ($verifyOutput -join [Environment]::NewLine) | Should -Match "Isolated SDK $([regex]::Escape($version)) is not installed under"
    }

    It 'fails clearly when the installation directory has no host' {
        $version = '99.0.100'
        $installDirectory = Join-Path $script:ToolRoot $version
        New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null

        $verifyOutput = @(Invoke-VerifyTool -Version $version)

        $script:VerifyExitCode | Should -Not -Be 0
        ($verifyOutput -join [Environment]::NewLine) | Should -Match 'expected dotnet host was not found'
        Test-Path -LiteralPath $installDirectory -PathType Container | Should -BeTrue
    }

    It 'fails with launch context when the host cannot be launched' {
        $version = '99.0.100'
        $installDirectory = Join-Path $script:ToolRoot $version
        $hostPath = Join-Path $installDirectory 'dotnet.exe'
        New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
        Set-Content -LiteralPath $hostPath -Value 'not-a-windows-executable' -NoNewline

        $verifyOutput = @(Invoke-VerifyTool -Version $version)

        $script:VerifyExitCode | Should -Not -Be 0
        ($verifyOutput -join [Environment]::NewLine) | Should -Match "Unable to launch isolated SDK $([regex]::Escape($version)) host"
        Test-Path -LiteralPath $hostPath -PathType Leaf | Should -BeTrue
    }

    It 'fails with the native exit code when the host reports execution failure' {
        $version = '99.0.100'
        Install-FakeIsolatedHost -SdkVersion $version -ReportedVersion $version | Out-Null
        $env:FAKE_DOTNET_EXIT_CODE = '73'

        $verifyOutput = @(Invoke-VerifyTool -Version $version)

        $script:VerifyExitCode | Should -Not -Be 0
        ($verifyOutput -join [Environment]::NewLine) | Should -Match "Unable to verify isolated SDK $([regex]::Escape($version)) with exit code 73\."
    }

    It 'fails when the isolated host does not report the requested SDK version' {
        $version = '99.0.100'
        Install-FakeIsolatedHost -SdkVersion $version -ReportedVersion '98.0.100' | Out-Null

        $verifyOutput = @(Invoke-VerifyTool -Version $version)

        $script:VerifyExitCode | Should -Not -Be 0
        ($verifyOutput -join [Environment]::NewLine) | Should -Match "Isolated SDK $([regex]::Escape($version)) failed verification: the host did not report SDK $([regex]::Escape($version))\."
    }

    It 'rejects an identical SDK version reported from another location' {
        $version = '99.0.100'
        Install-FakeIsolatedHost -Version $version -ReportedVersion $version | Out-Null
        $wrongOrigin = Join-Path $script:TestRoot 'system/sdk'
        New-Item -ItemType Directory -Path $wrongOrigin -Force | Out-Null
        $env:FAKE_DOTNET_SDK_ORIGIN = $wrongOrigin

        $verifyOutput = @(Invoke-VerifyTool -Version $version)
        $script:VerifyExitCode | Should -Not -Be 0
        ($verifyOutput -join [Environment]::NewLine) | Should -Match 'was not reported from'
        ($verifyOutput -join [Environment]::NewLine) | Should -Match 'SDK inventory'
    }

    It 'rejects missing isolated SDK origin directory even when a host reports that path' {
        $version = '99.0.100'
        $installDirectory = Install-FakeIsolatedHost -Version $version -ReportedVersion $version
        Remove-Item -LiteralPath (Join-Path $installDirectory 'sdk') -Recurse -Force

        $verifyOutput = @(Invoke-VerifyTool -Version $version)
        $script:VerifyExitCode | Should -Not -Be 0
        ($verifyOutput -join [Environment]::NewLine) | Should -Match 'SDK inventory'
        ($verifyOutput -join [Environment]::NewLine) | Should -Match 'was not reported from'
    }

    It 'rejects --version mismatch and preserves its own failure context' {
        $version = '99.0.100'
        Install-FakeIsolatedHost -Version $version -ReportedVersion $version | Out-Null
        $env:FAKE_DOTNET_RESOLVED_VERSION = '98.0.100'

        $verifyOutput = @(Invoke-VerifyTool -Version $version)
        $script:VerifyExitCode | Should -Not -Be 0
        ($verifyOutput -join [Environment]::NewLine) | Should -Match '--version resolved 98.0.100 instead of 99.0.100'
    }

    It 'forces single-location lookup and ignores ambient global.json' {
        $version = '99.0.100'
        Install-FakeIsolatedHost -Version $version -ReportedVersion $version | Out-Null
        Set-Content -LiteralPath (Join-Path $script:ToolRoot 'global.json') -Value '{ "sdk": {"version": "1.0.100"} }'
        $env:DOTNET_MULTILEVEL_LOOKUP = '1'
        $env:FAKE_DOTNET_EXPECT_MULTILEVEL_LOOKUP = '0'
        $env:FAKE_DOTNET_FORBIDDEN_WORK_DIR = $script:ToolRoot

        try {
            $verifyOutput = @(Invoke-VerifyTool -Version $version)
            $script:VerifyExitCode | Should -Be 0
            ($verifyOutput -join [Environment]::NewLine) | Should -Match 'verified successfully'
            $env:DOTNET_MULTILEVEL_LOOKUP | Should -Be '1'
        }
        finally {
            Remove-Item Env:DOTNET_MULTILEVEL_LOOKUP -ErrorAction SilentlyContinue
        }
    }

    It 'shows shared Audit classification from deterministic Microsoft metadata' {
        $version = '99.0.100'
        Install-FakeIsolatedHost -Version $version -ReportedVersion $version | Out-Null
        $metadata = Join-Path $script:TestRoot 'metadata'
        New-Item -ItemType Directory -Path $metadata -Force | Out-Null
        $env:VERIFY_METADATA_ROOT = $metadata
        @'
{"releases-index":[{"channel-version":"99.0","latest-sdk":"99.0.200","support-phase":"maintenance","release-type":"lts","eol-date":"2030-01-01","releases.json":"https://example.invalid/99.0.json"}]}
'@ | Set-Content -LiteralPath (Join-Path $metadata 'index.json')
        @'
{"releases":[{"release-date":"2026-01-01","sdk":{"version":"99.0.100"}},{"release-date":"2026-04-01","sdk":{"version":"99.0.200"}}]}
'@ | Set-Content -LiteralPath (Join-Path $metadata 'channel.json')

        $verifyOutput = @(Invoke-VerifyTool -Version $version)
        $script:VerifyExitCode | Should -Be 0
        $outputText = $verifyOutput -join [Environment]::NewLine
        $outputText | Should -Match 'Support type\s+LTS'
        $outputText | Should -Match 'Status\s+Maintenance'
        $outputText | Should -Match 'SDK release date\s+2026-01-01'
        $outputText | Should -Match 'Channel EOS date\s+2030-01-01'
        $outputText | Should -Match 'Update available\s+99\.0\.200'
        $outputText.Contains([char]27) | Should -BeFalse
    }

    It 'excludes system runtimes from the isolated component inventory' {
        $version = '99.0.100'
        Install-FakeIsolatedHost -Version $version -ReportedVersion $version | Out-Null
        $unrelated = Join-Path $script:TestRoot 'system/shared/Microsoft.AspNetCore.App'
        New-Item -ItemType Directory -Path $unrelated -Force | Out-Null
        $env:FAKE_DOTNET_EXTRA_RUNTIME_ROOT = $unrelated

        $verifyOutput = @(Invoke-VerifyTool -Version $version)
        $script:VerifyExitCode | Should -Be 0
        $outputText = $verifyOutput -join [Environment]::NewLine
        $outputText | Should -Match 'Microsoft\.NETCore\.App\s+99\.0\.9'
        $outputText | Should -Not -Match 'Microsoft\.AspNetCore\.App'
    }

    It 'requires an exact version for Verify' {
        $verifyOutput = @(Invoke-VerifyTool)

        $script:VerifyExitCode | Should -Not -Be 0
        ($verifyOutput -join [Environment]::NewLine) | Should -Match '-SdkVersion is required with -Action Verify\.'
    }

    It 'rejects invalid exact-version syntax for Verify' {
        $verifyOutput = @(Invoke-VerifyTool -Version 'invalid/version')

        $script:VerifyExitCode | Should -Not -Be 0
        ($verifyOutput -join [Environment]::NewLine) | Should -Match 'Invalid SDK version: invalid/version'
    }
}

Describe 'PowerShell Verify origin, resolution, and metadata boundaries' {
    BeforeAll {
        $script:root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    }
    It 'keeps the Verify local proof helper available to later Install work without implementing Install reuse yet' {
        $source = Get-Content -LiteralPath (Join-Path $script:root 'isolated-dotnet-sdk.ps1') -Raw
        $source | Should -Match 'function Get-LocalIsolatedSdkValidation'
        $source | Should -Match 'Get-SdkAuditClassification -Version'
    }
}
