Describe 'PowerShell install target status' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:ToolScript = Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1'
        $script:HomeVariableName = if ($IsWindows) { 'USERPROFILE' } else { 'HOME' }
        $script:FakeHostOutput = $env:ISOLATED_DOTNET_SDK_SHARED_FAKE_HOST_ROOT

        function Initialize-SystemDotNetStub {
            param([switch]$IncludeTarget)

            $fakeBin = Join-Path $script:TestRoot 'system-bin'
            New-Item -ItemType Directory -Path $fakeBin -Force | Out-Null

            $batchLines = @(
                '@echo off'
                'if not "%1"=="--list-sdks" exit /b 91'
                "echo $($script:UnrelatedVersion) [C:\system\sdk]"
            )
            if ($IncludeTarget) {
                $batchLines += "echo $($script:Version) [C:\system\sdk]"
            }
            $batchLines += 'exit /b 0'

            Set-Content `
                -LiteralPath (Join-Path $fakeBin 'dotnet.cmd') `
                -Value ($batchLines -join "`r`n")

            $env:ISOLATED_DOTNET_SDK_TEST_PATH = "$fakeBin$([IO.Path]::PathSeparator)$env:PATH"
        }

        function Install-IsolatedFakeHost {
            New-Item -ItemType Directory -Path $script:InstallDir -Force | Out-Null
            Copy-Item `
                -Path (Join-Path $script:FakeHostOutput '*') `
                -Destination $script:InstallDir `
                -Recurse `
                -Force
        }
    }

    BeforeEach {
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-install-status-{0}" -f [guid]::NewGuid())
        $script:TestHome = Join-Path $script:TestRoot 'home'
        $script:ToolRoot = Join-Path $script:TestHome 'dotnet-sdks'
        $script:ToolPath = Join-Path $script:ToolRoot 'isolated-dotnet-sdk.ps1'
        $script:Version = '99.0.100'
        $script:UnrelatedVersion = '8.0.425'
        $script:InstallDir = Join-Path $script:ToolRoot $script:Version
        $script:OriginalHomeValue = [Environment]::GetEnvironmentVariable($script:HomeVariableName, 'Process')

        New-Item -ItemType Directory -Path $script:ToolRoot -Force | Out-Null
        Copy-Item -LiteralPath $script:ToolScript -Destination $script:ToolPath -Force
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:TestHome, 'Process')

        $env:ISOLATED_DOTNET_SDK_TOOL_PATH = $script:ToolPath
        $env:ISOLATED_DOTNET_SDK_TEST_VERSION = $script:Version
        $env:FAKE_DOTNET_SDK_VERSION = $script:Version
    }

    AfterEach {
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:OriginalHomeValue, 'Process')
        foreach ($name in @(
                'ISOLATED_DOTNET_SDK_TOOL_PATH',
                'ISOLATED_DOTNET_SDK_TEST_PATH',
                'ISOLATED_DOTNET_SDK_TEST_VERSION',
                'FAKE_DOTNET_SDK_VERSION')) {
            Remove-Item "Env:$name" -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'reports only the selected System SDK and preserves confirmation' {
        Initialize-SystemDotNetStub -IncludeTarget

        $output = @(& pwsh -NoProfile -Command '
            $env:PATH = $env:ISOLATED_DOTNET_SDK_TEST_PATH
            function Read-Host {
                param([string]$Prompt)
                Write-Information $Prompt -InformationAction Continue
                return ""
            }
            & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -Version $env:ISOLATED_DOTNET_SDK_TEST_VERSION
        ' 6>&1 2>&1)

        $LASTEXITCODE | Should -Be 0
        $text = $output -join [Environment]::NewLine
        $text | Should -Match 'Checking existing installations\.\.\.'
        $text | Should -Match 'System SDK: Already installed'
        $text | Should -Match 'Location: C:\\system\\sdk\\99\.0\.100'
        $text | Should -Match 'Isolated SDK: Not installed'
        $text | Should -Match 'Isolated SDK: Not installed\r?\n\r?\nSystem SDK: Already installed'
        $text | Should -Match 'Install an isolated copy in addition to the System SDK\?'
        $text | Should -Match 'Installation cancelled\.'
        $text | Should -Not -Match ([regex]::Escape($script:UnrelatedVersion))
        $text | Should -Not -Match 'normal dotnet host'
        $text | Should -Not -Match 'installed normally'
    }

    It 'reports an existing isolated target without unrelated System inventory' {
        Initialize-SystemDotNetStub
        Install-IsolatedFakeHost

        $output = @(& pwsh -NoProfile -Command '
            $env:PATH = $env:ISOLATED_DOTNET_SDK_TEST_PATH
            & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -Version $env:ISOLATED_DOTNET_SDK_TEST_VERSION -Yes
        ' 6>&1 2>&1)

        $LASTEXITCODE | Should -Be 0
        $text = $output -join [Environment]::NewLine
        $text | Should -Match 'Checking existing installations\.\.\.'
        $text | Should -Match 'System SDK: Not installed'
        $text | Should -Match ([regex]::Escape("Location: $($script:InstallDir)") + '\r?\n\r?\nSystem SDK: Not installed')
        $text | Should -Match 'Isolated SDK: Already installed'
        $text | Should -Match ([regex]::Escape("Location: $($script:InstallDir)"))
        $text | Should -Not -Match ([regex]::Escape($script:UnrelatedVersion))
        $text | Should -Not -Match 'Loading Microsoft release metadata'
    }

    It 'reports both ownership states when the selected target exists in both' {
        Initialize-SystemDotNetStub -IncludeTarget
        Install-IsolatedFakeHost

        $output = @(& pwsh -NoProfile -Command '
            $env:PATH = $env:ISOLATED_DOTNET_SDK_TEST_PATH
            & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -Version $env:ISOLATED_DOTNET_SDK_TEST_VERSION -Yes
        ' 6>&1 2>&1)

        $LASTEXITCODE | Should -Be 0
        $text = $output -join [Environment]::NewLine
        $text | Should -Match 'System SDK: Already installed'
        $text | Should -Match 'Location: C:\\system\\sdk\\99\.0\.100'
        $text | Should -Match ([regex]::Escape("Location: $($script:InstallDir)") + '\r?\n\r?\nSystem SDK: Already installed')
        $text | Should -Match 'Isolated SDK: Already installed'
        $text | Should -Match ([regex]::Escape("Location: $($script:InstallDir)"))
        $text | Should -Not -Match ([regex]::Escape($script:UnrelatedVersion))
        $text | Should -Not -Match 'Loading Microsoft release metadata'
    }

    It 'reports neither ownership state before continuing to acquisition' {
        Initialize-SystemDotNetStub

        $output = @(& pwsh -NoProfile -Command '
            $env:PATH = $env:ISOLATED_DOTNET_SDK_TEST_PATH
            function Invoke-WebRequest { throw "stop-after-status" }
            & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -Version $env:ISOLATED_DOTNET_SDK_TEST_VERSION -Yes
        ' 6>&1 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        $text = $output -join [Environment]::NewLine
        $text | Should -Match 'Checking existing installations\.\.\.'
        $text | Should -Match 'System SDK: Not installed'
        $text | Should -Match 'Isolated SDK: Not installed\r?\n\r?\nSystem SDK: Not installed'
        $text | Should -Match 'Isolated SDK: Not installed'
        $text | Should -Not -Match ([regex]::Escape($script:UnrelatedVersion))
    }
}
