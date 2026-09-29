Describe 'PowerShell SDK version ordering' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:ToolScript = Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1'
        $script:HomeVariableName = if ($IsWindows) { 'USERPROFILE' } else { 'HOME' }
    }

    BeforeEach {
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-ordering-tests-{0}" -f [guid]::NewGuid())
        $script:TestHome = Join-Path $script:TestRoot 'home'
        $script:ToolRoot = Join-Path $script:TestHome 'dotnet-sdks'
        $script:ToolPath = Join-Path $script:ToolRoot 'isolated-dotnet-sdk.ps1'
        $script:OriginalHomeValue = [Environment]::GetEnvironmentVariable($script:HomeVariableName, 'Process')

        New-Item -ItemType Directory -Path $script:ToolRoot -Force | Out-Null
        Copy-Item -LiteralPath $script:ToolScript -Destination $script:ToolPath -Force
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:TestHome, 'Process')
        $env:ISOLATED_DOTNET_SDK_TOOL_PATH = $script:ToolPath
    }

    AfterEach {
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:OriginalHomeValue, 'Process')
        Remove-Item Env:ISOLATED_DOTNET_SDK_TOOL_PATH -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'preserves the shared newest-first ordering vector in the expanded SDK picker' {
        $metadataOutput = @(& pwsh -NoProfile -Command '
            $global:metadataResponses = [System.Collections.Generic.Queue[string]]::new()
            $global:metadataResponses.Enqueue("1")
            $global:metadataResponses.Enqueue("s")
            $global:metadataResponses.Enqueue("q")
            function Read-Host { param([string]$Prompt) $global:metadataResponses.Dequeue() }
            function Invoke-RestMethod {
                param([string]$Uri)
                if ($Uri -like "*releases-index.json") {
                    return [pscustomobject]@{
                        "releases-index" = @(
                            [pscustomobject]@{
                                "channel-version" = "8.0"
                                "latest-sdk" = "8.0.300"
                                "support-phase" = "active"
                                "release-type" = "lts"
                                "releases.json" = "https://example.invalid/releases.json"
                            }
                        )
                    }
                }
                return [pscustomobject]@{
                    releases = @(
                        [pscustomobject]@{
                            sdks = @(
                                [pscustomobject]@{ version = "8.0.100-preview.7.23376.3" },
                                [pscustomobject]@{ version = "8.0.300" },
                                [pscustomobject]@{ version = "8.0.100-rc.1.23455.8" },
                                [pscustomobject]@{ version = "8.0.101" },
                                [pscustomobject]@{ version = "8.0.100" },
                                [pscustomobject]@{ version = "8.0.200" },
                                [pscustomobject]@{ version = "8.0.100-rc.2.23479.6" },
                                [pscustomobject]@{ version = "8.0.100-preview.6.23330.14" },
                                [pscustomobject]@{ version = "8.0.201" },
                                [pscustomobject]@{ version = "8.0.300-servicing.1.2.3" },
                                [pscustomobject]@{ version = "8.0.100-preview.7.23376.4" },
                                [pscustomobject]@{ version = "8.0.100-rc.2.23479.7" }
                            )
                        }
                    )
                }
            }
            & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install
        ' 6>&1 2>&1)

        $LASTEXITCODE | Should -Be 0
        $expected = @(
            '8.0.300',
            '8.0.300-servicing.1.2.3',
            '8.0.201',
            '8.0.200',
            '8.0.101',
            '8.0.100',
            '8.0.100-rc.2.23479.7',
            '8.0.100-rc.2.23479.6',
            '8.0.100-rc.1.23455.8',
            '8.0.100-preview.7.23376.4',
            '8.0.100-preview.7.23376.3',
            '8.0.100-preview.6.23330.14'
        )
        $actual = @(
            $metadataOutput |
                ForEach-Object { [string]$_ } |
                Where-Object { $_ -match '^\s+\d+\. 8\.0\.' } |
                ForEach-Object { $_ -replace '^\s+\d+\. ', '' -replace ' \([^)]*\)$', '' } |
                Select-Object -Last 12
        )

        $actual | Should -Be $expected
    }
}
