Describe 'Repository supply-chain configuration' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:WorkflowRoot = Join-Path $script:RepositoryRoot '.github/workflows'
        $script:WorkflowPath = Join-Path $script:WorkflowRoot 'validate.yml'
        $script:Workflow = Get-Content -LiteralPath $script:WorkflowPath -Raw
        $script:MonitorWorkflowPath = Join-Path $script:WorkflowRoot 'dependency-update-monitor.yml'
        $script:MonitorWorkflow = Get-Content -LiteralPath $script:MonitorWorkflowPath -Raw
        $script:WorkflowContent = @(
            Get-ChildItem -LiteralPath $script:WorkflowRoot -File |
                Where-Object { $_.Extension -in @('.yml', '.yaml') } |
                Sort-Object -Property Name |
                ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }
        ) -join [Environment]::NewLine
        $script:TestConfig = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.config/test-frameworks.json') -Raw | ConvertFrom-Json
        $script:AnalysisConfig = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.config/static-analysis.json') -Raw | ConvertFrom-Json
    }

    It 'keeps every external action reference pinned to a full commit SHA' {
        $allActionRefs = [regex]::Matches($script:WorkflowContent, 'uses:\s+[^@\s]+@[^\s#]+')
        $pinnedActionRefs = [regex]::Matches($script:WorkflowContent, 'uses:\s+[^@\s]+@[0-9a-f]{40}(?=\s|#)')

        $allActionRefs.Count | Should -BeGreaterThan 0
        $pinnedActionRefs.Count | Should -Be $allActionRefs.Count
    }

    It 'keeps readable release context on the monitor workflow action pin' {
        $script:MonitorWorkflow |
            Should -Match 'actions/checkout@[0-9a-f]{40}\s+#\s+v[0-9]+\.[0-9]+\.[0-9]+'
    }

    It 'keeps scheduled dependency monitoring least privilege and manually runnable' {
        $script:MonitorWorkflow | Should -Match '(?m)^\s*workflow_dispatch:\s*$'
        $script:MonitorWorkflow | Should -Match '(?m)^\s*schedule:\s*$'
        $script:MonitorWorkflow | Should -Match '(?m)^\s*contents:\s+read\s*$'
        $script:MonitorWorkflow | Should -Match '(?m)^\s*issues:\s+write\s*$'
        $script:MonitorWorkflow | Should -Not -Match '(?m)^\s*pull-requests:\s+write\s*$'
        $script:MonitorWorkflow | Should -Match 'Invoke-DependencyUpdateCheck\.ps1'
        $script:MonitorWorkflow | Should -Match 'Sync-DependencyUpdateIssue\.ps1'
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
