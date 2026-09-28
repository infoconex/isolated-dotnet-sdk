Describe 'PowerShell comment-based help' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:ToolScript = Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1'
        $script:HelpText = Get-Help $script:ToolScript -Full | Out-String
    }

    It 'describes the supported PowerShell operational contract' {
        $script:HelpText | Should -Match 'Windows with PowerShell 7'
        $script:HelpText | Should -Match 'not added to PATH'
        $script:HelpText | Should -Match 'Explicit List with Version is invalid'
        $script:HelpText | Should -Match 'WhatIf and Confirm are supported only for Remove'
        $script:HelpText | Should -Match 'does not choose a missing action or version'
        $script:HelpText | Should -Match 'Required interactive input that is unavailable is an operational failure'
        $script:HelpText | Should -Match 'Explicit cancellation is a successful no-change result'
        $script:HelpText | Should -Match 'Operational failures return a nonzero exit status'
        $script:HelpText | Should -Match 'Exact-version installs bypass release-metadata discovery'
    }
}
