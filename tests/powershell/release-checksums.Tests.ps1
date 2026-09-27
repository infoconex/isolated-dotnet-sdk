Describe 'Release checksum generation' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:Generator = Join-Path $script:RepositoryRoot 'scripts/New-ReleaseChecksums.ps1'
    }

    BeforeEach {
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-checksum-tests-{0}" -f [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null
        Copy-Item (Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1') $script:TestRoot
        Copy-Item (Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.sh') $script:TestRoot
        $script:OutputPath = Join-Path $script:TestRoot 'SHA256SUMS'
    }

    AfterEach {
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'writes exactly one lowercase SHA-256 entry for each stable script in fixed order' {
        & $script:Generator -RepositoryRoot $script:TestRoot -OutputPath $script:OutputPath | Out-Null

        $lines = @(Get-Content -LiteralPath $script:OutputPath)
        $lines.Count | Should -Be 2
        $lines[0] | Should -Match '^[0-9a-f]{64}  isolated-dotnet-sdk\.ps1$'
        $lines[1] | Should -Match '^[0-9a-f]{64}  isolated-dotnet-sdk\.sh$'

        $psExpected = (Get-FileHash -LiteralPath (Join-Path $script:TestRoot 'isolated-dotnet-sdk.ps1') -Algorithm SHA256).Hash.ToLowerInvariant()
        $shExpected = (Get-FileHash -LiteralPath (Join-Path $script:TestRoot 'isolated-dotnet-sdk.sh') -Algorithm SHA256).Hash.ToLowerInvariant()
        $lines[0] | Should -Be "$psExpected  isolated-dotnet-sdk.ps1"
        $lines[1] | Should -Be "$shExpected  isolated-dotnet-sdk.sh"
    }

    It 'is byte-for-byte deterministic across repeated generation' {
        & $script:Generator -RepositoryRoot $script:TestRoot -OutputPath $script:OutputPath | Out-Null
        $first = [System.IO.File]::ReadAllBytes($script:OutputPath)

        & $script:Generator -RepositoryRoot $script:TestRoot -OutputPath $script:OutputPath | Out-Null
        $second = [System.IO.File]::ReadAllBytes($script:OutputPath)

        [Convert]::ToBase64String($second) | Should -Be ([Convert]::ToBase64String($first))
        $second[0..2] | Should -Not -Be @(0xEF, 0xBB, 0xBF)
    }
}
