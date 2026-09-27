Describe 'PowerShell release-metadata structural boundaries' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:ToolScript = Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1'
        $script:HomeVariableName = if ($IsWindows) { 'USERPROFILE' } else { 'HOME' }
    }

    BeforeEach {
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-metadata-boundaries-{0}" -f [guid]::NewGuid())
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

    It 'does not select release-index entries missing required fields' {
        $metadataOutput = @(& pwsh -NoProfile -Command '
            function Invoke-RestMethod {
                [pscustomobject]@{
                    "releases-index" = @(
                        [pscustomobject]@{
                            "support-phase" = "active"
                            "releases.json" = "https://example.invalid/missing-channel.json"
                        },
                        [pscustomobject]@{
                            "channel-version" = "98.0"
                            "releases.json" = "https://example.invalid/missing-phase.json"
                        },
                        [pscustomobject]@{
                            "channel-version" = "97.0"
                            "support-phase" = "active"
                        }
                    )
                }
            }
            & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install
        ' 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        $text = $metadataOutput -join [Environment]::NewLine
        $text | Should -Match 'No selectable .NET channels were found in Microsoft release metadata\.'
        $text | Should -Not -Match 'Select a supported or development .NET channel:'
    }

    It 'fails before the SDK picker when selected-channel metadata has no SDK versions' {
        $metadataOutput = @(& pwsh -NoProfile -Command '
            $global:metadataResponses = [System.Collections.Generic.Queue[string]]::new()
            $global:metadataResponses.Enqueue("1")
            function Read-Host { param([string]$Prompt) $global:metadataResponses.Dequeue() }
            function Invoke-RestMethod {
                param([string]$Uri)
                if ($Uri -like "*releases-index.json") {
                    return [pscustomobject]@{
                        "releases-index" = @(
                            [pscustomobject]@{
                                "channel-version" = "99.0"
                                "support-phase" = "active"
                                "releases.json" = "https://example.invalid/releases.json"
                            }
                        )
                    }
                }
                return [pscustomobject]@{ releases = @() }
            }
            & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install
        ' 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        $text = $metadataOutput -join [Environment]::NewLine
        $text | Should -Match 'No SDK versions were found for \.NET 99\.0\.'
        $text | Should -Not -Match 'Available \.NET 99\.0 SDKs:'
    }
}
