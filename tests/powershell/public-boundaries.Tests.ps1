Describe 'PowerShell public selection and list boundaries' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:ToolScript = Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1'
        $script:HomeVariableName = if ($IsWindows) { 'USERPROFILE' } else { 'HOME' }
    }

    BeforeEach {
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-public-boundaries-{0}" -f [guid]::NewGuid())
        $script:TestHome = Join-Path $script:TestRoot 'home'
        $script:ToolRoot = Join-Path $script:TestHome 'dotnet-sdks'
        $script:ToolPath = Join-Path $script:ToolRoot 'isolated-dotnet-sdk.ps1'
        $script:OriginalHomeValue = [Environment]::GetEnvironmentVariable($script:HomeVariableName, 'Process')

        New-Item -ItemType Directory -Path $script:ToolRoot -Force | Out-Null
        Copy-Item -LiteralPath $script:ToolScript -Destination $script:ToolPath -Force
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:TestHome, 'Process')
        $env:ISOLATED_DOTNET_SDK_TOOL_PATH = $script:ToolPath
    }

    AfterEach {
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:OriginalHomeValue, 'Process')
        Remove-Item Env:ISOLATED_DOTNET_SDK_TOOL_PATH -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'selects Install when SdkVersion is supplied without Action' {
        $failureOutput = @(& pwsh -NoProfile -Command '
            function Invoke-WebRequest { throw "install-download-boundary" }
            & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -SdkVersion 99.0.100 -Yes
        ' 6>&1 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        $text = $failureOutput -join [Environment]::NewLine
        $text | Should -Match 'Target SDK: 99\.0\.100'
        $text | Should -Match 'install-download-boundary'
        $text | Should -Not -Match 'What would you like to do\?'
    }

    It 'treats Remove with no installed SDKs as successful no-change' {
        $removeOutput = @(& pwsh -NoProfile -File $script:ToolPath -Action Remove 6>&1 2>&1)

        $LASTEXITCODE | Should -Be 0
        $text = $removeOutput -join [Environment]::NewLine
        $text | Should -Match 'No isolated SDKs are installed under'
        $text | Should -Match 'Removal cancelled\.'
    }

    It 'treats explicit removal picker cancellation as successful no-change' {
        $version = '99.0.100'
        $installDirectory = Join-Path $script:ToolRoot $version
        New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $installDirectory 'dotnet.exe') -Force | Out-Null

        $removeOutput = @(& pwsh -NoProfile -Command '
            function Read-Host { param([string]$Prompt) return "q" }
            & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Remove
        ' 6>&1 2>&1)

        $LASTEXITCODE | Should -Be 0
        ($removeOutput -join [Environment]::NewLine) | Should -Match 'Removal cancelled\.'
        Test-Path -LiteralPath $installDirectory | Should -BeTrue
    }

    It 'fails when required removal picker input is unavailable' {
        $version = '99.0.100'
        $installDirectory = Join-Path $script:ToolRoot $version
        New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $installDirectory 'dotnet.exe') -Force | Out-Null

        $removeOutput = @(& pwsh -NoProfile -NonInteractive -File $script:ToolPath -Action Remove 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        ($removeOutput -join [Environment]::NewLine) | Should -Match 'Interactive input is unavailable\.'
        ($removeOutput -join [Environment]::NewLine) | Should -Not -Match 'Removal cancelled\.'
        Test-Path -LiteralPath $installDirectory | Should -BeTrue
    }

    It 'lists SDK directories and ignores non-SDK tool artifacts' {
        $version = '99.0.100'
        $installDirectory = Join-Path $script:ToolRoot $version
        New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $installDirectory 'dotnet.exe') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:ToolRoot 'not-an-sdk') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:ToolRoot '.install-99.0.200.leftover') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:ToolRoot '.sdk-payload-99.0.200.leftover.zip') -Value 'payload'

        $listOutput = @(& pwsh -NoProfile -File $script:ToolPath -Action List 6>&1 2>&1)

        $LASTEXITCODE | Should -Be 0
        $text = $listOutput -join [Environment]::NewLine
        $text | Should -Match ([regex]::Escape("99.0.100  $installDirectory"))
        $text | Should -Not -Match 'not-an-sdk'
        $text | Should -Not -Match '\.sdk-payload-99\.0\.200\.leftover\.zip'
        $text | Should -Not -Match '\.install-99\.0\.200\.leftover'
    }
}
