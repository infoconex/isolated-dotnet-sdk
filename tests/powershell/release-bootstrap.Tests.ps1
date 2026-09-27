Describe 'PowerShell stable release bootstrap semantics' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:ToolScript = Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1'
        $script:HomeVariableName = if ($IsWindows) { 'USERPROFILE' } else { 'HOME' }
    }

    BeforeEach {
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-release-tests-{0}" -f [guid]::NewGuid())
        $script:TestHome = Join-Path $script:TestRoot 'home'
        $script:ToolRoot = Join-Path $script:TestHome 'dotnet-sdks'
        $script:ToolPath = Join-Path $script:ToolRoot 'isolated-dotnet-sdk.ps1'
        $script:ReleaseA = Join-Path $script:TestRoot 'release-a.ps1'
        $script:ReleaseB = Join-Path $script:TestRoot 'release-b.ps1'
        $script:OriginalHomeValue = [Environment]::GetEnvironmentVariable($script:HomeVariableName, 'Process')

        New-Item -ItemType Directory -Path $script:TestHome -Force | Out-Null
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:TestHome, 'Process')

        Copy-Item $script:ToolScript $script:ReleaseA -Force
        Copy-Item $script:ToolScript $script:ReleaseB -Force
        Add-Content -Path $script:ReleaseA -Value "`n# release-source-marker: v1.0.0"
        Add-Content -Path $script:ReleaseB -Value "`n# release-source-marker: v2.0.0"
    }

    AfterEach {
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:OriginalHomeValue, 'Process')
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'file-based stable bootstrap installs the exact selected release source' {
        & pwsh -NoProfile -File $script:ReleaseA -Action List *> $null

        $LASTEXITCODE | Should -Be 0
        Select-String -Path $script:ToolPath -Pattern '# release-source-marker: v1.0.0' -SimpleMatch -Quiet |
            Should -BeTrue
        Select-String -Path $script:ToolPath -Pattern '# release-source-marker: v2.0.0' -SimpleMatch -Quiet |
            Should -BeFalse
    }

    It 'explicit stable update replaces the saved tool with the newly selected release' {
        & pwsh -NoProfile -File $script:ReleaseA -Action List *> $null
        $LASTEXITCODE | Should -Be 0

        & pwsh -NoProfile -File $script:ReleaseB -Action List *> $null

        $LASTEXITCODE | Should -Be 0
        Select-String -Path $script:ToolPath -Pattern '# release-source-marker: v2.0.0' -SimpleMatch -Quiet |
            Should -BeTrue
        Select-String -Path $script:ToolPath -Pattern '# release-source-marker: v1.0.0' -SimpleMatch -Quiet |
            Should -BeFalse
    }

    It 'explicit rollback replaces the saved tool with the older selected release' {
        & pwsh -NoProfile -File $script:ReleaseA -Action List *> $null
        & pwsh -NoProfile -File $script:ReleaseB -Action List *> $null

        & pwsh -NoProfile -File $script:ReleaseA -Action List *> $null

        $LASTEXITCODE | Should -Be 0
        Select-String -Path $script:ToolPath -Pattern '# release-source-marker: v1.0.0' -SimpleMatch -Quiet |
            Should -BeTrue
        Select-String -Path $script:ToolPath -Pattern '# release-source-marker: v2.0.0' -SimpleMatch -Quiet |
            Should -BeFalse
    }

    It 'normal saved-tool execution does not implicitly replace or update itself' {
        & pwsh -NoProfile -File $script:ReleaseA -Action List *> $null
        $LASTEXITCODE | Should -Be 0
        $before = (Get-FileHash -LiteralPath $script:ToolPath -Algorithm SHA256).Hash

        & pwsh -NoProfile -File $script:ToolPath -Action List *> $null

        $LASTEXITCODE | Should -Be 0
        (Get-FileHash -LiteralPath $script:ToolPath -Algorithm SHA256).Hash | Should -Be $before
        Select-String -Path $script:ToolPath -Pattern '# release-source-marker: v1.0.0' -SimpleMatch -Quiet |
            Should -BeTrue
    }
}
