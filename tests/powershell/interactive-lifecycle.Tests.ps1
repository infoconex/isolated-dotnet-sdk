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

        function Get-AcknowledgementPromptCount {
            param([string]$Output)
            return ([regex]::Matches($Output, 'Press Enter to return to [^\r\n]+\.\.\.')).Count
        }

        function Install-FakeInteractiveHost {
            param([string]$Version)

            $installDirectory = Join-Path $script:ToolRoot $Version
            New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
            Copy-Item `
                -Path (Join-Path $env:ISOLATED_DOTNET_SDK_SHARED_FAKE_HOST_ROOT '*') `
                -Destination $installDirectory `
                -Recurse `
                -Force
            $env:FAKE_DOTNET_SDK_VERSION = $Version
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
        Remove-Item Env:FAKE_DOTNET_SDK_VERSION -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'waits for Enter only when persistent input and output are terminal-capable' {
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:ToolScript,
            [ref]$tokens,
            [ref]$parseErrors)
        $parseErrors | Should -BeNullOrEmpty

        $functionAst = $ast.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Wait-ForInteractiveResultAcknowledgement'
            }, $true)
        $functionAst | Should -Not -BeNullOrEmpty
        $functionDefinition = [scriptblock]::Create($functionAst.Extent.Text)
        . $functionDefinition

        $script:InteractiveSession = $true
        $script:AcknowledgementOutput = [System.Collections.Generic.List[string]]::new()
        $script:AcknowledgementReadCount = 0

        function Write-ToolDisplay {
            param(
                [AllowEmptyString()]
                [string]$Message = ''
            )
            $script:AcknowledgementOutput.Add($Message)
        }

        function Read-ToolInput {
            $script:AcknowledgementReadCount++
            return ''
        }

        Wait-ForInteractiveResultAcknowledgement -Destination 'Verify' -InputRedirected:$false -OutputRedirected:$false

        $script:AcknowledgementOutput | Should -Contain 'Press Enter to return to Verify...'
        $script:AcknowledgementReadCount | Should -Be 1

        $script:AcknowledgementOutput.Clear()
        $script:AcknowledgementReadCount = 0
        Wait-ForInteractiveResultAcknowledgement -InputRedirected:$true -OutputRedirected:$false
        Wait-ForInteractiveResultAcknowledgement -InputRedirected:$false -OutputRedirected:$true

        $script:AcknowledgementOutput.Count | Should -Be 0
        $script:AcknowledgementReadCount | Should -Be 0
    }

    It 'clears only a capable persistent terminal and ignores clear failures' {
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:ToolScript,
            [ref]$tokens,
            [ref]$parseErrors)
        $parseErrors | Should -BeNullOrEmpty

        $functionAst = $ast.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Clear-InteractiveScreen'
            }, $true)
        $functionAst | Should -Not -BeNullOrEmpty
        . ([scriptblock]::Create($functionAst.Extent.Text))

        $script:InteractiveSession = $true
        $script:ClearCallCount = 0
        function Clear-Host { $script:ClearCallCount++ }

        Clear-InteractiveScreen -InputRedirected:$false -OutputRedirected:$false
        $script:ClearCallCount | Should -Be 1

        Clear-InteractiveScreen -InputRedirected:$true -OutputRedirected:$false
        Clear-InteractiveScreen -InputRedirected:$false -OutputRedirected:$true
        $script:InteractiveSession = $false
        Clear-InteractiveScreen -InputRedirected:$false -OutputRedirected:$false
        $script:ClearCallCount | Should -Be 1

        $script:InteractiveSession = $true
        function Clear-Host { throw 'unsupported terminal host' }
        { Clear-InteractiveScreen -InputRedirected:$false -OutputRedirected:$false } | Should -Not -Throw
    }

    It 'captured persistent List returns to Main without acknowledgement' {
        $result = Invoke-InteractiveToolProcess -ToolPath $script:ToolPath -InputLines @('l', 'e')

        $result.ExitCode | Should -Be 0
        (Get-MainPromptCount $result.Output) | Should -Be 2
        (Get-AcknowledgementPromptCount $result.Output) | Should -Be 0
        $result.Output | Should -Match 'L\. List installed SDKs'
        $result.Output | Should -Match 'Isolated SDKs:'
        $result.Output | Should -Match 'System SDKs:'
        $result.Output | Should -Match 'Exiting\.'
        $result.Output.Contains([char]27) | Should -BeFalse
    }

    It 'captured persistent Remove no-change returns without acknowledgement' {
        $result = Invoke-InteractiveToolProcess -ToolPath $script:ToolPath -InputLines @('r', 'e')

        $result.ExitCode | Should -Be 0
        (Get-MainPromptCount $result.Output) | Should -Be 2
        (Get-AcknowledgementPromptCount $result.Output) | Should -Be 0
        $result.Output | Should -Match 'No isolated SDKs are installed'
        $result.Output | Should -Match 'Removal cancelled\.'
    }

    It 'keeps explicit List one-shot without acknowledgement' {
        $result = Invoke-InteractiveToolProcess `
            -ToolPath $script:ToolPath `
            -Command '& $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action List'

        $result.ExitCode | Should -Be 0
        (Get-MainPromptCount $result.Output) | Should -Be 0
        (Get-AcknowledgementPromptCount $result.Output) | Should -Be 0
        $result.Output | Should -Match 'Installed \.NET SDKs'
    }

    It 'does not mask an interactive operational failure with later Exit input' {
        $command = @'
function Invoke-RestMethod { throw 'transport failure' }
& $env:ISOLATED_DOTNET_SDK_TOOL_PATH
'@
        $result = Invoke-InteractiveToolProcess `
            -ToolPath $script:ToolPath `
            -InputLines @('i', 'e') `
            -Command $command

        $result.ExitCode | Should -Not -Be 0
        (Get-MainPromptCount $result.Output) | Should -Be 1
        (Get-AcknowledgementPromptCount $result.Output) | Should -Be 0
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
            -InputLines @('i', 'b', 'e') `
            -Command $command

        $result.ExitCode | Should -Be 0
        (Get-MainPromptCount $result.Output) | Should -Be 2
        (Get-AcknowledgementPromptCount $result.Output) | Should -Be 0
        $result.Output | Should -Match 'B\. Back to Main'
    }


    It 'returns an acknowledged Install result to the selected channel SDK list' {
        $version = '10.0.401'
        Install-FakeInteractiveHost -Version $version

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
& $env:ISOLATED_DOTNET_SDK_TOOL_PATH
'@
        $result = Invoke-InteractiveToolProcess `
            -ToolPath $script:ToolPath `
            -InputLines @('i', '1', '1', 'b', 'b', 'e') `
            -Command $command

        $result.ExitCode | Should -Be 0
        ([regex]::Matches($result.Output, 'Available \.NET 10\.0 SDKs:')).Count | Should -Be 2
        ([regex]::Matches($result.Output, 'Select a supported or development \.NET channel:')).Count | Should -Be 2
        (Get-MainPromptCount $result.Output) | Should -Be 2
        (Get-AcknowledgementPromptCount $result.Output) | Should -Be 0
    }

    It 'captured already-installed interactive Install returns without acknowledgement' {
        $version = '99.0.100'
        Install-FakeInteractiveHost -Version $version

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
            -InputLines @('i', 'm', $version, 'b', 'e') `
            -Command $command

        $result.ExitCode | Should -Be 0
        (Get-MainPromptCount $result.Output) | Should -Be 2
        (Get-AcknowledgementPromptCount $result.Output) | Should -Be 0
        $result.Output | Should -Match 'Isolated SDK:.*Already installed'
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

        $result = Invoke-InteractiveToolProcess -ToolPath $script:ToolPath -InputLines @('r', 'b', 'e')

        $result.ExitCode | Should -Be 0
        (Get-MainPromptCount $result.Output) | Should -Be 2
        $result.Output | Should -Match 'B\. Back to Main'
        $result.Output | Should -Not -Match 'Continue\?'
    }

    It 'returns a completed Remove result to the Remove SDK list' {
        foreach ($version in @('99.0.100', '98.0.100')) {
            Install-FakeInteractiveHost -Version $version
        }

        $result = Invoke-InteractiveToolProcess `
            -ToolPath $script:ToolPath `
            -InputLines @('r', '1', 'b', 'e') `
            -Command '& $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Yes'

        $result.ExitCode | Should -Be 0
        ([regex]::Matches($result.Output, 'Select an isolated SDK to remove:')).Count | Should -Be 2
        $result.Output | Should -Match 'Isolated SDK 99\.0\.100 was removed\.'
        (Get-MainPromptCount $result.Output) | Should -Be 2
        (Get-AcknowledgementPromptCount $result.Output) | Should -Be 0
    }

    It 'sorts Remove choices newest to oldest' {
        foreach ($version in @('8.0.425', '11.0.100-rc.1.26425.128', '10.0.401')) {
            $installDirectory = Join-Path $script:ToolRoot $version
            New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $installDirectory 'dotnet.exe') -Force | Out-Null
        }

        $result = Invoke-InteractiveToolProcess -ToolPath $script:ToolPath -InputLines @('r', 'b', 'e')

        $result.ExitCode | Should -Be 0
        $removeStart = $result.Output.IndexOf('Select an isolated SDK to remove:')
        $removeEnd = $result.Output.IndexOf('B. Back to Main', $removeStart)
        $removeSection = $result.Output.Substring($removeStart, $removeEnd - $removeStart)
        $removeSection | Should -Match '1\. 11\.0\.100-rc\.1\.26425\.128'
        $removeSection | Should -Match '2\. 10\.0\.401'
        $removeSection | Should -Match '3\. 8\.0\.425'
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
        $result.Output | Should -Match '1\. 10\.0\.401 \(latest'
        $result.Output | Should -Match '2\. 10\.0\.305'
        $result.Output | Should -Match '3\. 10\.0\.201'
        $result.Output | Should -Match 'S\. Show all versions'
        ([regex]::Matches($result.Output, '10\.0\.400')).Count | Should -Be 1
        ([regex]::Matches($result.Output, '10\.0\.303')).Count | Should -Be 1
    }

    It 'distinguishes blank and nonblank invalid Main selections' {
        $result = Invoke-InteractiveToolProcess `
            -ToolPath $script:ToolPath `
            -InputLines @('', '6', 'e') `
            -Command '& $env:ISOLATED_DOTNET_SDK_TOOL_PATH *>&1'

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'A selection is required\. Choose I, R, L, V, A, or E\.'
        $result.Output | Should -Match 'Invalid selection: 6\. Choose I, R, L, V, A, or E\.'
        $result.Output | Should -Match 'A selection is required\. Choose I, R, L, V, A, or E\.\r?\n\r?\nIsolated \.NET SDK development \(main\)\r?\n\r?\nWhat would you like to do\?'
        $result.Output | Should -Match 'Invalid selection: 6\. Choose I, R, L, V, A, or E\.\r?\n\r?\nIsolated \.NET SDK development \(main\)\r?\n\r?\nWhat would you like to do\?'
    }

    It 'reports Remove choices and separates retry feedback from redraw' {
        $version = '99.0.100'
        $installDirectory = Join-Path $script:ToolRoot $version
        New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $installDirectory 'dotnet.exe') -Force | Out-Null

        $result = Invoke-InteractiveToolProcess `
            -ToolPath $script:ToolPath `
            -InputLines @('r', '', '6', 'b', 'e') `
            -Command '& $env:ISOLATED_DOTNET_SDK_TOOL_PATH *>&1'

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'A selection is required\. Choose 1, B, or E\.'
        $result.Output | Should -Match 'Invalid selection: 6\. Choose 1, B, or E\.'
        $result.Output | Should -Match 'A selection is required\. Choose 1, B, or E\.\r?\n\r?\nSelect an isolated SDK to remove:'
        $result.Output | Should -Match 'Invalid selection: 6\. Choose 1, B, or E\.\r?\n\r?\nSelect an isolated SDK to remove:'
    }

}
