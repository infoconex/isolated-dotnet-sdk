Describe 'PowerShell removal behavior' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:ToolScript = Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1'
        $script:RemovalVersion = '99.0.0-removal-test'
        $script:HomeVariableName = if ($IsWindows) { 'USERPROFILE' } else { 'HOME' }

        function Import-ToolFunctionDefinition {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:ToolScript,
                [ref]$tokens,
                [ref]$errors)

            if ($errors.Count -gt 0) {
                throw "Unable to parse product script for removal tests: $($errors[0].Message)"
            }

            $functionDefinitions = $ast.FindAll(
                {
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
                },
                $true)

            foreach ($functionDefinition in $functionDefinitions) {
                $bodyText = $functionDefinition.Body.Extent.Text
                $bodyText = $bodyText.Substring(1, $bodyText.Length - 2)
                Set-Item `
                    -Path "Function:script:$($functionDefinition.Name)" `
                    -Value ([scriptblock]::Create($bodyText))
            }
        }

        function Install-TestTool {
            & pwsh -NoProfile -File $script:ToolScript -Action List *> $null
            $LASTEXITCODE | Should -Be 0
        }

        function Initialize-TestRemovalTarget {
            $installDirectory = Join-Path $script:SdkRoot $script:SdkVersion
            if (Test-Path -LiteralPath $installDirectory) {
                Microsoft.PowerShell.Management\Remove-Item -LiteralPath $installDirectory -Recurse -Force
            }

            New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $installDirectory 'dotnet.exe') -Force | Out-Null
            return $installDirectory
        }
    }

    BeforeEach {
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-removal-tests-{0}" -f [guid]::NewGuid())
        $script:TestHome = Join-Path $script:TestRoot 'home'
        $script:ToolRoot = Join-Path $script:TestHome 'dotnet-sdks'
        $script:InstalledToolPath = Join-Path $script:ToolRoot 'isolated-dotnet-sdk.ps1'
        $script:OriginalHomeValue = [Environment]::GetEnvironmentVariable($script:HomeVariableName, 'Process')

        New-Item -ItemType Directory -Path $script:TestHome -Force | Out-Null
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:TestHome, 'Process')
    }

    AfterEach {
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:OriginalHomeValue, 'Process')
        Microsoft.PowerShell.Management\Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'process-level behavior' {
        It 'forwards -WhatIf through source bootstrap without changing SDK state' {
            $publicInstallDirectory = Join-Path $script:ToolRoot $script:RemovalVersion
            New-Item -ItemType Directory -Path $publicInstallDirectory -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $publicInstallDirectory 'dotnet.exe') -Force | Out-Null

            $whatIfOutput = @(& pwsh -NoProfile -File $script:ToolScript -Action Remove -SdkVersion $script:RemovalVersion -WhatIf *>&1)

            $LASTEXITCODE | Should -Be 0
            Test-Path -LiteralPath $publicInstallDirectory | Should -BeTrue
            ($whatIfOutput -join [Environment]::NewLine) | Should -Match 'What if:'
        }

        It 'forwards the legacy opt-in through bootstrap while WhatIf preserves the target' {
            $version = '1.0.4'
            $publicInstallDirectory = Join-Path $script:ToolRoot $version
            New-Item -ItemType Directory -Path $publicInstallDirectory -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $publicInstallDirectory 'dotnet.exe') -Force | Out-Null

            $whatIfOutput = @(& pwsh -NoProfile -File $script:ToolScript -Action Remove -SdkVersion $version -AllowUnsupportedShutdown -Yes -WhatIf *>&1)

            $LASTEXITCODE | Should -Be 0
            Test-Path -LiteralPath $publicInstallDirectory | Should -BeTrue
            ($whatIfOutput -join [Environment]::NewLine) | Should -Match 'What if:'
        }

        It 'rejects removal-only risk-mitigation parameters on unsupported actions' {
            Install-TestTool

            $unsupportedOutput = @(& pwsh -NoProfile -File $script:InstalledToolPath -Action List -WhatIf 2>&1)

            $LASTEXITCODE | Should -Not -Be 0
            ($unsupportedOutput -join [Environment]::NewLine) | Should -Match 'supported only with.*Remove'
        }

        It 'rejects legacy shutdown approval on actions other than Remove' {
            Install-TestTool
            $output = @(& pwsh -NoProfile -File $script:InstalledToolPath -Action List -AllowUnsupportedShutdown 2>&1)

            $LASTEXITCODE | Should -Not -Be 0
            ($output -join [Environment]::NewLine) | Should -Match 'supported only with.*Remove'
        }

        It 'fails safely for non-interactive removal without explicit approval' {
            Install-TestTool
            $publicInstallDirectory = Join-Path $script:ToolRoot $script:RemovalVersion
            New-Item -ItemType Directory -Path $publicInstallDirectory -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $publicInstallDirectory 'dotnet.exe') -Force | Out-Null

            & pwsh -NoProfile -NonInteractive -File $script:InstalledToolPath -Action Remove -SdkVersion $script:RemovalVersion *> $null

            $LASTEXITCODE | Should -Not -Be 0
            Test-Path -LiteralPath $publicInstallDirectory | Should -BeTrue
        }
    }

    Context 'Remove-IsolatedSdk focused behavior' {
        BeforeEach {
            Import-ToolFunctionDefinition
            $script:SdkRoot = Join-Path $script:TestRoot 'function-home'
            $script:SdkVersion = $script:RemovalVersion
        }

        It 'discovers damaged version directories for Remove but excludes unrelated folders' {
            Import-ToolFunctionDefinition
            New-Item -ItemType Directory -Path $script:SdkRoot -Force | Out-Null
            $valid = Join-Path $script:SdkRoot '8.0.426'
            $other = Join-Path $script:SdkRoot 'notes'
            New-Item -ItemType Directory -Path $valid -Force | Out-Null
            New-Item -ItemType Directory -Path $other -Force | Out-Null
            $versions = @(Get-RemoveSdkCandidateVersion)
            $versions | Should -Contain '8.0.426'
            $versions | Should -Not -Contain 'notes'
        }

        It 'removes an incomplete no-host SDK after ordinary approval without invoking shutdown' {
            $installDirectory = Join-Path $script:SdkRoot $script:SdkVersion
            New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $installDirectory 'leftover.txt') -Value 'safe fixture'
            Set-Item -Path Function:script:Invoke-IsolatedSdkBuildServerShutdown -Value {
                throw 'shutdown must not run without a host'
            }

            Remove-IsolatedSdk -Yes

            Test-Path -LiteralPath $installDirectory | Should -BeFalse
            Test-Path -LiteralPath (Join-Path (Join-Path $script:SdkRoot '.pending-removals') $script:SdkVersion) | Should -BeFalse
        }

        It 'preserves a no-host SDK under -WhatIf without creating recovery state' {
            $installDirectory = Join-Path $script:SdkRoot $script:SdkVersion
            New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null

            Remove-IsolatedSdk -Yes -WhatIf

            Test-Path -LiteralPath $installDirectory | Should -BeTrue
            Test-Path -LiteralPath (Join-Path (Join-Path $script:SdkRoot '.pending-removals') $script:SdkVersion) | Should -BeFalse
        }

        It 'rejects arbitrary directory names and symlinked SDK targets on direct Remove' {
            New-Item -ItemType Directory -Path $script:SdkRoot -Force | Out-Null
            $other = Join-Path $script:SdkRoot 'notes'
            New-Item -ItemType Directory -Path $other -Force | Out-Null
            $script:SdkVersion = 'notes'
            { Remove-IsolatedSdk -Yes } | Should -Throw '*Invalid*'
            Test-Path -LiteralPath $other | Should -BeTrue

            $outside = Join-Path $script:TestRoot 'outside'
            New-Item -ItemType Directory -Path $outside -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $outside 'keep.txt') -Value 'protected'
            $script:SdkVersion = '9.0.117'
            $link = Join-Path $script:SdkRoot $script:SdkVersion
            New-Item -ItemType SymbolicLink -Path $link -Target $outside -ErrorAction Stop | Out-Null
            { Remove-IsolatedSdk -Yes } | Should -Throw
            Get-Content -LiteralPath (Join-Path $outside 'keep.txt') | Should -Be 'protected'
        }

        It 'exposes native WhatIf and Confirm parameters' {
            $removeCommand = Get-Command Remove-IsolatedSdk -CommandType Function

            $removeCommand.Parameters.ContainsKey('WhatIf') | Should -BeTrue
            $removeCommand.Parameters.ContainsKey('Confirm') | Should -BeTrue
            $removeCommand.Parameters.ContainsKey('AllowUnsupportedShutdown') | Should -BeTrue
        }

        It 'keeps the SDK and skips shutdown after default cancellation' {
            $installDirectory = Initialize-TestRemovalTarget
            $script:ConfirmationCallCount = 0
            $script:ShutdownCallCount = 0
            Set-Item -Path Function:script:Confirm-Action -Value {
                param([string]$Prompt)
                $null = $Prompt
                $script:ConfirmationCallCount++
                return $false
            }
            Set-Item -Path Function:script:Invoke-IsolatedSdkBuildServerShutdown -Value {
                param([string]$DotNetPath, [string]$SdkVersion)
                $null = $DotNetPath
                $null = $SdkVersion
                $script:ShutdownCallCount++
                throw 'shutdown must not run after cancellation'
            }

            Remove-IsolatedSdk

            $script:ConfirmationCallCount | Should -Be 1
            $script:ShutdownCallCount | Should -Be 0
            Test-Path -LiteralPath $installDirectory | Should -BeTrue
        }

        It 'shuts down once and removes the selected SDK after default approval' {
            $installDirectory = Initialize-TestRemovalTarget
            $script:ConfirmationCallCount = 0
            $script:ShutdownCallCount = 0
            Set-Item -Path Function:script:Confirm-Action -Value {
                param([string]$Prompt)
                $null = $Prompt
                $script:ConfirmationCallCount++
                return $true
            }
            Set-Item -Path Function:script:Invoke-IsolatedSdkBuildServerShutdown -Value {
                param([string]$DotNetPath, [string]$SdkVersion)
                $null = $DotNetPath
                $null = $SdkVersion
                $script:ShutdownCallCount++
            }

            Remove-IsolatedSdk

            $script:ConfirmationCallCount | Should -Be 1
            $script:ShutdownCallCount | Should -Be 1
            Test-Path -LiteralPath $installDirectory | Should -BeFalse
        }

        It 'uses -Confirm:$false as an automation path without tool-owned prompting' {
            $installDirectory = Initialize-TestRemovalTarget
            $script:ShutdownCallCount = 0
            Set-Item -Path Function:script:Confirm-Action -Value {
                param([string]$Prompt)
                $null = $Prompt
                throw 'tool-owned confirmation must not run for explicit -Confirm:$false'
            }
            Set-Item -Path Function:script:Invoke-IsolatedSdkBuildServerShutdown -Value {
                param([string]$DotNetPath, [string]$SdkVersion)
                $null = $DotNetPath
                $null = $SdkVersion
                $script:ShutdownCallCount++
            }

            Remove-IsolatedSdk -Confirm:$false

            $script:ShutdownCallCount | Should -Be 1
            Test-Path -LiteralPath $installDirectory | Should -BeFalse
        }

        It 'supports -Yes automation' {
            $installDirectory = Initialize-TestRemovalTarget
            $script:ShutdownCallCount = 0
            Set-Item -Path Function:script:Confirm-Action -Value {
                param([string]$Prompt)
                $null = $Prompt
                throw 'tool-owned confirmation must not run for -Yes'
            }
            Set-Item -Path Function:script:Invoke-IsolatedSdkBuildServerShutdown -Value {
                param([string]$DotNetPath, [string]$SdkVersion)
                $null = $DotNetPath
                $null = $SdkVersion
                $script:ShutdownCallCount++
            }

            Remove-IsolatedSdk -Yes

            $script:ShutdownCallCount | Should -Be 1
            Test-Path -LiteralPath $installDirectory | Should -BeFalse
        }

        It 'does not require a separate legacy shutdown permission after normal approval' {
            $script:SdkVersion = '2.1.105'
            $installDirectory = Initialize-TestRemovalTarget
            $script:ShutdownApprovals = [System.Collections.Generic.List[bool]]::new()
            Set-Item -Path Function:script:Invoke-IsolatedSdkBuildServerShutdown -Value {
                param(
                    [string]$DotNetPath,
                    [string]$SdkVersion,
                    [switch]$AllowUnsupportedShutdown
                )
                $null = $DotNetPath
                $null = $SdkVersion
                $script:ShutdownApprovals.Add([bool]$AllowUnsupportedShutdown)
            }

            Remove-IsolatedSdk -Yes
            $script:ShutdownApprovals.Count | Should -Be 1
            $script:ShutdownApprovals[0] | Should -BeFalse
            Test-Path -LiteralPath $installDirectory | Should -BeFalse

            $installDirectory = Initialize-TestRemovalTarget
            Remove-IsolatedSdk -Yes -AllowUnsupportedShutdown
            $script:ShutdownApprovals.Count | Should -Be 2
            $script:ShutdownApprovals[1] | Should -BeTrue
            Test-Path -LiteralPath $installDirectory | Should -BeFalse
        }

        It 'gives -WhatIf precedence over explicit legacy approval' {
            $script:SdkVersion = '2.1.105'
            $installDirectory = Initialize-TestRemovalTarget
            Set-Item -Path Function:script:Invoke-IsolatedSdkBuildServerShutdown -Value {
                throw 'shutdown must never run for WhatIf'
            }

            Remove-IsolatedSdk -Yes -AllowUnsupportedShutdown -WhatIf

            Test-Path -LiteralPath $installDirectory | Should -BeTrue
        }

        It 'gives -WhatIf precedence over -Yes' {
            $installDirectory = Initialize-TestRemovalTarget
            $script:ShutdownCallCount = 0
            Set-Item -Path Function:script:Invoke-IsolatedSdkBuildServerShutdown -Value {
                param([string]$DotNetPath, [string]$SdkVersion)
                $null = $DotNetPath
                $null = $SdkVersion
                $script:ShutdownCallCount++
                throw 'shutdown must not run under -WhatIf'
            }

            Remove-IsolatedSdk -Yes -WhatIf

            $script:ShutdownCallCount | Should -Be 0
            Test-Path -LiteralPath $installDirectory | Should -BeTrue
        }

        It 'propagates shutdown failure and preserves the SDK directory' {
            $installDirectory = Initialize-TestRemovalTarget
            Set-Item -Path Function:script:Confirm-Action -Value {
                param([string]$Prompt)
                $null = $Prompt
                return $true
            }
            Set-Item -Path Function:script:Invoke-IsolatedSdkBuildServerShutdown -Value {
                param([string]$DotNetPath, [string]$SdkVersion)
                $null = $DotNetPath
                $null = $SdkVersion
                throw 'simulated shutdown failure'
            }

            { Remove-IsolatedSdk } | Should -Throw '*simulated shutdown failure*'
            Test-Path -LiteralPath $installDirectory | Should -BeTrue
        }

        It 'keeps locked SDK contents together while staging with an atomic directory rename' {
            $installDirectory = Initialize-TestRemovalTarget
            $lockedFile = Join-Path $installDirectory 'locked-test-file.txt'
            Set-Content -LiteralPath $lockedFile -Value 'locked fixture'
            $record = Join-Path (Join-Path $script:SdkRoot '.pending-removals') $script:SdkVersion
            $lockHandle = [IO.File]::Open($lockedFile, [IO.FileMode]::Open,
                [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
            $staged = $false
            $stagingFailure = $null

            try {
                try {
                    Invoke-ConfirmedSdkRemovalStaging -Version $script:SdkVersion
                    $staged = $true
                }
                catch {
                    # Windows may reject renaming a directory containing an
                    # exclusively opened file. That is an acceptable failure,
                    # provided the entire original SDK remains intact.
                    $stagingFailure = $_
                }

                $stages = @(Get-ChildItem -LiteralPath $script:SdkRoot -Directory -Force |
                        Where-Object { $_.Name -like ".removing-$($script:SdkVersion)-*" })
                if ($staged) {
                    # Platforms that permit renaming a directory with an open
                    # child file must still stage everything together.
                    Test-Path -LiteralPath $installDirectory | Should -BeFalse
                    $stages.Count | Should -Be 1
                    Test-Path -LiteralPath $record -PathType Leaf | Should -BeTrue
                    $state = Get-PendingRemoval -Version $script:SdkVersion
                    Test-Path -LiteralPath (Join-Path $state.Stage 'dotnet.exe') | Should -BeTrue
                    Test-Path -LiteralPath (Join-Path $state.Stage 'locked-test-file.txt') | Should -BeTrue
                }
                else {
                    $stagingFailure | Should -Not -BeNullOrEmpty
                    # A failed rename must not relocate individual SDK files
                    # or destroy the original installation/recovery identity.
                    Test-Path -LiteralPath $installDirectory | Should -BeTrue
                    Test-Path -LiteralPath (Join-Path $installDirectory 'dotnet.exe') | Should -BeTrue
                    Test-Path -LiteralPath $lockedFile | Should -BeTrue
                    $stages.Count | Should -Be 0
                    Test-Path -LiteralPath $record | Should -BeFalse
                }
            }
            finally {
                $lockHandle.Dispose()
            }

            if ($staged) {
                Complete-PendingRemoval -Version $script:SdkVersion
                Test-Path -LiteralPath $record | Should -BeFalse
                Test-Path -LiteralPath $installDirectory | Should -BeFalse
            }
        }

        It 'retries an incomplete removal after its SDK host was deleted' {
            $installDirectory = Initialize-TestRemovalTarget
            $script:SdkVersion = $script:RemovalVersion
            Set-Item -Path Function:script:Invoke-IsolatedSdkBuildServerShutdown -Value {}
            Set-Item -Path Function:script:Invoke-IsolatedSdkDirectoryRemoval -Value {
                param([string]$InstallDirectory)
                Remove-Item -LiteralPath (Join-Path $InstallDirectory 'dotnet.exe') -Force -ErrorAction Stop
                throw 'simulated locked file'
            }

            { Remove-IsolatedSdk -Yes } | Should -Throw '*incomplete*'
            Test-Path -LiteralPath $installDirectory | Should -BeFalse
            $record = Join-Path (Join-Path $script:SdkRoot '.pending-removals') $script:SdkVersion
            Test-Path -LiteralPath $record -PathType Leaf | Should -BeTrue
            $state = Get-PendingRemoval -Version $script:SdkVersion
            Test-Path -LiteralPath $state.Stage -PathType Container | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $state.Stage 'dotnet.exe') | Should -BeFalse

            Remove-IsolatedSdk -Yes -WhatIf
            Test-Path -LiteralPath $record | Should -BeTrue
            Test-Path -LiteralPath $state.Stage | Should -BeTrue

            # Restore the real removal helper to exercise a second invocation
            # without a host or another build-server shutdown.
            Import-ToolFunctionDefinition
            Set-Item -Path Function:script:Invoke-IsolatedSdkBuildServerShutdown -Value {
                throw 'shutdown must not run during incomplete removal retry'
            }
            Remove-IsolatedSdk -Yes

            Test-Path -LiteralPath $record | Should -BeFalse
            Test-Path -LiteralPath $state.Stage | Should -BeFalse
            Test-Path -LiteralPath $installDirectory | Should -BeFalse
        }

        It 'does not retry against a newly replaced version directory' {
            $installDirectory = Initialize-TestRemovalTarget
            Set-Item -Path Function:script:Invoke-IsolatedSdkBuildServerShutdown -Value {}
            Set-Item -Path Function:script:Invoke-IsolatedSdkDirectoryRemoval -Value {
                param([string]$InstallDirectory)
                Remove-Item -LiteralPath (Join-Path $InstallDirectory 'dotnet.exe') -Force -ErrorAction Stop
                throw 'simulated locked file'
            }
            { Remove-IsolatedSdk -Yes } | Should -Throw '*incomplete*'
            $state = Get-PendingRemoval -Version $script:SdkVersion
            New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
            $sentinel = Join-Path $installDirectory 'preserve.txt'
            Set-Content -LiteralPath $sentinel -Value 'unrelated data'

            { Remove-IsolatedSdk -Yes } | Should -Throw '*replaced*'
            Get-Content -LiteralPath $sentinel | Should -Be 'unrelated data'
            Test-Path -LiteralPath $state.Stage | Should -BeTrue
        }

        It 'propagates deletion failure and does not report success' {
            $installDirectory = Initialize-TestRemovalTarget
            Set-Item -Path Function:script:Confirm-Action -Value {
                param([string]$Prompt)
                $null = $Prompt
                return $true
            }
            Set-Item -Path Function:script:Invoke-IsolatedSdkBuildServerShutdown -Value {
                param([string]$DotNetPath, [string]$SdkVersion)
                $null = $DotNetPath
                $null = $SdkVersion
            }
            Set-Item -Path Function:script:Invoke-IsolatedSdkDirectoryRemoval -Value {
                param([string]$InstallDirectory)
                $null = $InstallDirectory
                throw 'simulated deletion failure'
            }
            $removalInformation = @()

            { Remove-IsolatedSdk -InformationVariable removalInformation } |
                Should -Throw '*simulated deletion failure*'

            Test-Path -LiteralPath $installDirectory | Should -BeFalse
            Test-Path -LiteralPath (Join-Path (Join-Path $script:SdkRoot '.pending-removals') $script:SdkVersion) | Should -BeTrue
            ($removalInformation.MessageData -join [Environment]::NewLine) | Should -Not -Match 'was removed'
        }
    }
}
