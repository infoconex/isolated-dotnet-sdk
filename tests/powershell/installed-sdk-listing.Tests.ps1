Describe 'PowerShell installed SDK listing' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:ToolScript = Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1'
        $script:HomeVariableName = if ($IsWindows) { 'USERPROFILE' } else { 'HOME' }

        function Install-TestTool {
            Copy-Item $script:ToolScript $script:SourceCopy -Force
            $bootstrapBin = Join-Path $script:TestRoot 'bootstrap-bin'
            New-Item -ItemType Directory -Path $bootstrapBin -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $bootstrapBin 'dotnet.cmd') -Value "@echo off`r`nexit /b 0`r`n"
            $env:ISOLATED_DOTNET_SDK_SOURCE_COPY = $script:SourceCopy
            $env:ISOLATED_DOTNET_SDK_BOOTSTRAP_BIN = $bootstrapBin

            & pwsh -NoProfile -Command '$env:PATH = "$env:ISOLATED_DOTNET_SDK_BOOTSTRAP_BIN;$env:PATH"; & $env:ISOLATED_DOTNET_SDK_SOURCE_COPY -Action List *> $null'
            $LASTEXITCODE | Should -Be 0
        }

        function Write-SystemDotNetStub {
            param(
                [string]$Directory,
                [string[]]$InventoryLines = @(),
                [int]$ExitCode = 0
            )

            New-Item -ItemType Directory -Path $Directory -Force | Out-Null
            $content = [System.Collections.Generic.List[string]]::new()
            $content.Add('@echo off')
            foreach ($line in $InventoryLines) {
                $content.Add("echo $line")
            }
            $content.Add("exit /b $ExitCode")
            Set-Content -LiteralPath (Join-Path $Directory 'dotnet.cmd') -Value $content
        }
    }

    BeforeEach {
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-installed-list-{0}" -f [guid]::NewGuid())
        $script:TestHome = Join-Path $script:TestRoot 'home'
        $script:ToolRoot = Join-Path $script:TestHome 'dotnet-sdks'
        $script:ToolPath = Join-Path $script:ToolRoot 'isolated-dotnet-sdk.ps1'
        $script:SourceCopy = Join-Path $script:TestRoot 'isolated-dotnet-sdk-source.ps1'
        $script:OriginalHomeValue = [Environment]::GetEnvironmentVariable($script:HomeVariableName, 'Process')

        New-Item -ItemType Directory -Path $script:TestHome -Force | Out-Null
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:TestHome, 'Process')
    }

    AfterEach {
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:OriginalHomeValue, 'Process')
        Remove-Item Env:ISOLATED_DOTNET_SDK_SOURCE_COPY -ErrorAction SilentlyContinue
        Remove-Item Env:ISOLATED_DOTNET_SDK_BOOTSTRAP_BIN -ErrorAction SilentlyContinue
        Remove-Item Env:ISOLATED_DOTNET_SDK_TOOL_PATH -ErrorAction SilentlyContinue
        Remove-Item Env:ISOLATED_DOTNET_SDK_SYSTEM_BIN -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'shows isolated SDKs before system SDKs and preserves same-version overlap' {
        Install-TestTool
        foreach ($version in @('11.0.100-rc.1.26425.128', '10.0.401')) {
            $installDir = Join-Path $script:ToolRoot $version
            New-Item -ItemType Directory -Path $installDir -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $installDir 'dotnet.exe') -Force | Out-Null
        }

        $fakeBin = Join-Path $script:TestRoot 'system-bin'
        Write-SystemDotNetStub `
            -Directory $fakeBin `
            -InventoryLines @(
                '10.0.401 [C:\Program Files\dotnet\sdk]',
                '9.0.318 [D:\dotnet sdk]'
            )
        $env:ISOLATED_DOTNET_SDK_TOOL_PATH = $script:ToolPath
        $env:ISOLATED_DOTNET_SDK_SYSTEM_BIN = $fakeBin

        $listOutput = @(& pwsh -NoProfile -Command '$env:PATH = "$env:ISOLATED_DOTNET_SDK_SYSTEM_BIN;$env:PATH"; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action List 2>&1')
        $text = $listOutput -join [Environment]::NewLine

        $LASTEXITCODE | Should -Be 0
        $text | Should -Match 'Installed \.NET SDKs'
        $text | Should -Match '(?m)^Isolated SDKs:$'
        $text | Should -Match '(?m)^System SDKs:$'
        $text | Should -Match ([regex]::Escape("11.0.100-rc.1.26425.128  $(Join-Path $script:ToolRoot '11.0.100-rc.1.26425.128')"))
        $text | Should -Match ([regex]::Escape("10.0.401  $(Join-Path $script:ToolRoot '10.0.401')"))
        $text | Should -Match '10\.0\.401  C:\\Program Files\\dotnet\\sdk'
        $text | Should -Match '9\.0\.318  D:\\dotnet sdk'
        ([regex]::Matches($text, '10\.0\.401')).Count | Should -Be 2
        $text.IndexOf('Isolated SDKs:') | Should -BeLessThan $text.IndexOf('System SDKs:')
    }

    It 'shows None for both empty ownership groups' {
        Install-TestTool
        $fakeBin = Join-Path $script:TestRoot 'empty-system-bin'
        Write-SystemDotNetStub -Directory $fakeBin
        $env:ISOLATED_DOTNET_SDK_TOOL_PATH = $script:ToolPath
        $env:ISOLATED_DOTNET_SDK_SYSTEM_BIN = $fakeBin

        $listOutput = @(& pwsh -NoProfile -Command '$env:PATH = "$env:ISOLATED_DOTNET_SDK_SYSTEM_BIN;$env:PATH"; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action List 2>&1')
        $text = $listOutput -join [Environment]::NewLine

        $LASTEXITCODE | Should -Be 0
        $text | Should -Match '(?m)^Isolated SDKs:$'
        $text | Should -Match '(?m)^System SDKs:$'
        ([regex]::Matches($text, '(?m)^  None$')).Count | Should -Be 2
    }

    It 'treats an unavailable system dotnet host as an empty System SDKs group' {
        Install-TestTool
        $emptyBin = Join-Path $script:TestRoot 'no-dotnet-bin'
        New-Item -ItemType Directory -Path $emptyBin -Force | Out-Null
        $env:ISOLATED_DOTNET_SDK_TOOL_PATH = $script:ToolPath
        $env:ISOLATED_DOTNET_SDK_SYSTEM_BIN = $emptyBin

        $listOutput = @(& pwsh -NoProfile -Command '$env:PATH = $env:ISOLATED_DOTNET_SDK_SYSTEM_BIN; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action List 2>&1')
        $text = $listOutput -join [Environment]::NewLine

        $LASTEXITCODE | Should -Be 0
        $text | Should -Match '(?ms)^System SDKs:\r?\n  None'
    }

    It 'fails when the resolved system dotnet inventory exits nonzero' {
        Install-TestTool
        $fakeBin = Join-Path $script:TestRoot 'failing-system-bin'
        Write-SystemDotNetStub -Directory $fakeBin -ExitCode 71
        $env:ISOLATED_DOTNET_SDK_TOOL_PATH = $script:ToolPath
        $env:ISOLATED_DOTNET_SDK_SYSTEM_BIN = $fakeBin

        $listOutput = @(& pwsh -NoProfile -Command '$env:PATH = "$env:ISOLATED_DOTNET_SDK_SYSTEM_BIN;$env:PATH"; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action List 2>&1')
        $text = $listOutput -join [Environment]::NewLine

        $LASTEXITCODE | Should -Not -Be 0
        $text | Should -Match 'Unable to list SDKs through the system dotnet host with exit code 71\.'
        $text | Should -Not -Match '(?m)^System SDKs:$'
    }

    It 'does not make a system-only SDK removable' {
        Install-TestTool
        $fakeBin = Join-Path $script:TestRoot 'system-only-bin'
        Write-SystemDotNetStub -Directory $fakeBin -InventoryLines @('10.0.401 [C:\Program Files\dotnet\sdk]')
        $env:ISOLATED_DOTNET_SDK_TOOL_PATH = $script:ToolPath
        $env:ISOLATED_DOTNET_SDK_SYSTEM_BIN = $fakeBin

        $removeOutput = @(& pwsh -NoProfile -Command '$env:PATH = "$env:ISOLATED_DOTNET_SDK_SYSTEM_BIN;$env:PATH"; & $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Remove -Version 10.0.401 -Yes 2>&1')
        $text = $removeOutput -join [Environment]::NewLine

        $LASTEXITCODE | Should -Not -Be 0
        $text | Should -Match 'Isolated SDK 10\.0\.401 was not found'
        Test-Path -LiteralPath (Join-Path $fakeBin 'dotnet.cmd') | Should -BeTrue
    }
}
