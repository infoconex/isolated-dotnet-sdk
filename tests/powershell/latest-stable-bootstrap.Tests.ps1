Describe 'PowerShell latest stable bootstrap' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:BootstrapScript = Join-Path $script:RepositoryRoot 'install.ps1'
        $script:ExpectedHash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    }

    BeforeEach {
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-latest-bootstrap-{0}" -f [guid]::NewGuid())
        $script:ExecutionLog = Join-Path $script:TestRoot 'executions.log'
        $script:Scenario = 'success'
        $script:LatestTag = 'v1.0.0'
        $script:ActualHash = $script:ExpectedHash
        $script:ToolExitCode = 0
        $script:RequestedUris = @()
        $script:OriginalExecutionLog = $env:BOOTSTRAP_EXECUTION_LOG
        $script:OriginalToolExit = $env:BOOTSTRAP_TOOL_EXIT

        New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null
        $env:BOOTSTRAP_EXECUTION_LOG = $script:ExecutionLog
        $env:BOOTSTRAP_TOOL_EXIT = [string]$script:ToolExitCode

        Mock Invoke-RestMethod {
            if ($script:Scenario -eq 'discovery-failure') {
                throw 'simulated release discovery failure'
            }

            if ($script:Scenario -eq 'malformed-release') {
                return [pscustomobject]@{
                    draft = $false
                    prerelease = $false
                }
            }

            if ($script:Scenario -eq 'prerelease') {
                return [pscustomobject]@{
                    tag_name = 'v9.9.9'
                    draft = $false
                    prerelease = $true
                }
            }

            return [pscustomobject]@{
                tag_name = $script:LatestTag
                draft = $false
                prerelease = $false
            }
        }

        Mock Invoke-WebRequest {
            $script:RequestedUris += [string]$Uri

            if ([string]$Uri -like '*/isolated-dotnet-sdk.ps1') {
                @'
Add-Content -LiteralPath $env:BOOTSTRAP_EXECUTION_LOG -Value 'executed'
exit ([int]$env:BOOTSTRAP_TOOL_EXIT)
'@ | Set-Content -LiteralPath $OutFile -NoNewline
                return
            }

            if ([string]$Uri -like '*/SHA256SUMS') {
                switch ($script:Scenario) {
                    'missing-checksum' { throw 'simulated checksum download failure' }
                    'malformed-checksum' {
                        'not-a-checksum  isolated-dotnet-sdk.ps1' | Set-Content -LiteralPath $OutFile
                    }
                    'duplicate-checksum' {
                        @(
                            "$($script:ExpectedHash)  isolated-dotnet-sdk.ps1",
                            "$($script:ExpectedHash)  isolated-dotnet-sdk.ps1"
                        ) | Set-Content -LiteralPath $OutFile
                    }
                    default {
                        "$($script:ExpectedHash)  isolated-dotnet-sdk.ps1" | Set-Content -LiteralPath $OutFile
                    }
                }
                return
            }

            throw "Unexpected URI: $Uri"
        }

        Mock Get-FileHash {
            [pscustomobject]@{ Hash = $script:ActualHash }
        }
    }

    AfterEach {
        if ($null -eq $script:OriginalExecutionLog) {
            Remove-Item Env:BOOTSTRAP_EXECUTION_LOG -ErrorAction SilentlyContinue
        }
        else {
            $env:BOOTSTRAP_EXECUTION_LOG = $script:OriginalExecutionLog
        }

        if ($null -eq $script:OriginalToolExit) {
            Remove-Item Env:BOOTSTRAP_TOOL_EXIT -ErrorAction SilentlyContinue
        }
        else {
            $env:BOOTSTRAP_TOOL_EXIT = $script:OriginalToolExit
        }

        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'verifies and executes the resolved tagged PowerShell tool' {
        & $script:BootstrapScript

        Test-Path -LiteralPath $script:ExecutionLog | Should -BeTrue
        (Get-Content -LiteralPath $script:ExecutionLog).Count | Should -Be 1
        ($script:RequestedUris -join "`n") | Should -Match '/v1\.0\.0/isolated-dotnet-sdk\.ps1'
        ($script:RequestedUris -join "`n") | Should -Not -Match '/main/isolated-dotnet-sdk\.ps1'
    }

    It 'follows future latest-stable movement without a bootstrap change' {
        & $script:BootstrapScript

        $script:LatestTag = 'v2.0.0'
        & $script:BootstrapScript

        ($script:RequestedUris -join "`n") | Should -Match '/v1\.0\.0/isolated-dotnet-sdk\.ps1'
        ($script:RequestedUris -join "`n") | Should -Match '/v2\.0\.0/isolated-dotnet-sdk\.ps1'
    }

    It 'fails closed when release discovery fails' {
        $script:Scenario = 'discovery-failure'

        { & $script:BootstrapScript } | Should -Throw
        Test-Path -LiteralPath $script:ExecutionLog | Should -BeFalse
    }

    It 'fails closed for malformed or prerelease metadata' {
        $script:Scenario = 'malformed-release'
        { & $script:BootstrapScript } | Should -Throw
        Test-Path -LiteralPath $script:ExecutionLog | Should -BeFalse

        $script:Scenario = 'prerelease'
        { & $script:BootstrapScript } | Should -Throw
        Test-Path -LiteralPath $script:ExecutionLog | Should -BeFalse
    }

    It 'never executes the released tool for missing malformed or duplicate checksum data' {
        foreach ($scenario in @('missing-checksum', 'malformed-checksum', 'duplicate-checksum')) {
            Remove-Item -LiteralPath $script:ExecutionLog -Force -ErrorAction SilentlyContinue
            $script:Scenario = $scenario

            { & $script:BootstrapScript } | Should -Throw
            Test-Path -LiteralPath $script:ExecutionLog | Should -BeFalse
        }
    }

    It 'never executes the released tool after a checksum mismatch' {
        $script:ActualHash = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'

        { & $script:BootstrapScript } | Should -Throw
        Test-Path -LiteralPath $script:ExecutionLog | Should -BeFalse
    }

    It 'does not report success when the released tool fails' {
        $script:ToolExitCode = 7
        $env:BOOTSTRAP_TOOL_EXIT = [string]$script:ToolExitCode

        { & $script:BootstrapScript } | Should -Throw '*exit code 7*'
        Test-Path -LiteralPath $script:ExecutionLog | Should -BeTrue
    }
}
