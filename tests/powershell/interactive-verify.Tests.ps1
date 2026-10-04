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
            $startInfo.ArgumentList.Add($Command)
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

        function Install-FakeInteractiveVerifyHost {
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
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-interactive-verify-{0}" -f [guid]::NewGuid())
        $script:TestHome = Join-Path $script:TestRoot 'home'
        $script:ToolRoot = Join-Path $script:TestHome 'dotnet-sdks'
        $script:ToolPath = Join-Path $script:ToolRoot 'isolated-dotnet-sdk.ps1'
        $script:SourceCopy = Join-Path $script:TestRoot 'isolated-dotnet-sdk-source.ps1'
        New-Item -ItemType Directory -Path $script:TestHome -Force | Out-Null

        Copy-Item $script:ToolScript $script:SourceCopy -Force
        $homeVariable = if ($IsWindows) { 'USERPROFILE' } else { 'HOME' }
        $originalHome = [Environment]::GetEnvironmentVariable($homeVariable, 'Process')
        try {
            [Environment]::SetEnvironmentVariable($homeVariable, $script:TestHome, 'Process')
            & pwsh -NoProfile -File $script:SourceCopy -Action List *> $null
            $LASTEXITCODE | Should -Be 0
        }
        finally {
            [Environment]::SetEnvironmentVariable($homeVariable, $originalHome, 'Process')
        }
    }

    AfterEach {
        Remove-Item Env:FAKE_DOTNET_SDK_VERSION -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'exposes Verify on Main and returns to Main after a healthy Verify' {
        $version = '99.0.100'
        Install-FakeInteractiveVerifyHost -Version $version -ReportedVersion $version | Out-Null

        $result = Invoke-InteractiveVerifyTool -InputLines @('v', '1', 'e')

        $result.ExitCode | Should -Be 0
        (Get-MainPromptCount $result.Output) | Should -Be 2
        $result.Output | Should -Match 'V\. Verify an isolated SDK'
        $result.Output | Should -Match 'Select an isolated SDK to verify:'
        $result.Output | Should -Match "Isolated SDK $([regex]::Escape($version)) is healthy\."
        $result.Output | Should -Match 'Exiting\.'
    }

    It 'treats no isolated SDKs as a normal no-change result' {
        $result = Invoke-InteractiveVerifyTool -InputLines @('v', 'e')

        $result.ExitCode | Should -Be 0
        (Get-MainPromptCount $result.Output) | Should -Be 2
        $result.Output | Should -Match 'No isolated SDKs are installed under'
        $result.Output | Should -Not -Match 'Select an isolated SDK to verify:'
    }

    It 'supports Back to Main and Exit from Verify selection' {
        $version = '99.0.100'
        Install-FakeInteractiveVerifyHost -Version $version -ReportedVersion $version | Out-Null

        $result = Invoke-InteractiveVerifyTool -InputLines @('v', 'b', 'v', 'e')

        $result.ExitCode | Should -Be 0
        (Get-MainPromptCount $result.Output) | Should -Be 2
        $result.Output | Should -Match 'B\. Back to Main'
        $result.Output | Should -Match 'E\. Exit'
        $result.Output | Should -Match 'Exiting\.'
        $result.Output | Should -Not -Match "Isolated SDK $([regex]::Escape($version)) is healthy\."
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
        $result.Output | Should -Not -Match [regex]::Escape($systemVersion)
    }

    It 'terminates nonzero when the selected isolated SDK fails verification' {
        $version = '99.0.100'
        Install-FakeInteractiveVerifyHost -Version $version -ReportedVersion '98.0.100' | Out-Null

        $result = Invoke-InteractiveVerifyTool `
            -InputLines @('v', '1', 'e') `
            -Command '& $env:ISOLATED_DOTNET_SDK_TOOL_PATH *>&1'

        $result.ExitCode | Should -Not -Be 0
        (Get-MainPromptCount $result.Output) | Should -Be 1
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
}
