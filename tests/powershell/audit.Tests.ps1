Describe 'PowerShell SDK Audit' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:ToolScript = Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1'
        $script:HomeVariableName = if ($IsWindows) { 'USERPROFILE' } else { 'HOME' }

        function Write-SystemDotNetStub {
            param(
                [string]$Directory,
                [string[]]$InventoryLines = @()
            )

            New-Item -ItemType Directory -Path $Directory -Force | Out-Null
            $content = [System.Collections.Generic.List[string]]::new()
            $content.Add('@echo off')
            foreach ($line in $InventoryLines) {
                $content.Add("echo $line")
            }
            $content.Add('exit /b 0')
            Set-Content -LiteralPath (Join-Path $Directory 'dotnet.cmd') -Value $content
        }

        function Add-IsolatedSdk {
            param(
                [string]$Version,
                [switch]$Runnable
            )

            $installDirectory = Join-Path $script:ToolRoot $Version
            New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
            if ($Runnable) {
                Copy-Item `
                    -Path (Join-Path $env:ISOLATED_DOTNET_SDK_SHARED_FAKE_HOST_ROOT '*') `
                    -Destination $installDirectory `
                    -Recurse `
                    -Force
                $env:FAKE_DOTNET_SDK_VERSION = $Version
            }
            else {
                New-Item -ItemType File -Path (Join-Path $installDirectory 'dotnet.exe') -Force | Out-Null
            }
        }

        function Write-StandardMetadataFixture {
            @'
{
  "releases-index": [
    { "channel-version": "12.0", "latest-sdk": "12.0.100-preview.2.999", "support-phase": "preview", "release-type": "sts", "releases.json": "https://example.invalid/12.0.json" },
    { "channel-version": "11.0", "latest-sdk": "11.0.100-rc.2.999", "support-phase": "go-live", "release-type": "sts", "releases.json": "https://example.invalid/11.0.json" },
    { "channel-version": "10.0", "latest-sdk": "10.0.401", "support-phase": "active", "release-type": "lts", "releases.json": "https://example.invalid/10.0.json" },
    { "channel-version": "9.0", "latest-sdk": "9.0.318", "support-phase": "maintenance", "release-type": "sts", "releases.json": "https://example.invalid/9.0.json" },
    { "channel-version": "8.0", "latest-sdk": "8.0.425", "support-phase": "maintenance", "release-type": "lts", "releases.json": "https://example.invalid/8.0.json" },
    { "channel-version": "7.0", "latest-sdk": "7.0.410", "support-phase": "eol", "release-type": "sts", "releases.json": "https://example.invalid/7.0.json" },
    { "channel-version": "6.0", "latest-sdk": "6.0.428", "support-phase": "unsupported", "release-type": "lts", "releases.json": "https://example.invalid/6.0.json" }
  ]
}
'@ | Set-Content -LiteralPath (Join-Path $script:MetadataRoot 'releases-index.json')

            @'
{"releases":[
  {"release-date":"2026-09-01","security":false,"sdk":{"version":"10.0.401"}}
]}
'@ | Set-Content -LiteralPath (Join-Path $script:MetadataRoot '10.0.json')
            @'
{"releases":[
  {"release-date":"2026-07-01","security":false,"sdk":{"version":"9.0.306"}},
  {"release-date":"2026-09-01","security":true,"sdk":{"version":"9.0.318"}}
]}
'@ | Set-Content -LiteralPath (Join-Path $script:MetadataRoot '9.0.json')
            @'
{"releases":[
  {"release-date":"2026-06-01","security":false,"sdk":{"version":"8.0.303"}},
  {"release-date":"2026-09-01","security":false,"sdk":{"version":"8.0.425"}}
]}
'@ | Set-Content -LiteralPath (Join-Path $script:MetadataRoot '8.0.json')
            @'
{"releases":[
  {"release-date":"2024-05-01","security":true,"sdk":{"version":"7.0.410"}}
]}
'@ | Set-Content -LiteralPath (Join-Path $script:MetadataRoot '7.0.json')
            @'
{"releases":[
  {"release-date":"2026-09-01","security":false,"sdk":{"version":"11.0.100-rc.1.111"}},
  {"release-date":"2026-10-01","security":true,"sdk":{"version":"11.0.100-rc.2.999"}}
]}
'@ | Set-Content -LiteralPath (Join-Path $script:MetadataRoot '11.0.json')
            @'
{"releases":[
  {"release-date":"2026-09-01","security":false,"sdk":{"version":"12.0.100-preview.1.111"}},
  {"release-date":"2026-10-01","security":true,"sdk":{"version":"12.0.100-preview.2.999"}}
]}
'@ | Set-Content -LiteralPath (Join-Path $script:MetadataRoot '12.0.json')
            @'
{"releases":[
  {"release-date":"2024-11-01","security":false,"sdk":{"version":"6.0.428"}}
]}
'@ | Set-Content -LiteralPath (Join-Path $script:MetadataRoot '6.0.json')
        }

        function Invoke-TestAudit {
            $output = @(& pwsh -NoProfile -Command '
                $env:PATH = "$env:ISOLATED_DOTNET_SDK_SYSTEM_BIN;$env:PATH"
                function Invoke-RestMethod {
                    param([string]$Uri)
                    Add-Content -LiteralPath $env:AUDIT_NETWORK_LOG -Value $Uri
                    if ($Uri -like "*releases-index.json") {
                        if ($env:AUDIT_FAIL_INDEX -eq "true") { throw "index transport" }
                        return Get-Content -LiteralPath (Join-Path $env:AUDIT_METADATA_ROOT "releases-index.json") -Raw | ConvertFrom-Json
                    }
                    $name = [IO.Path]::GetFileNameWithoutExtension($Uri)
                    if ($env:AUDIT_FAIL_CHANNEL -eq $name) { throw "channel transport" }
                    return Get-Content -LiteralPath (Join-Path $env:AUDIT_METADATA_ROOT "$name.json") -Raw | ConvertFrom-Json
                }
                & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Audit
            ' 2>&1)
            return [pscustomobject]@{
                ExitCode = $LASTEXITCODE
                Text = $output -join [Environment]::NewLine
            }
        }
    }

    BeforeEach {
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-audit-tests-{0}" -f [guid]::NewGuid())
        $script:TestHome = Join-Path $script:TestRoot 'home'
        $script:ToolRoot = Join-Path $script:TestHome 'dotnet-sdks'
        $script:ToolPath = Join-Path $script:ToolRoot 'isolated-dotnet-sdk.ps1'
        $script:SystemBin = Join-Path $script:TestRoot 'system-bin'
        $script:MetadataRoot = Join-Path $script:TestRoot 'metadata'
        $script:NetworkLog = Join-Path $script:TestRoot 'network.log'
        $script:OriginalHomeValue = [Environment]::GetEnvironmentVariable($script:HomeVariableName, 'Process')

        New-Item -ItemType Directory -Path $script:ToolRoot, $script:SystemBin, $script:MetadataRoot -Force | Out-Null
        Copy-Item -LiteralPath $script:ToolScript -Destination $script:ToolPath -Force
        Set-Content -LiteralPath $script:NetworkLog -Value '' -NoNewline
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:TestHome, 'Process')
        $env:ISOLATED_DOTNET_SDK_TOOL_PATH = $script:ToolPath
        $env:ISOLATED_DOTNET_SDK_SYSTEM_BIN = $script:SystemBin
        $env:AUDIT_METADATA_ROOT = $script:MetadataRoot
        $env:AUDIT_NETWORK_LOG = $script:NetworkLog
        $env:AUDIT_FAIL_INDEX = 'false'
        $env:AUDIT_FAIL_CHANNEL = ''
        Write-SystemDotNetStub -Directory $script:SystemBin
        Write-StandardMetadataFixture
    }

    AfterEach {
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:OriginalHomeValue, 'Process')
        Remove-Item Env:ISOLATED_DOTNET_SDK_TOOL_PATH -ErrorAction SilentlyContinue
        Remove-Item Env:ISOLATED_DOTNET_SDK_SYSTEM_BIN -ErrorAction SilentlyContinue
        Remove-Item Env:AUDIT_METADATA_ROOT -ErrorAction SilentlyContinue
        Remove-Item Env:AUDIT_NETWORK_LOG -ErrorAction SilentlyContinue
        Remove-Item Env:AUDIT_FAIL_INDEX -ErrorAction SilentlyContinue
        Remove-Item Env:AUDIT_FAIL_CHANNEL -ErrorAction SilentlyContinue
        Remove-Item Env:FAKE_DOTNET_SDK_VERSION -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'reports servicing and lifecycle states for isolated and system SDKs' {
        foreach ($version in @('12.0.100-preview.1.111', '11.0.100-rc.1.111', '10.0.401', '9.0.306', '8.0.303', '7.0.410', '6.0.428')) {
            Add-IsolatedSdk -Version $version
        }
        Write-SystemDotNetStub -Directory $script:SystemBin -InventoryLines @(
            '10.0.401 [C:\dotnet\sdk]',
            '8.0.425 [C:\dotnet\sdk]'
        )

        $result = Invoke-TestAudit

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match '\.NET SDK audit'
        $result.Text | Should -Match 'Isolated SDKs:'
        $result.Text | Should -Match '9\.0\.306  Security update available -> 9\.0\.318  Maintenance'
        $result.Text | Should -Match '8\.0\.303  Update available -> 8\.0\.425  Maintenance'
        $result.Text | Should -Match '7\.0\.410  End of life'
        $result.Text | Should -Match '12\.0\.100-preview\.1\.111  Update available -> 12\.0\.100-preview\.2\.999  Preview'
        $result.Text | Should -Match '11\.0\.100-rc\.1\.111  Update available -> 11\.0\.100-rc\.2\.999  Go Live'
        $result.Text | Should -Match '6\.0\.428  Unsupported'
        $result.Text | Should -Match 'System SDKs:'
        $result.Text | Should -Match '8\.0\.425  Maintenance'
        $result.Text | Should -Not -Match 'Vulnerable'
    }

    It 'preserves duplicate versions across ownership groups' {
        Add-IsolatedSdk -Version '10.0.401'
        Write-SystemDotNetStub -Directory $script:SystemBin -InventoryLines @('10.0.401 [C:\dotnet\sdk]')

        $result = Invoke-TestAudit

        $result.ExitCode | Should -Be 0
        ([regex]::Matches($result.Text, '(?m)^  10\.0\.401  Current\r?$')).Count | Should -Be 2
    }

    It 'does not mark an SDK newer than known metadata as outdated' {
        Add-IsolatedSdk -Version '10.0.999'

        $result = Invoke-TestAudit

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match '10\.0\.999  Newer than known metadata'
        $result.Text | Should -Not -Match '10\.0\.999  Update available'
    }

    It 'reports an unrecognized installed channel without fabricated lifecycle data' {
        Add-IsolatedSdk -Version '13.0.100'

        $result = Invoke-TestAudit

        $result.ExitCode | Should -Be 0
        $result.Text | Should -Match '13\.0\.100  Unknown channel'
    }

    It 'fails clearly when the release index cannot be obtained' {
        Add-IsolatedSdk -Version '10.0.401'
        $env:AUDIT_FAIL_INDEX = 'true'

        $result = Invoke-TestAudit

        $result.ExitCode | Should -Not -Be 0
        $result.Text | Should -Match 'Unable to load \.NET release metadata from Microsoft\.'
        $result.Text | Should -Not -Match '10\.0\.401  Current'
    }


    It 'fails clearly when required channel metadata cannot be obtained' {
        Add-IsolatedSdk -Version '10.0.401'
        $env:AUDIT_FAIL_CHANNEL = '10.0'

        $result = Invoke-TestAudit

        $result.ExitCode | Should -Not -Be 0
        $result.Text | Should -Match 'Unable to load release metadata for \.NET 10\.0\.'
        $result.Text | Should -Not -Match '10\.0\.401  Current'
    }

    It 'fails clearly when required channel metadata is malformed' {
        Add-IsolatedSdk -Version '10.0.401'
        Set-Content -LiteralPath (Join-Path $script:MetadataRoot '10.0.json') -Value '{}'

        $result = Invoke-TestAudit

        $result.ExitCode | Should -Not -Be 0
        $result.Text | Should -Match 'Invalid release metadata for \.NET 10\.0\.'
        $result.Text | Should -Not -Match '10\.0\.401  Current'
    }

    It 'rejects an SDK version argument for Audit' {
        $output = @(& pwsh -NoProfile -File $script:ToolPath -Action Audit -SdkVersion 10.0.401 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        ($output -join [Environment]::NewLine) | Should -Match '-SdkVersion is supported only with -Action Install, Remove, or Verify\.'
    }

    It 'returns to Main after interactive Audit completes' {
        Add-IsolatedSdk -Version '10.0.401'
        $output = @(& pwsh -NoProfile -Command '
            $env:PATH = "$env:ISOLATED_DOTNET_SDK_SYSTEM_BIN;$env:PATH"
            $global:responses = [System.Collections.Generic.Queue[string]]::new()
            $global:responses.Enqueue("A")
            $global:responses.Enqueue("E")
            function Read-Host { param([string]$Prompt) $global:responses.Dequeue() }
            function Invoke-RestMethod {
                param([string]$Uri)
                if ($Uri -like "*releases-index.json") {
                    return Get-Content -LiteralPath (Join-Path $env:AUDIT_METADATA_ROOT "releases-index.json") -Raw | ConvertFrom-Json
                }
                $name = [IO.Path]::GetFileNameWithoutExtension($Uri)
                return Get-Content -LiteralPath (Join-Path $env:AUDIT_METADATA_ROOT "$name.json") -Raw | ConvertFrom-Json
            }
            & $env:ISOLATED_DOTNET_SDK_TOOL_PATH
        ' 2>&1)
        $text = $output -join [Environment]::NewLine

        $LASTEXITCODE | Should -Be 0
        $text | Should -Match 'A\. Audit installed SDKs'
        $text | Should -Match '10\.0\.401  Current'
        ([regex]::Matches($text, 'What would you like to do\?')).Count | Should -Be 2
        $text | Should -Match 'Exiting\.'
    }

    It 'keeps List and Verify independent of release metadata' {
        Add-IsolatedSdk -Version '10.0.401' -Runnable
        $listOutput = @(& pwsh -NoProfile -Command '
            $env:PATH = "$env:ISOLATED_DOTNET_SDK_SYSTEM_BIN;$env:PATH"
            function Invoke-RestMethod { throw "network-should-not-be-used" }
            & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action List
        ' 2>&1)
        $listExitCode = $LASTEXITCODE

        $verifyOutput = @(& pwsh -NoProfile -Command '
            $env:PATH = "$env:ISOLATED_DOTNET_SDK_SYSTEM_BIN;$env:PATH"
            function Invoke-RestMethod { throw "network-should-not-be-used" }
            & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Verify -SdkVersion 10.0.401
        ' 2>&1)
        $verifyExitCode = $LASTEXITCODE

        $listExitCode | Should -Be 0
        ($listOutput -join [Environment]::NewLine) | Should -Not -Match 'network-should-not-be-used'
        $verifyExitCode | Should -Be 0
        ($verifyOutput -join [Environment]::NewLine) | Should -Match 'Isolated SDK 10\.0\.401 is healthy\.'
        ($verifyOutput -join [Environment]::NewLine) | Should -Not -Match 'network-should-not-be-used'
    }
}
