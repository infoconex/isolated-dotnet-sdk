Describe 'PowerShell CLI presentation contract' {
    BeforeEach {
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-presentation-{0}" -f [guid]::NewGuid())
        $script:TestHome = Join-Path $script:TestRoot 'home'
        $script:SourceCopy = Join-Path $script:TestRoot 'isolated-dotnet-sdk-source.ps1'
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:HomeVariableName = if ($IsWindows) { 'USERPROFILE' } else { 'HOME' }
        $script:OriginalHomeValue = [Environment]::GetEnvironmentVariable($script:HomeVariableName, 'Process')
        $script:OriginalNoColor = [Environment]::GetEnvironmentVariable('NO_COLOR', 'Process')

        New-Item -ItemType Directory -Path $script:TestHome -Force | Out-Null
        Copy-Item (Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1') $script:SourceCopy -Force
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:TestHome, 'Process')
    }

    AfterEach {
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:OriginalHomeValue, 'Process')
        [Environment]::SetEnvironmentVariable('NO_COLOR', $script:OriginalNoColor, 'Process')
        Remove-Item Env:ISOLATED_DOTNET_SDK_PRESENTATION_SOURCE -ErrorAction SilentlyContinue
        Remove-Item Env:ISOLATED_DOTNET_SDK_PRESENTATION_TOOL -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'renders semantic headings and success distinctly without the CLI-name prefix' {
        $env:ISOLATED_DOTNET_SDK_PRESENTATION_SOURCE = $script:SourceCopy

        & pwsh -NoProfile -Command '$PSStyle.OutputRendering = "Ansi"; $output = @(& $env:ISOLATED_DOTNET_SDK_PRESENTATION_SOURCE -Action List 6>&1); $text = $output -join [Environment]::NewLine; $heading = "$($PSStyle.Foreground.Cyan)Installed .NET SDKs$($PSStyle.Reset)"; $isolatedHeading = "$($PSStyle.Foreground.Cyan)Isolated SDKs:$($PSStyle.Reset)"; $systemHeading = "$($PSStyle.Foreground.Cyan)System SDKs:$($PSStyle.Reset)"; $success = "$($PSStyle.Foreground.Green)Tool installed.$($PSStyle.Reset)"; if (-not $text.Contains($heading)) { exit 1 }; if (-not $text.Contains($isolatedHeading)) { exit 1 }; if (-not $text.Contains($systemHeading)) { exit 1 }; if (-not $text.Contains($success)) { exit 1 }; if ($text.Contains("isolated-dotnet-sdk:")) { exit 1 }; if ($text.Contains("$($PSStyle.Foreground.Cyan)None$($PSStyle.Reset)")) { exit 1 }'

        $LASTEXITCODE | Should -Be 0
    }

    It 'keeps redirected presentation output ANSI-free and prefix-free' {
        $output = @(& pwsh -NoProfile -File $script:SourceCopy -Action List 6>&1 | ForEach-Object { [string]$_ })

        $LASTEXITCODE | Should -Be 0
        $text = $output -join [Environment]::NewLine
        $text.Contains([char]27) | Should -BeFalse
        $text | Should -Not -Match 'isolated-dotnet-sdk:'
        $text | Should -Match 'Installed \.NET SDKs'
        $text | Should -Match 'Isolated SDKs:'
        $text | Should -Match 'System SDKs:'
    }

    It 'keeps failures on the error stream without restoring the CLI-name prefix' {
        & pwsh -NoProfile -File $script:SourceCopy -Action List *> $null
        $LASTEXITCODE | Should -Be 0
        $toolPath = Join-Path (Join-Path $script:TestHome 'dotnet-sdks') 'isolated-dotnet-sdk.ps1'
        $env:ISOLATED_DOTNET_SDK_PRESENTATION_TOOL = $toolPath

        $failure = @(& pwsh -NoProfile -Command '& $env:ISOLATED_DOTNET_SDK_PRESENTATION_TOOL -Action NotARealAction' 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        ($failure -join [Environment]::NewLine) | Should -Match 'Invalid action: NotARealAction'
        ($failure -join [Environment]::NewLine) | Should -Not -Match 'isolated-dotnet-sdk:'
    }

    It 'separates bootstrap output from invocation and saved-tool output' {
        $output = @(& pwsh -NoProfile -File $script:SourceCopy -Action List 6>&1 | ForEach-Object { [string]$_ })

        $LASTEXITCODE | Should -Be 0
        $text = $output -join [Environment]::NewLine
        $text | Should -Match '^\r?\nInstalling tool to '
        $text | Should -Match 'Tool installed\.\r?\n\r?\nInstalled \.NET SDKs'
    }

    It 'defines a semantic accent role for labels and picker metadata' {
        $source = Get-Content -LiteralPath $script:SourceCopy -Raw

        $source | Should -Match "ValidateSet\('Heading', 'Accent', 'Success'\)"
        $source | Should -Match 'function Write-ToolLabelValue'
        $source | Should -Match 'function Format-ToolAccent'
        $source | Should -Match '(?s)\$SelectedInteractively = \[string\]::IsNullOrWhiteSpace\(\$script:SdkVersion\).*?if \(\$SelectedInteractively\) \{\s*Write-ToolDisplay'
    }

    It 'replaces terminal control characters in invalid-input feedback values' {
        $source = Get-Content -LiteralPath $script:SourceCopy -Raw
        $source | Should -Match '\[regex\]::Replace\(\$Value, ''\[\^\\x20-\\x7E\]'', ''\?''\)'
    }
}
