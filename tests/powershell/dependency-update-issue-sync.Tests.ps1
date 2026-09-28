Describe 'Pinned dependency update issue synchronization' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        . (Join-Path $script:RepositoryRoot 'scripts/Sync-DependencyUpdateIssue.ps1')
    }

    It 'creates the tracking issue when updates exist and no tracking issue exists' {
        Get-DependencyMonitorIssueDecision -UpdateCount 2 -ExistingIssue $null |
            Should -Be 'Create'
    }

    It 'updates the existing open tracking issue instead of creating a duplicate' {
        $issue = [pscustomobject]@{ state = 'open' }

        Get-DependencyMonitorIssueDecision -UpdateCount 1 -ExistingIssue $issue |
            Should -Be 'Update'
    }

    It 'reopens the existing closed tracking issue when updates reappear' {
        $issue = [pscustomobject]@{ state = 'closed' }

        Get-DependencyMonitorIssueDecision -UpdateCount 1 -ExistingIssue $issue |
            Should -Be 'Reopen'
    }

    It 'closes the existing open tracking issue when every monitored pin is current' {
        $issue = [pscustomobject]@{ state = 'open' }

        Get-DependencyMonitorIssueDecision -UpdateCount 0 -ExistingIssue $issue |
            Should -Be 'Close'
    }

    It 'does nothing when every monitored pin is current and no open tracking issue needs reconciliation' {
        Get-DependencyMonitorIssueDecision -UpdateCount 0 -ExistingIssue $null |
            Should -Be 'None'

        $closedIssue = [pscustomobject]@{ state = 'closed' }
        Get-DependencyMonitorIssueDecision -UpdateCount 0 -ExistingIssue $closedIssue |
            Should -Be 'None'
    }

    It 'selects only the exact tracking issue and ignores pull requests and unrelated issues' {
        $issues = @(
            [pscustomobject]@{ number = 10; title = 'Other issue'; state = 'open' },
            [pscustomobject]@{ number = 11; title = $script:DependencyMonitorIssueTitle; state = 'open'; pull_request = [pscustomobject]@{} },
            [pscustomobject]@{ number = 12; title = $script:DependencyMonitorIssueTitle; state = 'closed' }
        )

        $selected = Select-DependencyMonitorIssue -Issue $issues

        $selected.number | Should -Be 12
    }

    It 'fails visibly if duplicate tracking issues already exist' {
        $issues = @(
            [pscustomobject]@{ number = 12; title = $script:DependencyMonitorIssueTitle; state = 'open' },
            [pscustomobject]@{ number = 13; title = $script:DependencyMonitorIssueTitle; state = 'closed' }
        )

        {
            Select-DependencyMonitorIssue -Issue $issues
        } | Should -Throw '*multiple dependency monitor tracking issues*'
    }
}
