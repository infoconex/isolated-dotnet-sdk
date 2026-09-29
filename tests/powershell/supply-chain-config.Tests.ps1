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
        $script:BashValidationSetup = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'scripts/initialize-bash-validation.sh') -Raw
        $script:PowerShellValidationSetup = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'scripts/Initialize-PowerShellValidation.ps1') -Raw
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

    It 'uses explicit versioned runner labels for the supported CI matrix' {
        $script:WorkflowContent | Should -Not -Match '(?m)\b(?:ubuntu|macos|windows)-latest\b'
        $script:Workflow | Should -Match '(?m)^\s*- ubuntu-24\.04\s*$'
        $script:Workflow | Should -Match '(?m)^\s*- macos-26\s*$'
        $script:Workflow | Should -Match '(?m)^\s*runs-on:\s+windows-2025\s*$'
        $script:MonitorWorkflow | Should -Match '(?m)^\s*runs-on:\s+ubuntu-24\.04\s*$'
    }

    It 'does not persist checkout credentials in read-only workflow checkouts' {
        foreach ($workflowContent in @($script:Workflow, $script:MonitorWorkflow)) {
            $workflowContent | Should -Match 'actions/checkout@[0-9a-f]{40}'
            $workflowContent | Should -Match '(?m)^\s*persist-credentials:\s+false\s*$'
        }
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
        $script:Workflow | Should -Match 'initialize-bash-validation\.sh'
        $script:BashValidationSetup | Should -Match 'git -C "\$bats_source_dir" fetch --depth=1 origin "\$bats_commit"'
        $script:BashValidationSetup | Should -Match 'checkout --detach FETCH_HEAD'
        $script:BashValidationSetup | Should -Match 'rev-parse HEAD'
    }

    It 'verifies the pinned ShellCheck SHA-256 before extraction' {
        [string]$script:AnalysisConfig.shellCheckLinuxX64Sha256 | Should -Match '^[0-9a-f]{64}$'
        $script:Workflow | Should -Match 'initialize-bash-validation\.sh'

        $verifyIndex = $script:BashValidationSetup.IndexOf('sha256sum -c -', [System.StringComparison]::Ordinal)
        $extractIndex = $script:BashValidationSetup.IndexOf('tar -xJf "$shellcheck_archive"', [System.StringComparison]::Ordinal)
        $verifyIndex | Should -BeGreaterThan -1
        $extractIndex | Should -BeGreaterThan $verifyIndex
    }

    It 'keeps PowerShell framework installation exact-version constrained' {
        [string]$script:TestConfig.pesterVersion | Should -Not -BeNullOrEmpty
        [string]$script:AnalysisConfig.psScriptAnalyzerVersion | Should -Not -BeNullOrEmpty
        $script:Workflow | Should -Match 'Initialize-PowerShellValidation\.ps1'
        $script:PowerShellValidationSetup | Should -Match 'Save-Module -Name Pester -RequiredVersion \$pesterVersion'
        $script:PowerShellValidationSetup | Should -Match 'Save-Module -Name PSScriptAnalyzer -RequiredVersion \$analyzerVersion'
        $script:PowerShellValidationSetup | Should -Match 'Test-ModuleManifest'
    }
}
