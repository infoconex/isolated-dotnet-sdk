BeforeAll {
    $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:ToolScript = Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1'
    $script:HomeVariableName = if ($IsWindows) { 'USERPROFILE' } else { 'HOME' }

    function Install-TestTool {
        Copy-Item $script:ToolScript $script:SourceCopy -Force
        Add-Content -Path $script:SourceCopy -Value "`n# bootstrap-source-marker"

        & pwsh -NoProfile -File $script:SourceCopy -Action List *> $null
        $LASTEXITCODE | Should -Be 0
    }
}

BeforeEach {
    $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-tests-{0}" -f [guid]::NewGuid())
    $script:TestHome = Join-Path $script:TestRoot 'home'
    $script:ToolRoot = Join-Path $script:TestHome 'dotnet-sdks'
    $script:ToolPath = Join-Path $script:ToolRoot 'isolated-dotnet-sdk.ps1'
    $script:SourceCopy = Join-Path $script:TestRoot 'isolated-dotnet-sdk-source.ps1'
    $script:OriginalHomeValue = [Environment]::GetEnvironmentVariable($script:HomeVariableName, 'Process')
    $script:OriginalNoColor = [Environment]::GetEnvironmentVariable('NO_COLOR', 'Process')

    New-Item -ItemType Directory -Path $script:TestHome -Force | Out-Null
    [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:TestHome, 'Process')
}

AfterEach {
    [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:OriginalHomeValue, 'Process')
    [Environment]::SetEnvironmentVariable('NO_COLOR', $script:OriginalNoColor, 'Process')
    Remove-Item Env:ISOLATED_DOTNET_SDK_EXPECTED_HOME -ErrorAction SilentlyContinue
    Remove-Item Env:ISOLATED_DOTNET_SDK_TOOL_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:ISOLATED_DOTNET_SDK_SOURCE_COPY -ErrorAction SilentlyContinue
    Remove-Item Env:ISOLATED_DOTNET_SDK_LIST_SUCCESS -ErrorAction SilentlyContinue
    Remove-Item Env:ISOLATED_DOTNET_SDK_LIST_INFORMATION -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'PowerShell process-level behavior' {
    It 'uses the isolated home/profile in a child PowerShell process' {
        $env:ISOLATED_DOTNET_SDK_EXPECTED_HOME = $script:TestHome

        & pwsh -NoProfile -Command 'if ($HOME -ne $env:ISOLATED_DOTNET_SDK_EXPECTED_HOME) { [Console]::Error.WriteLine("Child PowerShell HOME did not match the isolated profile."); exit 1 }'

        $LASTEXITCODE | Should -Be 0
    }

    It 'preserves the exact source script during file-based bootstrap' {
        Install-TestTool

        Select-String -Path $script:ToolPath -Pattern '# bootstrap-source-marker' -SimpleMatch -Quiet |
            Should -BeTrue
    }

    It 'lists the isolated SDK root' {
        Install-TestTool

        $listOutput = @(& pwsh -NoProfile -File $script:ToolPath -Action List 2>&1)

        $LASTEXITCODE | Should -Be 0
        ($listOutput -join [Environment]::NewLine) | Should -Match 'Isolated SDKs under'
    }

    It 'keeps presentation output off the success stream and ANSI out of redirected information output' {
        Install-TestTool
        $listSuccessOutputPath = Join-Path $script:TestRoot 'list-success.txt'
        $listInformationOutputPath = Join-Path $script:TestRoot 'list-information.txt'
        $env:ISOLATED_DOTNET_SDK_TOOL_PATH = $script:ToolPath
        $env:ISOLATED_DOTNET_SDK_LIST_SUCCESS = $listSuccessOutputPath
        $env:ISOLATED_DOTNET_SDK_LIST_INFORMATION = $listInformationOutputPath

        & pwsh -NoProfile -Command '$successPath = $env:ISOLATED_DOTNET_SDK_LIST_SUCCESS; $informationPath = $env:ISOLATED_DOTNET_SDK_LIST_INFORMATION; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action List 1> $successPath 6> $informationPath'
        $LASTEXITCODE | Should -Be 0

        $listSuccessOutput = if (Test-Path -LiteralPath $listSuccessOutputPath) {
            Get-Content -LiteralPath $listSuccessOutputPath -Raw
        }
        else {
            ''
        }
        [string]::IsNullOrWhiteSpace($listSuccessOutput) | Should -BeTrue

        $listInformationOutput = Get-Content -LiteralPath $listInformationOutputPath -Raw
        $listInformationOutput | Should -Match 'Isolated SDKs under'
        $listInformationOutput | Should -Match 'None'
        $listInformationOutput.Contains([char]27) | Should -BeFalse
    }

    It 'uses informational and success colors when ANSI rendering is requested' {
        Install-TestTool
        $env:ISOLATED_DOTNET_SDK_SOURCE_COPY = $script:SourceCopy

        & pwsh -NoProfile -Command '$PSStyle.OutputRendering = "Ansi"; $output = @(& $env:ISOLATED_DOTNET_SDK_SOURCE_COPY -Action List 6>&1); $text = $output -join [Environment]::NewLine; $expectedInfoPrefix = "$($PSStyle.Foreground.Cyan)isolated-dotnet-sdk:$($PSStyle.Reset)"; $expectedSuccessPrefix = "$($PSStyle.Foreground.Green)isolated-dotnet-sdk:$($PSStyle.Reset)"; if (-not $text.Contains($expectedInfoPrefix)) { exit 1 }; if (-not $text.Contains("$expectedSuccessPrefix Tool installed.")) { exit 1 }'

        $LASTEXITCODE | Should -Be 0
    }

    It 'honors NO_COLOR without ANSI escape sequences' {
        Install-TestTool
        $env:ISOLATED_DOTNET_SDK_TOOL_PATH = $script:ToolPath
        [Environment]::SetEnvironmentVariable('NO_COLOR', '1', 'Process')

        & pwsh -NoProfile -Command '$output = @(& $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action List 6>&1); $text = $output -join [Environment]::NewLine; if ($PSStyle.OutputRendering -ne "PlainText") { exit 1 }; if ($text.Contains([char]27)) { exit 1 }'

        $LASTEXITCODE | Should -Be 0
    }

    It 'rejects an invalid SDK version' {
        Install-TestTool

        & pwsh -NoProfile -File $script:ToolPath -Action Install -Version 'invalid/version' -Yes *> $null

        $LASTEXITCODE | Should -Not -Be 0
    }
}
