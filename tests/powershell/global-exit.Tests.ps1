Describe 'PowerShell global interactive exit contract' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:ToolScript = Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1'

        function Invoke-GlobalExitToolProcess {
            param(
                [string[]]$InputLines = @(),
                [string]$Command = '& $env:ISOLATED_DOTNET_SDK_TOOL_PATH'
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
                Output = $stdoutTask.GetAwaiter().GetResult() + $stderrTask.GetAwaiter().GetResult()
            }
        }

        function Get-GlobalExitMainPromptCount {
            param([string]$Output)
            return ([regex]::Matches($Output, 'What would you like to do\?')).Count
        }

        $script:ReleaseIndexCommand = @'
$releaseIndex = [pscustomobject]@{
    'releases-index' = @(
        [pscustomobject]@{
            'channel-version' = '10.0'
            'latest-sdk' = '10.0.401'
            'support-phase' = 'active'
            'release-type' = 'lts'
            'releases.json' = 'https://example.invalid/10.0/releases.json'
        },
        [pscustomobject]@{
            'channel-version' = '7.0'
            'latest-sdk' = '7.0.410'
            'support-phase' = 'eol'
            'release-type' = 'sts'
            'releases.json' = 'https://example.invalid/7.0/releases.json'
        }
    )
}
$channelMetadata = [pscustomobject]@{
    releases = @(
        [pscustomobject]@{ sdk = [pscustomobject]@{ version = '10.0.401' } },
        [pscustomobject]@{ sdk = [pscustomobject]@{ version = '10.0.400' } },
        [pscustomobject]@{ sdk = [pscustomobject]@{ version = '10.0.303' } }
    )
}
function Invoke-RestMethod {
    param($Uri)
    if ($Uri -like '*releases-index.json') { return $releaseIndex }
    return $channelMetadata
}
& $env:ISOLATED_DOTNET_SDK_TOOL_PATH
'@
    }

    BeforeEach {
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-global-exit-{0}" -f [guid]::NewGuid())
        $script:TestHome = Join-Path $script:TestRoot 'home'
        $script:ToolRoot = Join-Path $script:TestHome 'dotnet-sdks'
        $script:ToolPath = Join-Path $script:ToolRoot 'isolated-dotnet-sdk.ps1'
        $sourceCopy = Join-Path $script:TestRoot 'isolated-dotnet-sdk-source.ps1'
        New-Item -ItemType Directory -Path $script:TestHome -Force | Out-Null
        Copy-Item $script:ToolScript $sourceCopy -Force

        $homeVariable = if ($IsWindows) { 'USERPROFILE' } else { 'HOME' }
        $originalHome = [Environment]::GetEnvironmentVariable($homeVariable, 'Process')
        try {
            [Environment]::SetEnvironmentVariable($homeVariable, $script:TestHome, 'Process')
            & pwsh -NoProfile -File $sourceCopy -Action List *> $null
            $LASTEXITCODE | Should -Be 0
        }
        finally {
            [Environment]::SetEnvironmentVariable($homeVariable, $originalHome, 'Process')
        }
    }

    AfterEach {
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'advertises mnemonic Main commands and rejects numeric aliases' {
        $result = Invoke-GlobalExitToolProcess -InputLines @('1', '2', '3', '4', 'e')

        $result.ExitCode | Should -Be 0
        (Get-GlobalExitMainPromptCount $result.Output) | Should -Be 5
        $result.Output | Should -Match 'E\. Exit'
        $result.Output | Should -Match 'I\. Install an SDK'
        $result.Output | Should -Match 'R\. Remove an isolated SDK'
        $result.Output | Should -Match 'L\. List installed SDKs'
        $result.Output | Should -Not -Match '1\. Install an SDK'
        $result.Output | Should -Not -Match '2\. Remove an isolated SDK'
        $result.Output | Should -Not -Match '3\. List installed SDKs'
        $result.Output | Should -Not -Match '4\. Exit'
        $result.Output | Should -Match 'Invalid selection: 1\. Choose I, R, L, or E\.'
        $result.Output | Should -Match 'Invalid selection: 2\. Choose I, R, L, or E\.'
        $result.Output | Should -Match 'Invalid selection: 3\. Choose I, R, L, or E\.'
        $result.Output | Should -Match 'Invalid selection: 4\. Choose I, R, L, or E\.'
        $result.Output | Should -Match 'Exiting\.'
        $result.Output | Should -Match '\r?\n\r?\nExiting\.\r?\n\r?\n'
    }

    It 'exits the persistent session directly from supported channel selection' {
        $result = Invoke-GlobalExitToolProcess `
            -InputLines @('i', 'e') `
            -Command $script:ReleaseIndexCommand

        $result.ExitCode | Should -Be 0
        (Get-GlobalExitMainPromptCount $result.Output) | Should -Be 1
        $result.Output | Should -Match 'E\. Exit'
        $result.Output | Should -Not -Match 'Installation cancelled\.'
        $result.Output | Should -Match 'Exiting\.'
    }

    It 'exits the persistent session directly from the end-of-life channel view' {
        $result = Invoke-GlobalExitToolProcess `
            -InputLines @('i', 's', 'e') `
            -Command $script:ReleaseIndexCommand

        $result.ExitCode | Should -Be 0
        (Get-GlobalExitMainPromptCount $result.Output) | Should -Be 1
        $result.Output | Should -Match 'Select an end-of-life \.NET channel:'
        $result.Output | Should -Match 'E\. Exit'
        $result.Output | Should -Not -Match 'Installation cancelled\.'
        $result.Output | Should -Match 'Exiting\.'
    }

    It 'uses S to toggle the channel view in both directions' {
        $result = Invoke-GlobalExitToolProcess `
            -InputLines @('i', 's', 's', 'e') `
            -Command $script:ReleaseIndexCommand

        $result.ExitCode | Should -Be 0
        (Get-GlobalExitMainPromptCount $result.Output) | Should -Be 1
        ([regex]::Matches($result.Output, 'Select a supported or development \.NET channel:')).Count | Should -Be 2
        ([regex]::Matches($result.Output, 'Select an end-of-life \.NET channel:')).Count | Should -Be 1
        $result.Output | Should -Match 'S\. Show end-of-life channels'
        $result.Output | Should -Match 'S\. Show supported/development channels'
    }

    It 'rejects A instead of toggling the channel view' {
        $result = Invoke-GlobalExitToolProcess `
            -InputLines @('i', 'a', 'e') `
            -Command $script:ReleaseIndexCommand

        $result.ExitCode | Should -Be 0
        (Get-GlobalExitMainPromptCount $result.Output) | Should -Be 1
        ([regex]::Matches($result.Output, 'Select a supported or development \.NET channel:')).Count | Should -Be 2
        $result.Output | Should -Match 'Invalid selection: a\. Choose 1, S, B, M, or E\.'
        $result.Output | Should -Not -Match 'Select an end-of-life \.NET channel:'
    }

    It 'exits the persistent session directly from SDK version selection' {
        $result = Invoke-GlobalExitToolProcess `
            -InputLines @('i', '1', 'e') `
            -Command $script:ReleaseIndexCommand

        $result.ExitCode | Should -Be 0
        (Get-GlobalExitMainPromptCount $result.Output) | Should -Be 1
        $result.Output | Should -Match 'Available \.NET 10\.0 SDKs:'
        $result.Output | Should -Match 'E\. Exit'
        $result.Output | Should -Not -Match 'Installation cancelled\.'
        $result.Output | Should -Match 'Exiting\.'
    }

    It 'exits the persistent session directly from expanded SDK version selection' {
        $result = Invoke-GlobalExitToolProcess `
            -InputLines @('i', '1', 's', 'e') `
            -Command $script:ReleaseIndexCommand

        $result.ExitCode | Should -Be 0
        (Get-GlobalExitMainPromptCount $result.Output) | Should -Be 1
        $result.Output | Should -Match 'S\. Show all versions'
        $result.Output | Should -Match '10\.0\.400'
        $result.Output | Should -Match 'E\. Exit'
        $result.Output | Should -Match 'Exiting\.'
    }

    It 'exits the persistent session directly from Remove selection' {
        $version = '99.0.100'
        $installDirectory = Join-Path $script:ToolRoot $version
        New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $installDirectory 'dotnet.exe') -Force | Out-Null

        $result = Invoke-GlobalExitToolProcess -InputLines @('r', 'e')

        $result.ExitCode | Should -Be 0
        (Get-GlobalExitMainPromptCount $result.Output) | Should -Be 1
        $result.Output | Should -Match 'E\. Exit'
        $result.Output | Should -Not -Match 'Removal cancelled\.'
        $result.Output | Should -Match 'Exiting\.'
    }

    It 'keeps Q as Cancel for explicit one-shot interactive Install selection' {
        $command = $script:ReleaseIndexCommand.Replace(
            '& $env:ISOLATED_DOTNET_SDK_TOOL_PATH',
            '& $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install')
        $result = Invoke-GlobalExitToolProcess -InputLines @('q') -Command $command

        $result.ExitCode | Should -Be 0
        (Get-GlobalExitMainPromptCount $result.Output) | Should -Be 0
        $result.Output | Should -Match 'Q\. Cancel'
        $result.Output | Should -Match 'Installation cancelled\.'
        $result.Output | Should -Not -Match 'Exiting\.'
    }
}
