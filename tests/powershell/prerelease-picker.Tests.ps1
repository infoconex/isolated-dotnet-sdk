Describe 'PowerShell prerelease channel SDK picker' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:ToolScript = Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1'

        function Invoke-Picker {
            param(
                [string]$LatestSdk = '99.0.100-rc.2.22',
                [string]$SupportPhase = 'preview',
                [bool]$StableData = $false,
                [bool]$SingleVersion = $false,
                [bool]$SystemInstalled = $false,
                [string[]]$InputLines = @('1', 'q')
            )

            $command = @'
$releaseIndex = [pscustomobject]@{
    'releases-index' = @([pscustomobject]@{
        'channel-version' = '99.0'
        'latest-sdk' = $env:FAKE_LATEST
        'support-phase' = $env:FAKE_PHASE
        'release-type' = 'sts'
        'releases.json' = 'https://example.invalid/99.0/releases.json'
    })
}
$releases = if ($env:FAKE_SINGLE -eq '1') {
    @('99.0.100-rc.2.22')
}
elseif ($env:FAKE_STABLE -eq '1') {
    @('99.0.100-preview.5.5', '99.0.101', '99.0.100-rc.2.22', '99.0.100')
}
else {
    @('99.0.100-preview.5.5', '99.0.100-rc.1.11', '99.0.100-preview.6.6', '99.0.100-rc.2.22')
}
$channelMetadata = [pscustomobject]@{
    releases = @($releases | ForEach-Object { [pscustomobject]@{ sdk = [pscustomobject]@{ version = $_ } } })
}
function Invoke-RestMethod {
    param($Uri)
    if ($Uri -like '*releases-index.json') { return $releaseIndex }
    return $channelMetadata
}
& $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install
'@
            $info = [System.Diagnostics.ProcessStartInfo]::new()
            $info.FileName = 'pwsh'
            $info.UseShellExecute = $false
            $info.RedirectStandardInput = $true
            $info.RedirectStandardOutput = $true
            $info.RedirectStandardError = $true
            $info.ArgumentList.Add('-NoProfile')
            $info.ArgumentList.Add('-Command')
            $info.ArgumentList.Add($command)
            $info.Environment['ISOLATED_DOTNET_SDK_TOOL_PATH'] = $script:ToolPath
            $info.Environment['USERPROFILE'] = $script:TestHome
            $info.Environment['HOME'] = $script:TestHome
            $info.Environment['FAKE_LATEST'] = $LatestSdk
            $info.Environment['FAKE_PHASE'] = $SupportPhase
            $info.Environment['FAKE_STABLE'] = if ($StableData) { '1' } else { '0' }
            $info.Environment['FAKE_SINGLE'] = if ($SingleVersion) { '1' } else { '0' }

            if ($SystemInstalled) {
                $fakeBin = Join-Path $script:TestRoot 'system-bin'
                New-Item -ItemType Directory -Path $fakeBin -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $fakeBin 'dotnet.cmd') -Value @(
                    '@echo off'
                    'if not "%1"=="--list-sdks" exit /b 91'
                    'echo 99.0.101 [C:\system\sdk]'
                )
                $info.Environment['PATH'] = "$fakeBin$([IO.Path]::PathSeparator)$env:PATH"
            }

            $process = [System.Diagnostics.Process]::new()
            $process.StartInfo = $info
            [void]$process.Start()
            foreach ($line in $InputLines) {
                $process.StandardInput.WriteLine($line)
            }
            $process.StandardInput.Close()
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            $process.WaitForExit()
            return [pscustomobject]@{
                ExitCode = $process.ExitCode
                Output = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
            }
        }

        function Get-PickerView {
            param([string]$Output, [int]$Number = 1)
            $viewMatches = [regex]::Matches(
                $Output,
                '(?s)Available \.NET 99\.0 SDKs:(.*?)B\. Back to \.NET channels')
            if ($viewMatches.Count -lt $Number) {
                throw "Expected SDK picker view $Number, found $($viewMatches.Count). Output: $Output"
            }
            return $viewMatches[$Number - 1].Value
        }
    }

    BeforeEach {
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-picker-{0}" -f [guid]::NewGuid())
        $script:TestHome = Join-Path $script:TestRoot 'home'
        $script:ToolRoot = Join-Path $script:TestHome 'dotnet-sdks'
        $script:ToolPath = Join-Path $script:ToolRoot 'isolated-dotnet-sdk.ps1'
        New-Item -ItemType Directory -Path $script:TestHome -Force | Out-Null
        $sourceCopy = Join-Path $script:TestRoot 'isolated-dotnet-sdk.ps1'
        Copy-Item $script:ToolScript $sourceCopy
        $originalHome = [Environment]::GetEnvironmentVariable('USERPROFILE', 'Process')
        try {
            [Environment]::SetEnvironmentVariable('USERPROFILE', $script:TestHome, 'Process')
            & pwsh -NoProfile -File $sourceCopy -Action List *> $null
            $LASTEXITCODE | Should -Be 0
        }
        finally {
            [Environment]::SetEnvironmentVariable('USERPROFILE', $originalHome, 'Process')
        }
    }

    AfterEach {
        Remove-Item $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'defaults prerelease to all sorted Preview and RC milestones with latest marker' {
        $result = Invoke-Picker
        $result.ExitCode | Should -Be 0
        $view = Get-PickerView $result.Output
        $view | Should -Match '1\. 99\.0\.100-rc\.2\.22 \(latest\)'
        $view | Should -Match '2\. 99\.0\.100-rc\.1\.11'
        $view | Should -Match '3\. 99\.0\.100-preview\.6\.6'
        $view | Should -Match '4\. 99\.0\.100-preview\.5\.5'
        $view | Should -Match 'S\. Show featured versions'
        $result.Output | Should -Match 'Q\. Cancel'
    }

    It 'toggles to featured and back to all with reciprocal labels' {
        $result = Invoke-Picker -InputLines @('1', 's', 's', 'q')
        $result.ExitCode | Should -Be 0
        (Get-PickerView $result.Output 1) | Should -Match '4\. 99\.0\.100-preview\.5\.5'
        $featured = Get-PickerView $result.Output 2
        $featured | Should -Match '1\. 99\.0\.100-rc\.2\.22 \(latest\)'
        $featured | Should -Not -Match '2\. 99\.0\.100-rc\.1\.11'
        $featured | Should -Match 'S\. Show all versions'
        $expanded = Get-PickerView $result.Output 3
        $expanded | Should -Match '4\. 99\.0\.100-preview\.5\.5'
        $expanded | Should -Match 'S\. Show featured versions'
    }

    It 'keeps stable latest compact even if history includes previews and support phase says preview' {
        $result = Invoke-Picker -LatestSdk '99.0.101' -StableData $true -InputLines @('1', 's', 'q')
        $result.ExitCode | Should -Be 0
        $featured = Get-PickerView $result.Output 1
        $featured | Should -Match '1\. 99\.0\.101 \(latest\)'
        $featured | Should -Not -Match '2\. 99\.0\.100'
        $featured | Should -Match 'S\. Show all versions'
        $expanded = Get-PickerView $result.Output 2
        $expanded | Should -Match '2\. 99\.0\.100'
        $expanded | Should -Match 'S\. Show featured versions'
    }

    It 'does not offer a view toggle for one available prerelease SDK' {
        $result = Invoke-Picker -SingleVersion $true
        $result.ExitCode | Should -Be 0
        $view = Get-PickerView $result.Output
        $view | Should -Match '1\. 99\.0\.100-rc\.2\.22 \(latest\)'
        $view | Should -Not -Match 'S\. Show'
    }

    It 'falls back on missing and inconsistent latest without fabricating latest markers' {
        foreach ($latest in @('', '99.0.100-rc.99.99')) {
            $result = Invoke-Picker -LatestSdk $latest
            $result.ExitCode | Should -Be 0
            $view = Get-PickerView $result.Output
            $view | Should -Match '1\. 99\.0\.100-rc\.2\.22'
            $view | Should -Match '4\. 99\.0\.100-preview\.5\.5'
            $view | Should -Match 'S\. Show featured versions'
            $view | Should -Not -Match '\(latest\)'
        }
    }

    It 'composes latest with system-only and combined ownership markers' {
        $systemOnly = Invoke-Picker -LatestSdk '99.0.101' -StableData $true -SystemInstalled $true
        $systemOnly.ExitCode | Should -Be 0
        $view = Get-PickerView $systemOnly.Output
        $view | Should -Match '1\. 99\.0\.101 \(latest, installed system-sdk\)'
        $view | Should -Not -Match 'installed isolated-sdk'

        $sdkDir = Join-Path $script:ToolRoot '99.0.101'
        New-Item -ItemType Directory -Path $sdkDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $sdkDir 'dotnet.exe') -Force | Out-Null
        $both = Invoke-Picker -LatestSdk '99.0.101' -StableData $true -SystemInstalled $true
        $both.ExitCode | Should -Be 0
        (Get-PickerView $both.Output) |
            Should -Match '1\. 99\.0\.101 \(latest, installed system-sdk, installed isolated-sdk\)'
    }

    It 'falls back to newest discovered stable SDK and preserves isolated marker' {
        $sdkDir = Join-Path $script:ToolRoot '99.0.101'
        New-Item -ItemType Directory -Path $sdkDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $sdkDir 'dotnet.exe') -Force | Out-Null
        $result = Invoke-Picker -LatestSdk 'not-in-releases' -StableData $true
        $result.ExitCode | Should -Be 0
        $view = Get-PickerView $result.Output
        $view | Should -Match '1\. 99\.0\.101 \(installed isolated-sdk\)'
        $view | Should -Match 'S\. Show all versions'
        $view | Should -Not -Match '\(latest'
    }
}
