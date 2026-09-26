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
        $installDirectory = Join-Path $script:SdkRoot $script:Version
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

Describe 'PowerShell removal process-level behavior' {
    It 'forwards -WhatIf through source bootstrap without changing SDK state' {
        $publicInstallDirectory = Join-Path $script:ToolRoot $script:RemovalVersion
        New-Item -ItemType Directory -Path $publicInstallDirectory -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $publicInstallDirectory 'dotnet.exe') -Force | Out-Null

        $whatIfOutput = @(& pwsh -NoProfile -File $script:ToolScript -Action Remove -Version $script:RemovalVersion -WhatIf *>&1)

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

    It 'fails safely for non-interactive removal without explicit approval' {
        Install-TestTool
        $publicInstallDirectory = Join-Path $script:ToolRoot $script:RemovalVersion
        New-Item -ItemType Directory -Path $publicInstallDirectory -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $publicInstallDirectory 'dotnet.exe') -Force | Out-Null

        & pwsh -NoProfile -NonInteractive -File $script:InstalledToolPath -Action Remove -Version $script:RemovalVersion *> $null

        $LASTEXITCODE | Should -Not -Be 0
        Test-Path -LiteralPath $publicInstallDirectory | Should -BeTrue
    }
}

Describe 'Remove-IsolatedSdk focused behavior' {
    BeforeEach {
        Import-ToolFunctionDefinition
        $script:SdkRoot = Join-Path $script:TestRoot 'function-home'
        $script:Version = $script:RemovalVersion
    }

    It 'exposes native WhatIf and Confirm parameters' {
        $removeCommand = Get-Command Remove-IsolatedSdk -CommandType Function

        $removeCommand.Parameters.ContainsKey('WhatIf') | Should -BeTrue
        $removeCommand.Parameters.ContainsKey('Confirm') | Should -BeTrue
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

        Test-Path -LiteralPath $installDirectory | Should -BeTrue
        ($removalInformation.MessageData -join [Environment]::NewLine) | Should -Not -Match 'was removed'
    }
}
