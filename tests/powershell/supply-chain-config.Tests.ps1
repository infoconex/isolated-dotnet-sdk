Describe 'Repository supply-chain configuration' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:WorkflowPath = Join-Path $script:RepositoryRoot '.github/workflows/validate.yml'
        $script:Workflow = Get-Content -LiteralPath $script:WorkflowPath -Raw
        $script:TestConfig = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.config/test-frameworks.json') -Raw | ConvertFrom-Json
        $script:AnalysisConfig = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.config/static-analysis.json') -Raw | ConvertFrom-Json
    }

    It 'keeps every checkout reference pinned to a full commit SHA' {
        $allCheckoutRefs = [regex]::Matches($script:Workflow, 'actions/checkout@[^\s#]+')
        $pinnedCheckoutRefs = [regex]::Matches($script:Workflow, 'actions/checkout@[0-9a-f]{40}(?=\s|#)')

        $allCheckoutRefs.Count | Should -BeGreaterThan 0
        $pinnedCheckoutRefs.Count | Should -Be $allCheckoutRefs.Count
    }

    It 'keeps Bats pinned to an exact Git commit' {
        [string]$script:TestConfig.batsCommit | Should -Match '^[0-9a-f]{40}$'
        $script:Workflow | Should -Match 'git -C "\$source_dir" fetch --depth=1 origin "\$commit"'
        $script:Workflow | Should -Match 'checkout --detach FETCH_HEAD'
    }

    It 'verifies the pinned ShellCheck SHA-256 before extraction' {
        [string]$script:AnalysisConfig.shellCheckLinuxX64Sha256 | Should -Match '^[0-9a-f]{64}$'

        $verifyIndex = $script:Workflow.IndexOf('sha256sum -c -', [System.StringComparison]::Ordinal)
        $extractIndex = $script:Workflow.IndexOf('tar -xJf "$archive"', [System.StringComparison]::Ordinal)
        $verifyIndex | Should -BeGreaterThan -1
        $extractIndex | Should -BeGreaterThan $verifyIndex
    }

    It 'keeps PowerShell framework installation exact-version constrained' {
        [string]$script:TestConfig.pesterVersion | Should -Not -BeNullOrEmpty
        [string]$script:AnalysisConfig.psScriptAnalyzerVersion | Should -Not -BeNullOrEmpty
        $script:Workflow | Should -Match '-RequiredVersion \$pesterVersion'
        $script:Workflow | Should -Match '-RequiredVersion \$analyzerVersion'
    }
}
