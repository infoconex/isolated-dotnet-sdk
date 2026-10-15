Describe 'PowerShell Install channel ordering' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:Source = Join-Path $script:RepoRoot 'isolated-dotnet-sdk.ps1'

        function Invoke-ShuffledChannelPicker {
            param([string]$Selections)
            $command = @'
$answers = [System.Collections.Generic.Queue[string]]::new()
foreach ($answer in $env:CHANNEL_TEST_INPUT.Split(',')) { $answers.Enqueue($answer) }
function Read-Host {
    param([string]$Prompt)
    if ($answers.Count -eq 0) { throw 'Unexpected Install picker input request.' }
    return $answers.Dequeue()
}
function Invoke-RestMethod {
    param([string]$Uri)
    if ($Uri -like '*releases-index.json') {
        $entries = @(
            @('9.0', '9.0.318', 'active', 'sts'),
            @('2.1', '2.1.818', 'eol', 'lts'),
            @('8.0', '8.0.425', 'maintenance', 'lts'),
            @('2.2', '2.2.207', 'eol', 'sts'),
            @('oops', '0.0.100', 'eol', 'sts'),
            @('2.0', '2.1.202', 'eol', 'sts'),
            @('10.0', '10.0.402', 'active', 'lts')
        )
        $channels = @($entries | ForEach-Object {
            [pscustomobject]@{
                'channel-version' = $_[0]
                'latest-sdk' = $_[1]
                'support-phase' = $_[2]
                'release-type' = $_[3]
                'releases.json' = "https://example.invalid/$($_[0])/releases.json"
            }
        })
        $channels += [pscustomobject]@{
            'channel-version' = '11.0'
            'latest-sdk' = '11.0.100'
            'support-phase' = 'active'
            'release-type' = 'sts'
        }
        return [pscustomobject]@{ 'releases-index' = $channels }
    }
    $match = [regex]::Match($Uri, '^https://example\.invalid/([^/]+)/releases\.json$')
    if (-not $match.Success) { throw "Unexpected channel URL: $Uri" }
    $versions = @{
        '9.0' = '9.0.318'; '8.0' = '8.0.425'; '10.0' = '10.0.402'
        '2.1' = '2.1.818'; '2.2' = '2.2.207'; '2.0' = '2.1.202'
        'oops' = '0.0.100'
    }
    $version = $versions[$match.Groups[1].Value]
    return [pscustomobject]@{
        releases = @([pscustomobject]@{ sdk = [pscustomobject]@{ version = $version } })
    }
}
& $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install
'@
            $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
            $startInfo.FileName = 'pwsh'
            $startInfo.UseShellExecute = $false
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true
            $startInfo.ArgumentList.Add('-NoProfile')
            $startInfo.ArgumentList.Add('-Command')
            $startInfo.ArgumentList.Add($command)
            $startInfo.Environment['ISOLATED_DOTNET_SDK_TOOL_PATH'] = $script:ToolPath
            $startInfo.Environment['CHANNEL_TEST_INPUT'] = $Selections
            $startInfo.Environment['HOME'] = $script:Home
            $startInfo.Environment['USERPROFILE'] = $script:Home
            $process = [System.Diagnostics.Process]::new()
            $process.StartInfo = $startInfo
            [void]$process.Start()
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            $process.WaitForExit()
            return [pscustomobject]@{
                ExitCode = $process.ExitCode
                Output = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
            }
        }

        function Get-ChannelMenuVersions {
            param([string]$Output, [string]$Heading, [string]$Toggle)
            $start = $Output.IndexOf($Heading, [StringComparison]::Ordinal)
            if ($start -lt 0) { throw "Missing $Heading in: $Output" }
            $end = $Output.IndexOf($Toggle, $start, [StringComparison]::Ordinal)
            if ($end -lt 0) { throw "Missing $Toggle in: $Output" }
            $menu = $Output.Substring($start, $end - $start)
            return @([regex]::Matches($menu, '(?m)^\s*\d+\. \.NET (\S+)') | ForEach-Object { $_.Groups[1].Value })
        }
    }

    BeforeEach {
        $script:Root = Join-Path ([IO.Path]::GetTempPath()) ("isolated-dotnet-channel-sort-{0}" -f [guid]::NewGuid())
        $script:Home = Join-Path $script:Root 'home'
        $toolRoot = Join-Path $script:Home 'dotnet-sdks'
        $script:ToolPath = Join-Path $toolRoot 'isolated-dotnet-sdk.ps1'
        New-Item -ItemType Directory -Path $toolRoot -Force | Out-Null
        Copy-Item -LiteralPath $script:Source -Destination $script:ToolPath
    }

    AfterEach {
        Remove-Item -LiteralPath $script:Root -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'orders shuffled supported and EOL records numerically, retaining malformed records last' {
        $result = Invoke-ShuffledChannelPicker -Selections 's,q'
        $result.ExitCode | Should -Be 0
        @(Get-ChannelMenuVersions -Output $result.Output -Heading 'Select a supported or development .NET channel:' -Toggle 'S. Show end-of-life channels') | Should -Be @('10.0', '9.0', '8.0')
        @(Get-ChannelMenuVersions -Output $result.Output -Heading 'Select an end-of-life .NET channel:' -Toggle 'S. Show supported/development channels') | Should -Be @('2.2', '2.1', '2.0', 'oops')
        $result.Output | Should -Not -Match '\.NET 11\.0'
    }

    It 'opens the correct metadata after selecting a newly ordered EOL row' {
        $result = Invoke-ShuffledChannelPicker -Selections 's,2,b,q'
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'Available \.NET 2\.1 SDKs:'
        $result.Output | Should -Match '1\. 2\.1\.818 \(latest\)'
        $result.Output | Should -Not -Match 'Available \.NET 2\.2 SDKs:'
    }

    It 'keeps supported selection and Back/Cancel behavior intact' {
        $result = Invoke-ShuffledChannelPicker -Selections '1,b,q'
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'Available \.NET 10\.0 SDKs:'
        $result.Output | Should -Match '1\. 10\.0\.402 \(latest\)'
        $result.Output | Should -Not -Match 'Available \.NET 9\.0 SDKs:'
    }
}
