Describe 'PowerShell cross-platform path behavior' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:ToolScript = Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1'
        $script:HomeVariableName = if ($IsWindows) { 'USERPROFILE' } else { 'HOME' }
    }

    BeforeEach {
        $script:TestRoot = Join-Path `
            ([System.IO.Path]::GetTempPath()) `
            ("isolated-dotnet-sdk-cross-platform-{0}" -f [guid]::NewGuid())
        $script:OriginalHomeValue = [Environment]::GetEnvironmentVariable(
            $script:HomeVariableName,
            'Process')
    }

    AfterEach {
        [Environment]::SetEnvironmentVariable(
            $script:HomeVariableName,
            $script:OriginalHomeValue,
            'Process')
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'preserves a home/profile path containing whitespace through bootstrap and List' {
        $testHome = Join-Path $script:TestRoot 'home with spaces'
        $toolRoot = Join-Path $testHome 'dotnet-sdks'
        $toolPath = Join-Path $toolRoot 'isolated-dotnet-sdk.ps1'
        $sourceCopy = Join-Path $script:TestRoot 'isolated-dotnet-sdk-source.ps1'
        New-Item -ItemType Directory -Path $testHome -Force | Out-Null
        Copy-Item $script:ToolScript $sourceCopy -Force
        Add-Content -LiteralPath $sourceCopy -Value "`n# cross-platform-source-marker"
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $testHome, 'Process')

        $output = @(& pwsh -NoProfile -File $sourceCopy -Action List 2>&1)

        $LASTEXITCODE | Should -Be 0
        Test-Path -LiteralPath $toolPath -PathType Leaf | Should -BeTrue
        Select-String -LiteralPath $toolPath -Pattern '# cross-platform-source-marker' -SimpleMatch -Quiet |
            Should -BeTrue
        ($output -join [Environment]::NewLine) |
            Should -Match ([regex]::Escape("Isolated SDKs under ${toolRoot}:"))
        ($output -join [Environment]::NewLine) | Should -Match 'None'
    }
}
