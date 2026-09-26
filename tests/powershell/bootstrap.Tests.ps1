Describe 'PowerShell bootstrap filesystem behavior' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:ToolScript = Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1'
        $script:HomeVariableName = if ($IsWindows) { 'USERPROFILE' } else { 'HOME' }
    }

    BeforeEach {
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-bootstrap-tests-{0}" -f [guid]::NewGuid())
        $script:TestHome = Join-Path $script:TestRoot 'home'
        $script:ToolRoot = Join-Path $script:TestHome 'dotnet-sdks'
        $script:ToolPath = Join-Path $script:ToolRoot 'isolated-dotnet-sdk.ps1'
        $script:SourceCopy = Join-Path $script:TestRoot 'isolated-dotnet-sdk-source.ps1'
        $script:OriginalHomeValue = [Environment]::GetEnvironmentVariable($script:HomeVariableName, 'Process')

        New-Item -ItemType Directory -Path $script:TestHome -Force | Out-Null
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:TestHome, 'Process')

        Copy-Item $script:ToolScript $script:SourceCopy -Force
        Add-Content -Path $script:SourceCopy -Value "`n# bootstrap-source-marker"
    }

    AfterEach {
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:OriginalHomeValue, 'Process')
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'fails a tool-path directory conflict without mutating the conflicting destination' {
        New-Item -ItemType Directory -Path $script:ToolPath -Force | Out-Null

        $output = @(& pwsh -NoProfile -File $script:SourceCopy -Action List 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        ($output -join [Environment]::NewLine) | Should -Not -Match 'Tool installed\.'
        Test-Path -LiteralPath $script:ToolPath -PathType Container | Should -BeTrue
        @(Get-ChildItem -LiteralPath $script:ToolPath -Force) | Should -HaveCount 0
    }
}
