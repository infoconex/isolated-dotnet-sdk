Describe 'PowerShell bootstrap filesystem behavior' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:ToolScript = Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1'
        $script:HomeVariableName = if ($IsWindows) { 'USERPROFILE' } else { 'HOME' }

        function Import-ToolFunctionDefinition {
            param([string]$FunctionName)

            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:ToolScript,
                [ref]$tokens,
                [ref]$errors)

            if ($errors.Count -gt 0) {
                throw "Unable to parse product script for bootstrap tests: $($errors[0].Message)"
            }

            $functionDefinition = $ast.Find(
                {
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                        $node.Name -eq $FunctionName
                },
                $true)

            if ($null -eq $functionDefinition) {
                throw "Unable to find function $FunctionName in product script."
            }

            $bodyText = $functionDefinition.Body.Extent.Text
            $bodyText = $bodyText.Substring(1, $bodyText.Length - 2)
            Set-Item -Path "Function:script:$FunctionName" -Value ([scriptblock]::Create($bodyText))
        }
    }

    BeforeEach {
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-bootstrap-tests-{0}" -f [guid]::NewGuid())
        $script:TestHome = Join-Path $script:TestRoot 'home'
        $script:ToolRoot = Join-Path $script:TestHome 'dotnet-sdks'
        $script:ToolPath = Join-Path $script:ToolRoot 'isolated-dotnet-sdk.ps1'
        $script:SourceCopy = Join-Path $script:TestRoot 'isolated-dotnet-sdk-source.ps1'
        $script:OriginalHomeValue = [Environment]::GetEnvironmentVariable($script:HomeVariableName, 'Process')

        New-Item -ItemType Directory -Path $script:TestHome -Force | Out-Null
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:TestHome, 'Process')

        Copy-Item $script:ToolScript $script:SourceCopy -Force
        Add-Content -Path $script:SourceCopy -Value "`n# bootstrap-source-marker"
    }

    AfterEach {
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:OriginalHomeValue, 'Process')
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'fails a tool-path directory conflict without mutating the conflicting destination' {
        New-Item -ItemType Directory -Path $script:ToolPath -Force | Out-Null

        $output = @(& pwsh -NoProfile -File $script:SourceCopy -Action List 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        ($output -join [Environment]::NewLine) | Should -Not -Match 'Tool installed\.'
        Test-Path -LiteralPath $script:ToolPath -PathType Container | Should -BeTrue
        @(Get-ChildItem -LiteralPath $script:ToolPath -Force) | Should -HaveCount 0
    }

    It 'successful bootstrap removes its staging artifact' {
        & pwsh -NoProfile -File $script:SourceCopy -Action List *> $null

        $LASTEXITCODE | Should -Be 0
        Select-String -Path $script:ToolPath -Pattern '# bootstrap-source-marker' -SimpleMatch -Quiet |
            Should -BeTrue
        @(Get-ChildItem -LiteralPath $script:ToolRoot -Force -File -Filter '.isolated-dotnet-sdk.ps1.*.tmp') |
            Should -HaveCount 0
    }

    It 'staging failure preserves the saved tool and cleans its candidate' {
        Import-ToolFunctionDefinition -FunctionName 'Install-ToolIfNeeded'
        $script:SdkRoot = Join-Path $script:TestRoot 'focused-root'
        $script:ToolName = 'isolated-dotnet-sdk.ps1'
        $script:ToolPath = Join-Path $script:SdkRoot $script:ToolName
        $script:RepositoryRawBase = 'https://example.invalid'
        $script:ActionWasSpecified = $false
        $script:VersionWasSpecified = $false
        $script:ConfirmWasSpecified = $false
        $script:WhatIfWasSpecified = $false
        $script:Bootstrapped = $false
        New-Item -ItemType Directory -Path $script:SdkRoot -Force | Out-Null
        Set-Content -LiteralPath $script:ToolPath -Value '# existing saved tool'

        Set-Item -Path Function:script:Write-ToolInfo -Value { param([string]$Message) $null = $Message }
        Set-Item -Path Function:script:Write-ToolSuccess -Value { param([string]$Message) throw "unexpected success: $Message" }
        Set-Item -Path Function:script:Invoke-WebRequest -Value {
            param([string]$Uri, [string]$OutFile)
            $null = $Uri
            Set-Content -LiteralPath $OutFile -Value 'partial candidate'
            throw 'simulated staging failure'
        }

        { Install-ToolIfNeeded } | Should -Throw '*simulated staging failure*'
        (Get-Content -LiteralPath $script:ToolPath -Raw).Trim() | Should -Be '# existing saved tool'
        @(Get-ChildItem -LiteralPath $script:SdkRoot -Force -File -Filter '.isolated-dotnet-sdk.ps1.*.tmp') |
            Should -HaveCount 0
    }
}
