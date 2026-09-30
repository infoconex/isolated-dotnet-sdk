Describe 'PowerShell release-metadata behavior' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:ToolScript = Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1'
        $script:HomeVariableName = if ($IsWindows) { 'USERPROFILE' } else { 'HOME' }
    }

    BeforeEach {
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-metadata-tests-{0}" -f [guid]::NewGuid())
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

    It 'fails before channel selection when the release index is empty' {
        $metadataOutput = @(& pwsh -NoProfile -Command '
            function Invoke-RestMethod {
                [pscustomobject]@{ "releases-index" = @() }
            }
            & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install
        ' 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        $text = $metadataOutput -join [Environment]::NewLine
        $text | Should -Match 'No selectable .NET channels were found in Microsoft release metadata\.'
        $text | Should -Not -Match 'Select a supported or development \.NET channel:'
    }

    It 'reports a selected-channel network failure with channel context' {
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
                                "latest-sdk" = "99.0.100"
                                "support-phase" = "active"
                                "release-type" = "sts"
                                "releases.json" = "https://example.invalid/releases.json"
                            }
                        )
                    }
                }
                throw "transport-specific channel detail"
            }
            & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install
        ' 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        $text = $metadataOutput -join [Environment]::NewLine
        $text | Should -Match 'Unable to load release metadata for \.NET 99\.0\.'
        $text | Should -Not -Match 'transport-specific channel detail'
    }

    It 'normalizes sdk and sdks entries and selects the displayed newest SDK' {
        $metadataOutput = @(& pwsh -NoProfile -Command '
            $global:metadataResponses = [System.Collections.Generic.Queue[string]]::new()
            $global:metadataResponses.Enqueue("1")
            $global:metadataResponses.Enqueue("1")
            function Read-Host { param([string]$Prompt) $global:metadataResponses.Dequeue() }
            function Invoke-RestMethod {
                param([string]$Uri)
                if ($Uri -like "*releases-index.json") {
                    return [pscustomobject]@{
                        "releases-index" = @(
                            [pscustomobject]@{
                                "channel-version" = "99.0"
                                "latest-sdk" = "99.0.999"
                                "support-phase" = "active"
                                "release-type" = "sts"
                                "releases.json" = "https://example.invalid/releases.json"
                            }
                        )
                    }
                }
                return [pscustomobject]@{
                    releases = @(
                        [pscustomobject]@{
                            sdk = [pscustomobject]@{ version = "99.0.100" }
                            sdks = @(
                                [pscustomobject]@{ version = "99.0.100" },
                                [pscustomobject]@{ version = "99.0.101" }
                            )
                        }
                    )
                }
            }
            function Invoke-WebRequest { throw "release-metadata-download-boundary" }
            & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -Yes
        ' 6>&1 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        $text = $metadataOutput -join [Environment]::NewLine
        $text | Should -Match 'Target SDK: 99\.0\.101'
        $text | Should -Match 'release-metadata-download-boundary'
    }

    It 'bypasses release metadata discovery when an exact version is supplied' {
        $metadataOutput = @(& pwsh -NoProfile -Command '
            function Invoke-RestMethod { throw "metadata-discovery-was-called" }
            function Invoke-WebRequest { throw "release-metadata-download-boundary" }
            & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -Version 99.9.999 -Yes
        ' 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        $text = $metadataOutput -join [Environment]::NewLine
        $text | Should -Match 'release-metadata-download-boundary'
        $text | Should -Not -Match 'metadata-discovery-was-called'
        $text | Should -Not -Match 'Loading available \.NET SDK releases from Microsoft'
    }
}
