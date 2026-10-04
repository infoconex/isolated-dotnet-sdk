Describe 'PowerShell tool version identity' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:ToolScript = Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1'
        $script:StampScript = Join-Path $script:RepositoryRoot 'scripts/Set-ReleaseToolVersion.ps1'
        $script:PowerShellPath = (Get-Process -Id $PID).Path

        function Invoke-ToolProcess {
            param(
                [string]$ToolPath,
                [string[]]$Arguments = @(),
                [string[]]$InputLines = @(),
                [string]$HomePath
            )

            $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
            $startInfo.FileName = $script:PowerShellPath
            $startInfo.UseShellExecute = $false
            $startInfo.RedirectStandardInput = $true
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true
            $startInfo.ArgumentList.Add('-NoProfile')
            $startInfo.ArgumentList.Add('-File')
            $startInfo.ArgumentList.Add($ToolPath)
            foreach ($argument in $Arguments) {
                $startInfo.ArgumentList.Add($argument)
            }
            $startInfo.Environment['HOME'] = $HomePath
            $startInfo.Environment['USERPROFILE'] = $HomePath
            $startInfo.Environment['PATH'] = ''
            $startInfo.Environment['HTTP_PROXY'] = 'http://127.0.0.1:1'
            $startInfo.Environment['HTTPS_PROXY'] = 'http://127.0.0.1:1'
            $startInfo.Environment['http_proxy'] = 'http://127.0.0.1:1'
            $startInfo.Environment['https_proxy'] = 'http://127.0.0.1:1'

            $process = [System.Diagnostics.Process]::new()
            $process.StartInfo = $startInfo
            [void]$process.Start()

            foreach ($line in $InputLines) {
                $process.StandardInput.WriteLine($line)
            }
            $process.StandardInput.Close()

            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()
            $process.WaitForExit()

            $stdout = $stdoutTask.GetAwaiter().GetResult()
            $stderr = $stderrTask.GetAwaiter().GetResult()
            return [pscustomobject]@{
                ExitCode = $process.ExitCode
                StdOut   = $stdout
                StdErr   = $stderr
                Output   = $stdout + $stderr
            }
        }
    }

    BeforeEach {
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-version-{0}" -f [guid]::NewGuid())
        $script:TestHome = Join-Path $script:TestRoot 'home'
        New-Item -ItemType Directory -Path $script:TestHome -Force | Out-Null
    }

    AfterEach {
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'reports development identity without bootstrap or operational dependencies' {
        $result = Invoke-ToolProcess `
            -ToolPath $script:ToolScript `
            -Arguments @('-Version') `
            -HomePath $script:TestHome

        $result.ExitCode | Should -Be 0
        $result.StdOut.Trim() | Should -Be 'isolated-dotnet-sdk development (main)'
        Test-Path -LiteralPath (Join-Path $script:TestHome 'dotnet-sdks') | Should -BeFalse
    }

    It 'reports an exact stable release marker without bootstrap or operational dependencies' {
        $stableTool = Join-Path $script:TestRoot 'isolated-dotnet-sdk.ps1'
        $content = Get-Content -LiteralPath $script:ToolScript -Raw
        $content = $content.Replace(
            '$ToolReleaseIdentity = ''development''',
            '$ToolReleaseIdentity = ''v9.8.7''')
        [System.IO.File]::WriteAllText($stableTool, $content, [System.Text.UTF8Encoding]::new($false))

        $result = Invoke-ToolProcess `
            -ToolPath $stableTool `
            -Arguments @('-Version') `
            -HomePath $script:TestHome

        $result.ExitCode | Should -Be 0
        $result.StdOut.Trim() | Should -Be 'isolated-dotnet-sdk v9.8.7'
        Test-Path -LiteralPath (Join-Path $script:TestHome 'dotnet-sdks') | Should -BeFalse
    }

    It 'displays development identity in persistent Main' {
        $toolRoot = Join-Path $script:TestHome 'dotnet-sdks'
        $savedTool = Join-Path $toolRoot 'isolated-dotnet-sdk.ps1'
        New-Item -ItemType Directory -Path $toolRoot -Force | Out-Null
        Copy-Item -LiteralPath $script:ToolScript -Destination $savedTool -Force

        $result = Invoke-ToolProcess `
            -ToolPath $savedTool `
            -InputLines @('E') `
            -HomePath $script:TestHome

        $result.ExitCode | Should -Be 0
        ([regex]::Matches($result.Output, 'Isolated \.NET SDK development \(main\)')).Count | Should -Be 1
        $result.Output | Should -Match 'What would you like to do\?'
    }

    It 'supports -SdkVersion as the explicit SDK selector' {
        $toolRoot = Join-Path $script:TestHome 'dotnet-sdks'
        $savedTool = Join-Path $toolRoot 'isolated-dotnet-sdk.ps1'
        New-Item -ItemType Directory -Path $toolRoot -Force | Out-Null
        Copy-Item -LiteralPath $script:ToolScript -Destination $savedTool -Force

        $result = Invoke-ToolProcess `
            -ToolPath $savedTool `
            -Arguments @('-SdkVersion', 'bad/version') `
            -HomePath $script:TestHome

        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match 'Invalid SDK version: bad/version'
        $result.Output | Should -Not -Match 'isolated-dotnet-sdk development \(main\)'
    }

    It 'supports a positional SDK version with the same semantics' {
        $toolRoot = Join-Path $script:TestHome 'dotnet-sdks'
        $savedTool = Join-Path $toolRoot 'isolated-dotnet-sdk.ps1'
        New-Item -ItemType Directory -Path $toolRoot -Force | Out-Null
        Copy-Item -LiteralPath $script:ToolScript -Destination $savedTool -Force

        $result = Invoke-ToolProcess `
            -ToolPath $savedTool `
            -Arguments @('bad/version') `
            -HomePath $script:TestHome

        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match 'Invalid SDK version: bad/version'
        $result.Output | Should -Not -Match 'isolated-dotnet-sdk development \(main\)'
    }

    It 'rejects combining the tool version query with an SDK selector without bootstrapping' {
        $result = Invoke-ToolProcess `
            -ToolPath $script:ToolScript `
            -Arguments @('-Version', '-SdkVersion', '10.0.100') `
            -HomePath $script:TestHome

        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match '-Version cannot be combined'
        Test-Path -LiteralPath (Join-Path $script:TestHome 'dotnet-sdks') | Should -BeFalse
    }

    It 'stamps both product scripts from one stable tag' {
        $releaseRoot = Join-Path $script:TestRoot 'release-tree'
        New-Item -ItemType Directory -Path $releaseRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1') -Destination $releaseRoot
        Copy-Item -LiteralPath (Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.sh') -Destination $releaseRoot

        & $script:StampScript -RepositoryRoot $releaseRoot -ReleaseTag 'v9.8.7'

        $powerShellContent = Get-Content -LiteralPath (Join-Path $releaseRoot 'isolated-dotnet-sdk.ps1') -Raw
        $bashContent = Get-Content -LiteralPath (Join-Path $releaseRoot 'isolated-dotnet-sdk.sh') -Raw
        $stablePowerShellMarker = [regex]::Escape('$ToolReleaseIdentity = ''v9.8.7''')
        $developmentPowerShellMarker = [regex]::Escape('$ToolReleaseIdentity = ''development''')
        $powerShellContent | Should -Match $stablePowerShellMarker
        $bashContent | Should -Match 'TOOL_RELEASE_IDENTITY="v9\.8\.7"'
        $powerShellContent | Should -Not -Match $developmentPowerShellMarker
        $bashContent | Should -Not -Match 'TOOL_RELEASE_IDENTITY="development"'
    }
}
