Describe 'PowerShell CLI presentation contract' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:ToolScript = Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1'
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-presentation-{0}" -f [guid]::NewGuid())
        $script:TestHome = Join-Path $script:TestRoot 'home'
        $script:SourceCopy = Join-Path $script:TestRoot 'isolated-dotnet-sdk-source.ps1'
        $script:HomeVariableName = if ($IsWindows) { 'USERPROFILE' } else { 'HOME' }
        $script:OriginalHomeValue = [Environment]::GetEnvironmentVariable($script:HomeVariableName, 'Process')

        New-Item -ItemType Directory -Path $script:TestHome -Force | Out-Null
        Copy-Item -LiteralPath $script:ToolScript -Destination $script:SourceCopy -Force
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:TestHome, 'Process')
        $env:ISOLATED_DOTNET_SDK_PRESENTATION_TOOL = $script:SourceCopy
    }

    AfterAll {
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:OriginalHomeValue, 'Process')
        Remove-Item Env:ISOLATED_DOTNET_SDK_PRESENTATION_TOOL -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'renders semantic headings and success distinctly without the CLI-name prefix' {
        $env:PSSTYLE_OUTPUTRENDERING = 'Ansi'
        $output = @(& pwsh -NoProfile -File $script:SourceCopy -Action List 6>&1 | ForEach-Object { [string]$_ })

        $LASTEXITCODE | Should -Be 0
        $text = $output -join [Environment]::NewLine
        $text | Should -Not -Match 'isolated-dotnet-sdk:'
        $text | Should -Match 'Installed \.NET SDKs'
    }

    It 'keeps redirected presentation output ANSI-free and prefix-free' {
        $output = @(& pwsh -NoProfile -Command '$PSStyle.OutputRendering = ''PlainText''; & $env:ISOLATED_DOTNET_SDK_PRESENTATION_TOOL -Action List' 6>&1 | ForEach-Object { [string]$_ })

        $LASTEXITCODE | Should -Be 0
        $text = $output -join [Environment]::NewLine
        $text | Should -Not -Match ([regex]::Escape([char]27 + '['))
        $text | Should -Not -Match 'isolated-dotnet-sdk:'
        $text | Should -Match 'Installed \.NET SDKs'
    }

    It 'keeps failures on the error stream without restoring the CLI-name prefix' {
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
    }

    It 'replaces terminal control characters in invalid-input feedback values' {
        $source = Get-Content -LiteralPath $script:SourceCopy -Raw
        $source | Should -Match '\[regex\]::Replace\(\$Value, ''\[\^\\x20-\\x7E\]'', ''\?''\)'
    }
}