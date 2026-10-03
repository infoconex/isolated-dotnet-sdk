Describe 'PowerShell latest stable bootstrap' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:BootstrapScript = Join-Path $script:RepositoryRoot 'install.ps1'
        $script:ExpectedHash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    }

    BeforeEach {
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-latest-bootstrap-{0}" -f [guid]::NewGuid())
        $script:ExecutionLog = Join-Path $script:TestRoot 'executions.log'
        $script:RequestLog = Join-Path $script:TestRoot 'requests.log'

        $script:OriginalExecutionLog = $env:BOOTSTRAP_EXECUTION_LOG
        $script:OriginalToolExit = $env:BOOTSTRAP_TOOL_EXIT
        $script:OriginalRequestLog = $env:BOOTSTRAP_REQUEST_LOG
        $script:OriginalScenario = $env:BOOTSTRAP_TEST_SCENARIO
        $script:OriginalLatestTag = $env:BOOTSTRAP_TEST_LATEST_TAG
        $script:OriginalActualHash = $env:BOOTSTRAP_TEST_ACTUAL_HASH

        New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null
        $env:BOOTSTRAP_EXECUTION_LOG = $script:ExecutionLog
        $env:BOOTSTRAP_TOOL_EXIT = '0'
        $env:BOOTSTRAP_REQUEST_LOG = $script:RequestLog
        $env:BOOTSTRAP_TEST_SCENARIO = 'success'
        $env:BOOTSTRAP_TEST_LATEST_TAG = 'v1.0.0'
        $env:BOOTSTRAP_TEST_ACTUAL_HASH = $script:ExpectedHash

        Mock Invoke-RestMethod {
            switch ($env:BOOTSTRAP_TEST_SCENARIO) {
                'discovery-failure' {
                    throw 'simulated release discovery failure'
                }
                'malformed-release' {
                    return [pscustomobject]@{
                        draft = $false
                        prerelease = $false
                    }
                }
                'prerelease' {
                    return [pscustomobject]@{
                        tag_name = 'v9.9.9'
                        draft = $false
                        prerelease = $true
                    }
                }
                default {
                    return [pscustomobject]@{
                        tag_name = $env:BOOTSTRAP_TEST_LATEST_TAG
                        draft = $false
                        prerelease = $false
                    }
                }
            }
        }

        Mock Invoke-WebRequest {
            Add-Content -LiteralPath $env:BOOTSTRAP_REQUEST_LOG -Value ([string]$Uri)

            if ([string]$Uri -like '*/isolated-dotnet-sdk.ps1') {
                @'
Add-Content -LiteralPath $env:BOOTSTRAP_EXECUTION_LOG -Value 'executed'
exit ([int]$env:BOOTSTRAP_TOOL_EXIT)
'@ | Set-Content -LiteralPath $OutFile -NoNewline
                return
            }

            if ([string]$Uri -like '*/SHA256SUMS') {
                switch ($env:BOOTSTRAP_TEST_SCENARIO) {
                    'missing-checksum' {
                        throw 'simulated checksum download failure'
                    }
                    'missing-platform-entry' {
                        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  isolated-dotnet-sdk.sh' |
                            Set-Content -LiteralPath $OutFile
                    }
                    'malformed-checksum' {
                        'not-a-checksum  isolated-dotnet-sdk.ps1' | Set-Content -LiteralPath $OutFile
                    }
                    'duplicate-checksum' {
                        @(
                            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  isolated-dotnet-sdk.ps1',
                            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  isolated-dotnet-sdk.ps1'
                        ) | Set-Content -LiteralPath $OutFile
                    }
                    default {
                        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  isolated-dotnet-sdk.ps1' |
                            Set-Content -LiteralPath $OutFile
                    }
                }
                return
            }

            throw "Unexpected URI: $Uri"
        }

        Mock Get-FileHash {
            [pscustomobject]@{ Hash = $env:BOOTSTRAP_TEST_ACTUAL_HASH }
        }
    }

    AfterEach {
        $environment = @{
            BOOTSTRAP_EXECUTION_LOG = $script:OriginalExecutionLog
            BOOTSTRAP_TOOL_EXIT = $script:OriginalToolExit
            BOOTSTRAP_REQUEST_LOG = $script:OriginalRequestLog
            BOOTSTRAP_TEST_SCENARIO = $script:OriginalScenario
            BOOTSTRAP_TEST_LATEST_TAG = $script:OriginalLatestTag
            BOOTSTRAP_TEST_ACTUAL_HASH = $script:OriginalActualHash
        }

        foreach ($entry in $environment.GetEnumerator()) {
            if ($null -eq $entry.Value) {
                Remove-Item "Env:$($entry.Key)" -ErrorAction SilentlyContinue
            }
            else {
                Set-Item "Env:$($entry.Key)" -Value $entry.Value
            }
        }

        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'verifies and executes the resolved tagged PowerShell tool' {
        & $script:BootstrapScript

        Test-Path -LiteralPath $script:ExecutionLog | Should -BeTrue
        (Get-Content -LiteralPath $script:ExecutionLog).Count | Should -Be 1
        $requests = Get-Content -LiteralPath $script:RequestLog
        ($requests -join "`n") | Should -Match '/v1\.0\.0/isolated-dotnet-sdk\.ps1'
        ($requests -join "`n") | Should -Not -Match '/main/isolated-dotnet-sdk\.ps1'
    }

    It 'follows future latest-stable movement without a bootstrap change' {
        & $script:BootstrapScript

        $env:BOOTSTRAP_TEST_LATEST_TAG = 'v2.0.0'
        & $script:BootstrapScript

        $requests = Get-Content -LiteralPath $script:RequestLog
        ($requests -join "`n") | Should -Match '/v1\.0\.0/isolated-dotnet-sdk\.ps1'
        ($requests -join "`n") | Should -Match '/v2\.0\.0/isolated-dotnet-sdk\.ps1'
    }

    It 'fails closed when release discovery fails' {
        $env:BOOTSTRAP_TEST_SCENARIO = 'discovery-failure'

        { & $script:BootstrapScript } | Should -Throw
        Test-Path -LiteralPath $script:ExecutionLog | Should -BeFalse
    }

    It 'fails closed for malformed or prerelease metadata' {
        $env:BOOTSTRAP_TEST_SCENARIO = 'malformed-release'
        { & $script:BootstrapScript } | Should -Throw
        Test-Path -LiteralPath $script:ExecutionLog | Should -BeFalse

        $env:BOOTSTRAP_TEST_SCENARIO = 'prerelease'
        { & $script:BootstrapScript } | Should -Throw
        Test-Path -LiteralPath $script:ExecutionLog | Should -BeFalse
    }

    It 'never executes the released tool for missing malformed or duplicate checksum data' {
        foreach ($scenario in @(
                'missing-checksum',
                'missing-platform-entry',
                'malformed-checksum',
                'duplicate-checksum')) {
            Remove-Item -LiteralPath $script:ExecutionLog -Force -ErrorAction SilentlyContinue
            $env:BOOTSTRAP_TEST_SCENARIO = $scenario

            { & $script:BootstrapScript } | Should -Throw
            Test-Path -LiteralPath $script:ExecutionLog | Should -BeFalse
        }
    }

    It 'never executes the released tool after a checksum mismatch' {
        $env:BOOTSTRAP_TEST_ACTUAL_HASH = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'

        { & $script:BootstrapScript } | Should -Throw
        Test-Path -LiteralPath $script:ExecutionLog | Should -BeFalse
    }

    It 'does not report success when the released tool fails' {
        $env:BOOTSTRAP_TOOL_EXIT = '7'

        { & $script:BootstrapScript } | Should -Throw '*exit code 7*'
        Test-Path -LiteralPath $script:ExecutionLog | Should -BeTrue
    }
}
