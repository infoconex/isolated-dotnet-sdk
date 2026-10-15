Describe 'PowerShell interactive Verify' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:ToolScript = Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1'

        function Invoke-InteractiveVerifyTool {
            param(
                [string[]]$InputLines,
                [string]$Command = '& $env:ISOLATED_DOTNET_SDK_TOOL_PATH',
                [string]$PathPrefix
            )

            $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
            $startInfo.FileName = 'pwsh'
            $startInfo.UseShellExecute = $false
            $startInfo.RedirectStandardInput = $true
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true
            $startInfo.ArgumentList.Add('-NoProfile')
            $startInfo.ArgumentList.Add('-Command')
            $startInfo.ArgumentList.Add('function Invoke-RestMethod { throw "Fixture metadata unavailable" }; ' + $Command)
            $startInfo.Environment['ISOLATED_DOTNET_SDK_TOOL_PATH'] = $script:ToolPath
            $startInfo.Environment['HOME'] = $script:TestHome
            $startInfo.Environment['USERPROFILE'] = $script:TestHome
            if ($PathPrefix) {
                $startInfo.Environment['PATH'] = "$PathPrefix$([System.IO.Path]::PathSeparator)$env:PATH"
            }
            if ($env:FAKE_DOTNET_SDK_VERSION) {
                $startInfo.Environment['FAKE_DOTNET_SDK_VERSION'] = $env:FAKE_DOTNET_SDK_VERSION
            }

            $process = [System.Diagnostics.Process]::new()
            $process.StartInfo = $startInfo
            [void]$process.Start()

            foreach ($line in $InputLines) {
                $process.StandardInput.WriteLine($line)
            }
            $process.StandardInput.Close()

            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()
            $process.WaitForExit()

            return [pscustomobject]@{
                ExitCode = $process.ExitCode
                Output   = $stdoutTask.GetAwaiter().GetResult() + $stderrTask.GetAwaiter().GetResult()
            }
        }

        function Get-MainPromptCount {
            param([string]$Output)
            return ([regex]::Matches($Output, 'What would you like to do\?')).Count
        }

        function Get-AcknowledgementPromptCount {
            param([string]$Output)
            return ([regex]::Matches($Output, 'Press Enter to return to [^\r\n]+\.\.\.')).Count
        }

        function Install-FakeInteractiveVerifyHost {
            param(
                [string]$Version = '99.0.100',
                [string]$ReportedVersion = '99.0.100'
            )

            $installDirectory = Join-Path $script:ToolRoot $Version
            New-Item -ItemType Directory -Path (Join-Path $installDirectory 'sdk') -Force | Out-Null
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
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-interactive-verify-{0}" -f [guid]::NewGuid())
        $script:TestHome = Join-Path $script:TestRoot 'home'
        $script:ToolRoot = Join-Path $script:TestHome 'dotnet-sdks'
        $script:ToolPath = Join-Path $script:ToolRoot 'isolated-dotnet-sdk.ps1'
        # The interactive subprocesses under test use this independently
        # installed tool; launching an extra bootstrap process per case adds
        # no coverage to their prompt, input, and exit-code contracts.
        New-Item -ItemType Directory -Path $script:ToolRoot -Force | Out-Null
        Copy-Item -LiteralPath $script:ToolScript -Destination $script:ToolPath -Force -ErrorAction Stop
        Test-Path -LiteralPath $script:ToolPath -PathType Leaf | Should -BeTrue
    }

    AfterEach {
        Remove-Item Env:FAKE_DOTNET_SDK_VERSION -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'returns a healthy Verify result to the Verify SDK list' {
        $version = '99.0.100'
        Install-FakeInteractiveVerifyHost -Version $version -ReportedVersion $version | Out-Null

        $result = Invoke-InteractiveVerifyTool -InputLines @('v', '1', 'b', 'e')

        $result.ExitCode | Should -Be 0
        (Get-MainPromptCount $result.Output) | Should -Be 2
        (Get-AcknowledgementPromptCount $result.Output) | Should -Be 0
        $result.Output | Should -Match 'V\. Verify an isolated SDK'
        ([regex]::Matches($result.Output, 'Select an isolated SDK to verify:')).Count | Should -Be 2
        $result.Output | Should -Match 'Selection[^\r\n]*\r?\n\r?\nVerify isolated \.NET SDK'
        $result.Output | Should -Match "Isolated SDK $([regex]::Escape($version)) verified successfully\."
        $result.Output | Should -Match 'Exiting\.'
    }

    It 'treats no isolated SDKs as a normal no-change result' {
        $result = Invoke-InteractiveVerifyTool -InputLines @('v', 'e')

        $result.ExitCode | Should -Be 0
        (Get-MainPromptCount $result.Output) | Should -Be 2
        (Get-AcknowledgementPromptCount $result.Output) | Should -Be 0
        $result.Output | Should -Match 'No isolated SDKs are installed under'
        $result.Output | Should -Not -Match 'Select an isolated SDK to verify:'
    }

    It 'supports Back to Main and Exit from Verify selection' {
        $version = '99.0.100'
        Install-FakeInteractiveVerifyHost -Version $version -ReportedVersion $version | Out-Null

        $result = Invoke-InteractiveVerifyTool -InputLines @('v', 'b', 'v', 'e')

        $result.ExitCode | Should -Be 0
        (Get-MainPromptCount $result.Output) | Should -Be 2
        (Get-AcknowledgementPromptCount $result.Output) | Should -Be 0
        $result.Output | Should -Match 'B\. Back to Main'
        $result.Output | Should -Match 'E\. Exit'
        $result.Output | Should -Match 'Exiting\.'
        $result.Output | Should -Not -Match "Isolated SDK $([regex]::Escape($version)) verified successfully\."
    }

    It 'sorts Verify choices newest to oldest' {
        foreach ($version in @('8.0.425', '11.0.100-rc.1.26425.128', '10.0.401')) {
            Install-FakeInteractiveVerifyHost -Version $version -ReportedVersion $version | Out-Null
        }

        $result = Invoke-InteractiveVerifyTool -InputLines @('v', 'b', 'e')

        $result.ExitCode | Should -Be 0
        $verifyStart = $result.Output.IndexOf('Select an isolated SDK to verify:')
        $verifyEnd = $result.Output.IndexOf('B. Back to Main', $verifyStart)
        $verifySection = $result.Output.Substring($verifyStart, $verifyEnd - $verifyStart)
        $verifySection | Should -Match '1\. 11\.0\.100-rc\.1\.26425\.128'
        $verifySection | Should -Match '2\. 10\.0\.401'
        $verifySection | Should -Match '3\. 8\.0\.425'
    }

    It 'never offers System SDKs as interactive Verify targets' {
        $isolatedVersion = '99.0.100'
        $systemVersion = '88.0.100'
        Install-FakeInteractiveVerifyHost -Version $isolatedVersion -ReportedVersion $isolatedVersion | Out-Null

        $fakeBin = Join-Path $script:TestRoot 'fake-bin'
        New-Item -ItemType Directory -Path $fakeBin -Force | Out-Null
        @"
@echo off
if "%1"=="--list-sdks" echo $systemVersion [C:\system\sdk]
exit /b 0
"@ | Set-Content -LiteralPath (Join-Path $fakeBin 'dotnet.cmd') -Encoding ascii

        $result = Invoke-InteractiveVerifyTool `
            -InputLines @('v', 'b', 'e') `
            -PathPrefix $fakeBin

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match "1\. $([regex]::Escape($isolatedVersion))"
        $result.Output | Should -Not -Match ([regex]::Escape($systemVersion))
    }

    It 'terminates nonzero when the selected isolated SDK fails verification' {
        $version = '99.0.100'
        Install-FakeInteractiveVerifyHost -Version $version -ReportedVersion '98.0.100' | Out-Null

        $result = Invoke-InteractiveVerifyTool `
            -InputLines @('v', '1', 'e') `
            -Command '& $env:ISOLATED_DOTNET_SDK_TOOL_PATH *>&1'

        $result.ExitCode | Should -Not -Be 0
        (Get-MainPromptCount $result.Output) | Should -Be 1
        (Get-AcknowledgementPromptCount $result.Output) | Should -Be 0
        $result.Output | Should -Match "Isolated SDK $([regex]::Escape($version)) failed verification: the host did not report SDK $([regex]::Escape($version))\."
        $result.Output | Should -Not -Match 'Exiting\.'
    }

    It 'reports active Verify choices for blank and invalid selections' {
        $version = '99.0.100'
        Install-FakeInteractiveVerifyHost -Version $version -ReportedVersion $version | Out-Null

        $result = Invoke-InteractiveVerifyTool `
            -InputLines @('v', '', '6', 'b', 'e') `
            -Command '& $env:ISOLATED_DOTNET_SDK_TOOL_PATH *>&1'

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'A selection is required\. Choose 1, B, or E\.'
        $result.Output | Should -Match 'Invalid selection: 6\. Choose 1, B, or E\.'
        $result.Output | Should -Match 'Invalid selection: 6\. Choose 1, B, or E\.\r?\n\r?\nSelect an isolated SDK to verify:'
    }

    It 'uses the same legacy SDK origin checks in interactive Verify' {
        $version = '1.1.14'
        $directory = Install-FakeInteractiveVerifyHost -Version $version -ReportedVersion $version
        New-Item -ItemType Directory -Path (Join-Path $directory "sdk/$version") -Force | Out-Null
        $env:FAKE_DOTNET_LEGACY_HOST = 'true'
        try {
            $result = Invoke-InteractiveVerifyTool -InputLines @('v', '1', 'b', 'e')
            $result.ExitCode | Should -Be 0
            $result.Output | Should -Match 'SDK origin\s+OK\s+Exact SDK Base Path in isolated installation'
            $result.Output | Should -Match 'Isolated SDK 1\.1\.14 verified successfully'
            $result.Output | Should -Not -Match 'Unknown option: --list-sdks'
        }
        finally {
            Remove-Item Env:FAKE_DOTNET_LEGACY_HOST -ErrorAction SilentlyContinue
        }
    }

}
