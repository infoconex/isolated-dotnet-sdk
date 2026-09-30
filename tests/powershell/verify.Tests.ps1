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
            $env:FAKE_DOTNET_SDK_VERSION = $ReportedVersion
            return $installDirectory
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
        Remove-Item Env:FAKE_DOTNET_SDK_VERSION -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'reports a healthy exact isolated SDK without mutating it' {
        $version = '99.0.100'
        $installDirectory = Install-FakeIsolatedHost -Version $version -ReportedVersion $version
        $sentinelPath = Join-Path $installDirectory 'verify-sentinel.txt'
        Set-Content -LiteralPath $sentinelPath -Value 'preserve-me' -NoNewline
        $fileCountBefore = @(Get-ChildItem -LiteralPath $installDirectory -File -Recurse -Force).Count

        $verifyOutput = @(& pwsh -NoProfile -File $script:ToolPath -Action Verify -Version $version 2>&1)

        $LASTEXITCODE | Should -Be 0
        ($verifyOutput -join [Environment]::NewLine) | Should -Match "Isolated SDK $([regex]::Escape($version)) is healthy\."
        ($verifyOutput -join [Environment]::NewLine) | Should -Match ([regex]::Escape("Location: $installDirectory"))
        (Get-Content -LiteralPath $sentinelPath -Raw) | Should -Be 'preserve-me'
        @(Get-ChildItem -LiteralPath $installDirectory -File -Recurse -Force).Count | Should -Be $fileCountBefore
    }

    It 'fails clearly when the selected version is not installed' {
        $version = '99.0.100'

        $verifyOutput = @(& pwsh -NoProfile -File $script:ToolPath -Action Verify -Version $version 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        ($verifyOutput -join [Environment]::NewLine) | Should -Match "Isolated SDK $([regex]::Escape($version)) is not installed under"
    }

    It 'fails clearly when the installation directory has no host' {
        $version = '99.0.100'
        $installDirectory = Join-Path $script:ToolRoot $version
        New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null

        $verifyOutput = @(& pwsh -NoProfile -File $script:ToolPath -Action Verify -Version $version 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        ($verifyOutput -join [Environment]::NewLine) | Should -Match 'expected dotnet host was not found'
        Test-Path -LiteralPath $installDirectory -PathType Container | Should -BeTrue
    }

    It 'fails with launch context when the host cannot be launched' {
        $version = '99.0.100'
        $installDirectory = Join-Path $script:ToolRoot $version
        $hostPath = Join-Path $installDirectory 'dotnet.exe'
        New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
        Set-Content -LiteralPath $hostPath -Value 'not-a-windows-executable' -NoNewline

        $verifyOutput = @(& pwsh -NoProfile -File $script:ToolPath -Action Verify -Version $version 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        ($verifyOutput -join [Environment]::NewLine) | Should -Match "Unable to launch isolated SDK $([regex]::Escape($version)) host"
        Test-Path -LiteralPath $hostPath -PathType Leaf | Should -BeTrue
    }

    It 'fails with the native exit code when the host reports execution failure' {
        $version = '99.0.100'
        Install-FakeIsolatedHost -Version $version -ReportedVersion $version | Out-Null
        $env:FAKE_DOTNET_EXIT_CODE = '73'

        $verifyOutput = @(& pwsh -NoProfile -File $script:ToolPath -Action Verify -Version $version 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        ($verifyOutput -join [Environment]::NewLine) | Should -Match "Unable to verify isolated SDK $([regex]::Escape($version)) with exit code 73\."
    }

    It 'fails when the isolated host does not report the requested SDK version' {
        $version = '99.0.100'
        Install-FakeIsolatedHost -Version $version -ReportedVersion '98.0.100' | Out-Null

        $verifyOutput = @(& pwsh -NoProfile -File $script:ToolPath -Action Verify -Version $version 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        ($verifyOutput -join [Environment]::NewLine) | Should -Match "Isolated SDK $([regex]::Escape($version)) failed verification: the host did not report SDK $([regex]::Escape($version))\."
    }

    It 'requires an exact version for Verify' {
        $verifyOutput = @(& pwsh -NoProfile -File $script:ToolPath -Action Verify 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        ($verifyOutput -join [Environment]::NewLine) | Should -Match '-Version is required with -Action Verify\.'
    }

    It 'rejects invalid exact-version syntax for Verify' {
        $verifyOutput = @(& pwsh -NoProfile -File $script:ToolPath -Action Verify -Version 'invalid/version' 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        ($verifyOutput -join [Environment]::NewLine) | Should -Match 'Invalid SDK version: invalid/version'
    }
}
