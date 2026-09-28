Describe 'Pinned dependency update discovery' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        . (Join-Path $script:RepositoryRoot 'scripts/Invoke-DependencyUpdateCheck.ps1')

        function Get-TestCurrentPin {
            return [pscustomobject]@{
                PSScriptAnalyzerVersion = '1.25.0'
                PesterVersion = '6.2.0'
                ShellCheckVersion = '0.11.0'
                BatsVersion = '1.14.0'
                BatsCommit = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
                DotNetInstallCommit = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
            }
        }

        function Get-TestCandidateSnapshot {
            param(
                [string]$PSScriptAnalyzerVersion = '1.25.0',
                [string]$PesterVersion = '6.2.0',
                [string]$ShellCheckVersion = 'v0.11.0',
                [string]$BatsVersion = 'v1.14.0',
                [string]$BatsCommit = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                [string]$DotNetVersion = 'v2026.07.21',
                [string]$DotNetCommit = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
            )

            return [pscustomobject]@{
                PSScriptAnalyzer = [pscustomobject]@{
                    Version = $PSScriptAnalyzerVersion
                    SourceUrl = "https://example.invalid/PSScriptAnalyzer/$PSScriptAnalyzerVersion"
                }
                Pester = [pscustomobject]@{
                    Version = $PesterVersion
                    SourceUrl = "https://example.invalid/Pester/$PesterVersion"
                }
                ShellCheck = [pscustomobject]@{
                    Version = $ShellCheckVersion
                    SourceUrl = "https://example.invalid/ShellCheck/$ShellCheckVersion"
                }
                Bats = [pscustomobject]@{
                    Version = $BatsVersion
                    Commit = $BatsCommit
                    SourceUrl = "https://example.invalid/Bats/$BatsVersion"
                }
                DotNetInstall = [pscustomobject]@{
                    Version = $DotNetVersion
                    Commit = $DotNetCommit
                    SourceUrl = "https://example.invalid/dotnet-install/$DotNetVersion"
                }
            }
        }
    }

    It 'reports no update when every stable candidate matches the repository pins' {
        $updates = @(
            Get-DependencyUpdateRecord `
                -Current (Get-TestCurrentPin) `
                -Candidate (Get-TestCandidateSnapshot)
        )

        $updates.Count | Should -Be 0
        ConvertTo-DependencyUpdateReport -Update $updates |
            Should -Match 'All unsupported repository-owned dependency pins match'
    }

    It 'reports every newer candidate with authoritative context and coupled metadata guidance' {
        $candidate = Get-TestCandidateSnapshot `
            -PSScriptAnalyzerVersion '1.26.0' `
            -PesterVersion '6.3.0' `
            -ShellCheckVersion 'v0.12.0' `
            -BatsVersion 'v1.15.0' `
            -BatsCommit 'cccccccccccccccccccccccccccccccccccccccc' `
            -DotNetVersion 'v2026.10.01' `
            -DotNetCommit 'dddddddddddddddddddddddddddddddddddddddd'

        $updates = @(Get-DependencyUpdateRecord -Current (Get-TestCurrentPin) -Candidate $candidate)
        $report = ConvertTo-DependencyUpdateReport -Update $updates

        $updates.Count | Should -Be 5
        $report | Should -Match 'PSScriptAnalyzer'
        $report | Should -Match 'Pester'
        $report | Should -Match 'ShellCheck'
        $report | Should -Match 'Linux x64 release archive SHA-256'
        $report | Should -Match 'Bats-core'
        $report | Should -Match 'cccccccccccccccccccccccccccccccccccccccc'
        $report | Should -Match 'Microsoft dotnet/install-scripts'
        $report | Should -Match 'blob IDs'
        $report | Should -Match 'https://example\.invalid/'
    }

    It 'fails visibly when a same-version Bats release resolves to a different commit' {
        $candidate = Get-TestCandidateSnapshot `
            -BatsCommit 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'

        {
            Get-DependencyUpdateRecord -Current (Get-TestCurrentPin) -Candidate $candidate
        } | Should -Throw '*now resolves to*instead of pinned commit*'
    }

    It 'rejects malformed versions rather than treating them as current' {
        {
            Test-DependencyVersionUpdate -CurrentVersion '1.25.0' -CandidateVersion 'latest'
        } | Should -Throw '*not a supported stable version*'
    }

    It 'writes deterministic UTF-8 result artifacts without changing repository configuration' {
        $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("dependency-update-tests-{0}" -f [guid]::NewGuid())
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

        try {
            $jsonPath = Join-Path $testRoot 'result.json'
            $reportPath = Join-Path $testRoot 'report.md'
            $configPaths = @(
                (Join-Path $script:RepositoryRoot '.config/static-analysis.json'),
                (Join-Path $script:RepositoryRoot '.config/test-frameworks.json'),
                (Join-Path $script:RepositoryRoot '.config/remote-artifacts.json')
            )
            $beforeHashes = @($configPaths | ForEach-Object { (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash })

            $update = @(
                ConvertTo-DependencyUpdateRecord `
                    -Dependency 'ShellCheck' `
                    -Current '0.11.0' `
                    -Candidate '0.12.0' `
                    -SourceUrl 'https://example.invalid/ShellCheck/v0.12.0' `
                    -ReviewTogether 'Update version and checksum together.'
            )

            Write-DependencyUpdateResult -Update $update -JsonPath $jsonPath -MarkdownPath $reportPath | Out-Null
            $firstJson = [System.IO.File]::ReadAllBytes($jsonPath)
            $firstReport = [System.IO.File]::ReadAllBytes($reportPath)

            Write-DependencyUpdateResult -Update $update -JsonPath $jsonPath -MarkdownPath $reportPath | Out-Null
            $secondJson = [System.IO.File]::ReadAllBytes($jsonPath)
            $secondReport = [System.IO.File]::ReadAllBytes($reportPath)
            $afterHashes = @($configPaths | ForEach-Object { (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash })

            [Convert]::ToBase64String($secondJson) | Should -Be ([Convert]::ToBase64String($firstJson))
            [Convert]::ToBase64String($secondReport) | Should -Be ([Convert]::ToBase64String($firstReport))
            $secondJson[0..2] | Should -Not -Be @(0xEF, 0xBB, 0xBF)
            $secondReport[0..2] | Should -Not -Be @(0xEF, 0xBB, 0xBF)
            $afterHashes | Should -Be $beforeHashes
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
