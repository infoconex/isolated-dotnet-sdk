Describe 'PowerShell interactive lifecycle' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:ToolScript = Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1'

        function Invoke-InteractiveToolProcess {
            param(
                [string]$ToolPath,
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
            $startInfo.Environment['ISOLATED_DOTNET_SDK_TOOL_PATH'] = $ToolPath
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

            $output = $stdoutTask.GetAwaiter().GetResult() + $stderrTask.GetAwaiter().GetResult()
            return [pscustomobject]@{
                ExitCode = $process.ExitCode
                Output = $output
            }
        }

        function Get-MainPromptCount {
            param([string]$Output)
            return ([regex]::Matches($Output, 'What would you like to do\?')).Count
        }
    }

    BeforeEach {
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-interactive-{0}" -f [guid]::NewGuid())
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
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'returns to Main after interactive List and exits explicitly' {
        $result = Invoke-InteractiveToolProcess -ToolPath $script:ToolPath -InputLines @('3', '4')

        $result.ExitCode | Should -Be 0
        (Get-MainPromptCount $result.Output) | Should -Be 2
        $result.Output | Should -Match 'Isolated SDKs under'
        $result.Output | Should -Match 'Exiting\.'
    }

    It 'returns to Main after normal interactive Remove no-change' {
        $result = Invoke-InteractiveToolProcess -ToolPath $script:ToolPath -InputLines @('2', '4')

        $result.ExitCode | Should -Be 0
        (Get-MainPromptCount $result.Output) | Should -Be 2
        $result.Output | Should -Match 'No isolated SDKs are installed'
        $result.Output | Should -Match 'Removal cancelled\.'
    }

    It 'keeps explicit List one-shot' {
        $result = Invoke-InteractiveToolProcess `
            -ToolPath $script:ToolPath `
            -Command '& $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action List'

        $result.ExitCode | Should -Be 0
        (Get-MainPromptCount $result.Output) | Should -Be 0
        $result.Output | Should -Match 'Isolated SDKs under'
    }

    It 'does not mask an interactive operational failure with later Exit input' {
        $command = @'
function Invoke-RestMethod { throw 'transport failure' }
& $env:ISOLATED_DOTNET_SDK_TOOL_PATH
'@
        $result = Invoke-InteractiveToolProcess `
            -ToolPath $script:ToolPath `
            -InputLines @('1', '4') `
            -Command $command

        $result.ExitCode | Should -Not -Be 0
        (Get-MainPromptCount $result.Output) | Should -Be 1
        $result.Output | Should -Match 'Unable to load .NET release metadata from Microsoft\.'
        $result.Output | Should -Not -Match 'Exiting\.'
    }

    It 'returns from Install channel selection to Main with Back' {
        $command = @'
$releaseIndex = [pscustomobject]@{
    'releases-index' = @([pscustomobject]@{
        'channel-version' = '10.0'
        'latest-sdk' = '10.0.401'
        'support-phase' = 'active'
        'release-type' = 'lts'
        'releases.json' = 'https://example.invalid/10.0/releases.json'
    })
}
function Invoke-RestMethod { return $releaseIndex }
& $env:ISOLATED_DOTNET_SDK_TOOL_PATH
'@
        $result = Invoke-InteractiveToolProcess `
            -ToolPath $script:ToolPath `
            -InputLines @('1', 'b', '4') `
            -Command $command

        $result.ExitCode | Should -Be 0
        (Get-MainPromptCount $result.Output) | Should -Be 2
        $result.Output | Should -Match 'B\. Back to Main'
    }

    It 'returns from Install SDK selection to channel selection with Back' {
        $command = @'
$releaseIndex = [pscustomobject]@{
    'releases-index' = @([pscustomobject]@{
        'channel-version' = '10.0'
        'latest-sdk' = '10.0.401'
        'support-phase' = 'active'
        'release-type' = 'lts'
        'releases.json' = 'https://example.invalid/10.0/releases.json'
    })
}
$channelMetadata = [pscustomobject]@{
    releases = @([pscustomobject]@{ sdk = [pscustomobject]@{ version = '10.0.401' } })
}
function Invoke-RestMethod {
    param($Uri)
    if ($Uri -like '*releases-index.json') { return $releaseIndex }
    return $channelMetadata
}
& $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install
'@
        $result = Invoke-InteractiveToolProcess `
            -ToolPath $script:ToolPath `
            -InputLines @('1', 'b', 'q') `
            -Command $command

        $result.ExitCode | Should -Be 0
        ([regex]::Matches($result.Output, 'Select a supported or development \.NET channel:')).Count |
            Should -Be 2
        $result.Output | Should -Match 'B\. Back to \.NET channels'
    }

    It 'returns from Remove SDK selection to Main with Back' {
        $version = '99.0.100'
        $installDirectory = Join-Path $script:ToolRoot $version
        New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $installDirectory 'dotnet.exe') -Force | Out-Null

        $result = Invoke-InteractiveToolProcess -ToolPath $script:ToolPath -InputLines @('2', 'b', '4')

        $result.ExitCode | Should -Be 0
        (Get-MainPromptCount $result.Output) | Should -Be 2
        $result.Output | Should -Match 'B\. Back to Main'
        $result.Output | Should -Not -Match 'Continue\?'
    }

    It 'shows latest and newest feature bands before older servicing versions' {
        $command = @'
$releaseIndex = [pscustomobject]@{
    'releases-index' = @([pscustomobject]@{
        'channel-version' = '10.0'
        'latest-sdk' = '10.0.401'
        'support-phase' = 'active'
        'release-type' = 'lts'
        'releases.json' = 'https://example.invalid/10.0/releases.json'
    })
}
$channelMetadata = [pscustomobject]@{
    releases = @(
        [pscustomobject]@{ sdk = [pscustomobject]@{ version = '10.0.303' } },
        [pscustomobject]@{ sdk = [pscustomobject]@{ version = '10.0.401' } },
        [pscustomobject]@{ sdk = [pscustomobject]@{ version = '10.0.201' } },
        [pscustomobject]@{ sdk = [pscustomobject]@{ version = '10.0.400' } },
        [pscustomobject]@{ sdk = [pscustomobject]@{ version = '10.0.305' } }
    )
}
function Invoke-RestMethod {
    param($Uri)
    if ($Uri -like '*releases-index.json') { return $releaseIndex }
    return $channelMetadata
}
& $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install
'@
        $result = Invoke-InteractiveToolProcess `
            -ToolPath $script:ToolPath `
            -InputLines @('1', 's', 'q') `
            -Command $command

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match '1\. 10\.0\.401 \(latest\)'
        $result.Output | Should -Match '2\. 10\.0\.305'
        $result.Output | Should -Match '3\. 10\.0\.201'
        $result.Output | Should -Match 'S\. Show all versions'
        ([regex]::Matches($result.Output, '10\.0\.400')).Count | Should -Be 1
        ([regex]::Matches($result.Output, '10\.0\.303')).Count | Should -Be 1
    }
}
