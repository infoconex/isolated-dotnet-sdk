Describe 'PowerShell process-level behavior' {
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
        Remove-Item Env:ISOLATED_DOTNET_SDK_FAKE_BIN -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

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

    It 'propagates a failing saved child tool through file-based bootstrap' {
        Copy-Item $script:ToolScript $script:SourceCopy -Force

        & pwsh -NoProfile -File $script:SourceCopy -Action Install -SdkVersion 'invalid/version' -Yes *> $null

        $LASTEXITCODE | Should -Not -Be 0
    }

    It 'fails with context when system SDK inventory exits nonzero' {
        Install-TestTool
        $fakeBin = Join-Path $script:TestRoot 'system-dotnet-fake-bin'
        New-Item -ItemType Directory -Path $fakeBin -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $fakeBin 'dotnet.cmd') -Value "@echo off`r`nexit /b 71`r`n"
        $env:ISOLATED_DOTNET_SDK_TOOL_PATH = $script:ToolPath
        $env:ISOLATED_DOTNET_SDK_FAKE_BIN = $fakeBin

        $failureOutput = @(& pwsh -NoProfile -Command '$env:PATH = "$env:ISOLATED_DOTNET_SDK_FAKE_BIN;$env:PATH"; function Invoke-WebRequest { throw "continued-to-download" }; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -SdkVersion 99.0.100 -Yes' 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        ($failureOutput -join [Environment]::NewLine) | Should -Match 'Unable to list SDKs through the system dotnet host with exit code 71\.'
        ($failureOutput -join [Environment]::NewLine) | Should -Not -Match 'continued-to-download'
        ($failureOutput -join [Environment]::NewLine) | Should -Not -Match 'installation completed successfully'
    }

    It 'lists the isolated SDK root' {
        Install-TestTool

        $listOutput = @(& pwsh -NoProfile -File $script:ToolPath -Action List 2>&1)

        $LASTEXITCODE | Should -Be 0
        ($listOutput -join [Environment]::NewLine) | Should -Match 'Installed \.NET SDKs'
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
        $listInformationOutput | Should -Match 'Isolated SDKs:'
        $listInformationOutput | Should -Match 'System SDKs:'
        $listInformationOutput | Should -Match 'None'
        $listInformationOutput | Should -Not -Match 'isolated-dotnet-sdk:'
        $listInformationOutput.Contains([char]27) | Should -BeFalse
    }

    It 'uses heading and success colors when ANSI rendering is requested' {
        Install-TestTool
        $env:ISOLATED_DOTNET_SDK_SOURCE_COPY = $script:SourceCopy

        & pwsh -NoProfile -Command '$PSStyle.OutputRendering = "Ansi"; $output = @(& $env:ISOLATED_DOTNET_SDK_SOURCE_COPY -Action List 6>&1); $text = $output -join [Environment]::NewLine; $expectedHeading = "$($PSStyle.Foreground.Cyan)Installed .NET SDKs$($PSStyle.Reset)"; $expectedSuccess = "$($PSStyle.Foreground.Green)Tool installed.$($PSStyle.Reset)"; if (-not $text.Contains($expectedHeading)) { exit 1 }; if (-not $text.Contains($expectedSuccess)) { exit 1 }; if ($text.Contains("isolated-dotnet-sdk:")) { exit 1 }'

        $LASTEXITCODE | Should -Be 0
    }

    It 'honors NO_COLOR without ANSI escape sequences' {
        Install-TestTool
        $env:ISOLATED_DOTNET_SDK_TOOL_PATH = $script:ToolPath
        [Environment]::SetEnvironmentVariable('NO_COLOR', '1', 'Process')

        & pwsh -NoProfile -Command '$output = @(& $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action List 6>&1); $text = $output -join [Environment]::NewLine; if ($PSStyle.OutputRendering -ne "PlainText") { exit 1 }; if ($text.Contains([char]27)) { exit 1 }; if ($text.Contains("isolated-dotnet-sdk:")) { exit 1 }'

        $LASTEXITCODE | Should -Be 0
    }

    It 'rejects an invalid SDK version' {
        Install-TestTool

        & pwsh -NoProfile -File $script:ToolPath -Action Install -SdkVersion 'invalid/version' -Yes *> $null

        $LASTEXITCODE | Should -Not -Be 0
    }

    It 'reports release-index network failure with deterministic metadata context' {
        Install-TestTool
        $env:ISOLATED_DOTNET_SDK_TOOL_PATH = $script:ToolPath

        $metadataOutput = @(& pwsh -NoProfile -Command 'function Invoke-RestMethod { throw "transport-specific detail" }; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install' 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        ($metadataOutput -join [Environment]::NewLine) | Should -Match 'Unable to load .NET release metadata from Microsoft\.'
        ($metadataOutput -join [Environment]::NewLine) | Should -Not -Match 'transport-specific detail'
    }

    It '-Yes does not bypass unresolved install selection' {
        Install-TestTool
        $env:ISOLATED_DOTNET_SDK_TOOL_PATH = $script:ToolPath

        $failureOutput = @(& pwsh -NoProfile -NonInteractive -Command '$releaseIndex = [pscustomobject]@{ "releases-index" = @([pscustomobject]@{ "channel-version" = "99.0"; "latest-sdk" = "99.0.100"; "support-phase" = "active"; "release-type" = "sts"; "releases.json" = "https://example.invalid/releases.json" }) }; function Invoke-RestMethod { return $releaseIndex }; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -Yes' 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        ($failureOutput -join [Environment]::NewLine) | Should -Match 'Interactive input is unavailable\.'
        ($failureOutput -join [Environment]::NewLine) | Should -Match 'Select a supported or development .NET channel:'
    }

    It 'reports unavailable interactive input with repository-owned context' {
        Install-TestTool
        $version = '99.0.100-input-test'
        $installDirectory = Join-Path $script:ToolRoot $version
        New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $installDirectory 'dotnet.exe') -Force | Out-Null

        $failureOutput = @(& pwsh -NoProfile -NonInteractive -File $script:ToolPath -Action Remove -SdkVersion $version 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        ($failureOutput -join [Environment]::NewLine) | Should -Match 'Interactive input is unavailable\.'
        Test-Path -LiteralPath $installDirectory | Should -BeTrue
    }

    It 'reports release-metadata download failure with repository-owned context' {
        Install-TestTool
        $env:ISOLATED_DOTNET_SDK_TOOL_PATH = $script:ToolPath

        $failureOutput = @(& pwsh -NoProfile -Command 'function Invoke-WebRequest { throw "transport-specific-metadata-detail" }; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -SdkVersion 99.0.100 -Yes' 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        ($failureOutput -join [Environment]::NewLine) | Should -Match "Unable to load valid Microsoft release metadata for SDK 99\.0\.100"
        ($failureOutput -join [Environment]::NewLine) | Should -Not -Match 'installation completed successfully'
    }

    It 'rejects a version with an explicit List action' {
        Install-TestTool

        $failureOutput = @(& pwsh -NoProfile -File $script:ToolPath -Action List -SdkVersion 99.0.100 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        ($failureOutput -join [Environment]::NewLine) | Should -Match 'Version.*supported only with.*Install, Remove, or Verify'
        ($failureOutput -join [Environment]::NewLine) | Should -Not -Match 'Isolated SDKs under'
    }
}
