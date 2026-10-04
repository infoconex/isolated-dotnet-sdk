Describe 'PowerShell removal presentation' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:ToolScript = Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1'

        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:ToolScript,
            [ref]$tokens,
            [ref]$errors)
        if ($errors.Count -gt 0) {
            throw "Unable to parse product script: $($errors[0].Message)"
        }

        $functionDefinition = $ast.FindAll(
            {
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                    $node.Name -eq 'Invoke-IsolatedSdkBuildServerShutdown'
            },
            $true) | Select-Object -First 1

        $bodyText = $functionDefinition.Body.Extent.Text
        $bodyText = $bodyText.Substring(1, $bodyText.Length - 2)
        Set-Item `
            -Path Function:script:Invoke-IsolatedSdkBuildServerShutdown `
            -Value ([scriptblock]::Create($bodyText))
    }

    It 'suppresses successful child shutdown chatter and scopes first-run controls' {
        $fakeDotNet = Join-Path $TestDrive 'dotnet.cmd'
        Set-Content -LiteralPath $fakeDotNet -Value (@(
                '@echo off'
                'if /I not "%DOTNET_NOLOGO%"=="true" exit /b 81'
                'if /I not "%DOTNET_GENERATE_ASPNET_CERTIFICATE%"=="false" exit /b 82'
                'if /I not "%DOTNET_ADD_GLOBAL_TOOLS_TO_PATH%"=="false" exit /b 83'
                'echo child shutdown chatter'
                'exit /b 0'
            ) -join "`r`n")

        $originalNoLogo = [Environment]::GetEnvironmentVariable('DOTNET_NOLOGO', 'Process')
        $originalCertificate = [Environment]::GetEnvironmentVariable('DOTNET_GENERATE_ASPNET_CERTIFICATE', 'Process')
        $originalToolsPath = [Environment]::GetEnvironmentVariable('DOTNET_ADD_GLOBAL_TOOLS_TO_PATH', 'Process')

        try {
            $env:DOTNET_NOLOGO = 'parent-logo'
            $env:DOTNET_GENERATE_ASPNET_CERTIFICATE = 'parent-certificate'
            $env:DOTNET_ADD_GLOBAL_TOOLS_TO_PATH = 'parent-tools'

            $output = @(Invoke-IsolatedSdkBuildServerShutdown `
                    -DotNetPath $fakeDotNet `
                    -SdkVersion '99.0.100' 2>&1)

            ($output -join [Environment]::NewLine) | Should -Not -Match 'child shutdown chatter'
            $env:DOTNET_NOLOGO | Should -Be 'parent-logo'
            $env:DOTNET_GENERATE_ASPNET_CERTIFICATE | Should -Be 'parent-certificate'
            $env:DOTNET_ADD_GLOBAL_TOOLS_TO_PATH | Should -Be 'parent-tools'
        }
        finally {
            [Environment]::SetEnvironmentVariable('DOTNET_NOLOGO', $originalNoLogo, 'Process')
            [Environment]::SetEnvironmentVariable('DOTNET_GENERATE_ASPNET_CERTIFICATE', $originalCertificate, 'Process')
            [Environment]::SetEnvironmentVariable('DOTNET_ADD_GLOBAL_TOOLS_TO_PATH', $originalToolsPath, 'Process')
        }
    }

    It 'places blank display boundaries around the destructive warning' {
        $lines = @(Get-Content -LiteralPath $script:ToolScript)
        $warningIndex = -1
        for ($index = 0; $index -lt $lines.Count; $index++) {
            if ($lines[$index] -like '*Write-ToolWarning "Isolated SDK $SdkVersion will be removed from $InstallDir"*') {
                $warningIndex = $index
                break
            }
        }

        $warningIndex | Should -BeGreaterThan 0
        $lines[$warningIndex - 1].Trim() | Should -Be 'Write-ToolDisplay'
        $lines[$warningIndex + 1].Trim() | Should -Be 'Write-ToolDisplay'
    }
}
