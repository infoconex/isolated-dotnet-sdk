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
        # Only the shutdown function is imported from the product script. Its
        # warning helper must also exist when exercising the legacy fallback.
        Set-Item -Path Function:script:Write-ToolWarning -Value {
            param([string]$Message)
            Write-Warning $Message
        }
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

    It 'isolates historical shutdown from ambient SDK discovery and restores caller state' {
        $sdkDirectory = Join-Path $TestDrive '2.2.207'
        $ambientDirectory = Join-Path $TestDrive 'ambient'
        $fakeDotNet = Join-Path $sdkDirectory 'dotnet.cmd'
        $workDirectoryMarker = Join-Path $TestDrive 'shutdown-workdir.txt'
        New-Item -ItemType Directory -Path $sdkDirectory, $ambientDirectory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $ambientDirectory 'global.json') -Value '{"sdk":{"version":"0.0.0"}}'
        Set-Content -LiteralPath $fakeDotNet -Value (@(
                '@echo off'
                'if /I not "%1"=="build-server" exit /b 81'
                'if /I not "%2"=="shutdown" exit /b 82'
                'if /I not "%DOTNET_ROOT%"=="%EXPECTED_ISOLATED_ROOT%" exit /b 83'
                'if not "%DOTNET_MULTILEVEL_LOOKUP%"=="0" exit /b 84'
                'if not "%DOTNET_SKIP_FIRST_TIME_EXPERIENCE%"=="1" exit /b 85'
                'if not "%DOTNET_CLI_TELEMETRY_OPTOUT%"=="1" exit /b 86'
                'if /I not "%DOTNET_CLI_HOME%"=="%CD%" exit /b 87'
                'if exist global.json exit /b 88'
                'echo %CD%>"%SDK_TEST_SHUTDOWN_WORK_DIR_MARKER%"'
                'exit /b 0'
            ) -join "`r`n")

        $settings = @{
            DOTNET_ROOT                       = 'wrong-root'
            DOTNET_MULTILEVEL_LOOKUP          = '1'
            DOTNET_CLI_HOME                   = 'wrong-home'
            DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '0'
            DOTNET_CLI_TELEMETRY_OPTOUT       = '0'
            EXPECTED_ISOLATED_ROOT            = $sdkDirectory
            SDK_TEST_SHUTDOWN_WORK_DIR_MARKER = $workDirectoryMarker
        }
        $original = @{}
        $originalLocation = (Get-Location).Path
        foreach ($name in $settings.Keys) {
            $original[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        }
        try {
            foreach ($name in $settings.Keys) {
                [Environment]::SetEnvironmentVariable($name, $settings[$name], 'Process')
            }
            Push-Location -LiteralPath $ambientDirectory
            try {
                Invoke-IsolatedSdkBuildServerShutdown -DotNetPath $fakeDotNet -SdkVersion '2.2.207'
                (Get-Location).Path | Should -Be $ambientDirectory
                foreach ($name in $settings.Keys) {
                    [Environment]::GetEnvironmentVariable($name, 'Process') |
                        Should -Be $settings[$name]
                }
                Test-Path -LiteralPath $workDirectoryMarker | Should -BeTrue
                $shutdownDirectory = (Get-Content -LiteralPath $workDirectoryMarker -Raw).Trim()
                $shutdownDirectory | Should -Not -Be $ambientDirectory
                Test-Path -LiteralPath $shutdownDirectory | Should -BeFalse
            }
            finally {
                Pop-Location
            }
            (Get-Location).Path | Should -Be $originalLocation
        }
        finally {
            foreach ($name in $settings.Keys) {
                [Environment]::SetEnvironmentVariable($name, $original[$name], 'Process')
            }
        }
    }

    It 'automatically classifies proven historical unsupported shutdown without extra authorization' {
        foreach ($version in @('1.0.4', '1.1.5', '1.1.14', '2.0.3')) {
            $root = Join-Path $TestDrive $version
            $hostPath = Join-Path $root 'dotnet.cmd'
            New-Item -ItemType Directory -Path (Join-Path $root "sdk/$version") -Force | Out-Null
            Set-Content -LiteralPath $hostPath -Value (@(
                    '@echo off'
                    'if /I "%1 %2"=="build-server --help" ('
                    '  echo No executable found matching command "dotnet-build-server"'
                    '  exit /b 1'
                    ')'
                    'if /I "%1 %2"=="buildserver --help" ('
                    '  echo No executable found matching command "dotnet-buildserver"'
                    '  exit /b 1'
                    ')'
                    'exit /b 72'
                ) -join "`r`n")

            { Invoke-IsolatedSdkBuildServerShutdown -DotNetPath $hostPath -SdkVersion $version } |
                Should -Not -Throw

            { Invoke-IsolatedSdkBuildServerShutdown -DotNetPath $hostPath -SdkVersion $version -AllowUnsupportedShutdown } |
                Should -Not -Throw
            Test-Path -LiteralPath $root -PathType Container | Should -BeTrue
        }
    }

    It 'requires successful SDK-local Roslyn shutdown for 2.1.105' {
        $version = '2.1.105'
        $root = Join-Path $TestDrive $version
        $hostPath = Join-Path $root 'dotnet.cmd'
        $compilerPath = Join-Path $root "sdk/$version/Roslyn/bincore/VBCSCompiler.dll"
        $marker = Join-Path $TestDrive 'roslyn-shutdown-marker.txt'
        New-Item -ItemType Directory -Path (Split-Path $compilerPath -Parent) -Force | Out-Null
        Set-Content -LiteralPath $compilerPath -Value 'fake-compiler'
        $helpLines = @(
            '@echo off'
            'if /I "%1 %2"=="build-server --help" ('
            '  echo No executable found matching command "dotnet-build-server"'
            '  exit /b 1'
            ')'
            'if /I "%1 %2"=="buildserver --help" ('
            '  echo No executable found matching command "dotnet-buildserver"'
            '  exit /b 1'
            ')'
        )

        $previousMarker = [Environment]::GetEnvironmentVariable('SDK_TEST_ROSLYN_MARKER', 'Process')
        try {
            $env:SDK_TEST_ROSLYN_MARKER = $marker
            # Make the native process return a failure unconditionally for the
            # Roslyn command. First assert the fixture itself really exits 77.
            $failLines = $helpLines + @(
                'if /I "%1"=="exec" exit /b 77'
                'exit /b 88'
            )
            Set-Content -LiteralPath $hostPath -Value ($failLines -join "`r`n")
            $null = & $hostPath exec $compilerPath -shutdown
            $LASTEXITCODE | Should -Be 77

            { Invoke-IsolatedSdkBuildServerShutdown -DotNetPath $hostPath -SdkVersion $version -AllowUnsupportedShutdown } |
                Should -Throw '*exit code 77*'
            Test-Path -LiteralPath $marker | Should -BeFalse

            # The same SDK-local operation succeeds with the successful host.
            $successLines = $helpLines + @(
                'if /I "%1"=="exec" ('
                '  if not exist "%~2" exit /b 89'
                '  echo success>"%SDK_TEST_ROSLYN_MARKER%"'
                '  exit /b 0'
                ')'
                'exit /b 88'
            )
            Set-Content -LiteralPath $hostPath -Value ($successLines -join "`r`n")
            Invoke-IsolatedSdkBuildServerShutdown -DotNetPath $hostPath -SdkVersion $version -AllowUnsupportedShutdown
            Test-Path -LiteralPath $marker | Should -BeTrue
            Test-Path -LiteralPath $root -PathType Container | Should -BeTrue
        }
        finally {
            [Environment]::SetEnvironmentVariable('SDK_TEST_ROSLYN_MARKER', $previousMarker, 'Process')
        }
    }

    It 'does not ignore ambiguous capability probes or supported shutdown failures' {
        $version = '1.0.4'
        $root = Join-Path $TestDrive $version
        $hostPath = Join-Path $root 'dotnet.cmd'
        New-Item -ItemType Directory -Path (Join-Path $root "sdk/$version") -Force | Out-Null
        Set-Content -LiteralPath $hostPath -Value (@(
                '@echo off'
                'if "%2"=="--help" ('
                '  echo Unexpected host startup failure'
                '  exit /b 1'
                ')'
                'exit /b 77'
            ) -join "`r`n")
        { Invoke-IsolatedSdkBuildServerShutdown -DotNetPath $hostPath -SdkVersion $version -AllowUnsupportedShutdown } |
            Should -Throw '*probe failed unexpectedly*'

        Set-Content -LiteralPath $hostPath -Value (@(
                '@echo off'
                'if /I "%1 %2"=="build-server --help" exit /b 0'
                'if /I "%1 %2"=="build-server shutdown" exit /b 78'
                'exit /b 79'
            ) -join "`r`n")
        { Invoke-IsolatedSdkBuildServerShutdown -DotNetPath $hostPath -SdkVersion $version -AllowUnsupportedShutdown } |
            Should -Throw '*exit code 78*'
        Test-Path -LiteralPath $root -PathType Container | Should -BeTrue
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

        $warningIndex | Should -BeGreaterThan 3
        # Before a supported clear, interactive Remove already emitted the separator;
        # exact-version/direct Remove retains it immediately before the warning.
        $lines[$warningIndex - 3].Trim() | Should -Be 'if (-not $SelectedInteractively) {'
        $lines[$warningIndex - 2].Trim() | Should -Be 'Write-ToolDisplay'
        $lines[$warningIndex - 1].Trim() | Should -Be '}'
        $lines[$warningIndex + 1].Trim() | Should -Be 'Write-ToolDisplay'
    }
}
