Describe 'PowerShell transactional SDK installation' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:ToolScript = Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1'
        $script:HomeVariableName = if ($IsWindows) { 'USERPROFILE' } else { 'HOME' }
        $script:FakeHostProjectRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-fake-host-{0}" -f [guid]::NewGuid())
        $script:FakeHostOutput = Join-Path $script:FakeHostProjectRoot 'out'
        New-Item -ItemType Directory -Path $script:FakeHostProjectRoot -Force | Out-Null

        Set-Content -LiteralPath (Join-Path $script:FakeHostProjectRoot 'FakeDotNet.csproj') -Value @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
    <AssemblyName>dotnet</AssemblyName>
    <ImplicitUsings>disable</ImplicitUsings>
    <Nullable>disable</Nullable>
  </PropertyGroup>
</Project>
'@

        Set-Content -LiteralPath (Join-Path $script:FakeHostProjectRoot 'Program.cs') -Value @'
using System;
using System.IO;

public static class Program
{
    public static int Main(string[] args)
    {
        var exitText = Environment.GetEnvironmentVariable("FAKE_DOTNET_EXIT_CODE");
        if (!string.IsNullOrWhiteSpace(exitText) && int.TryParse(exitText, out var exitCode) && exitCode != 0)
        {
            return exitCode;
        }

        if (args.Length > 0 && args[0] == "--list-sdks")
        {
            var conflictPath = Environment.GetEnvironmentVariable("FAKE_DOTNET_CREATE_CONFLICT");
            if (!string.IsNullOrWhiteSpace(conflictPath))
            {
                Directory.CreateDirectory(conflictPath);
                File.WriteAllText(Path.Combine(conflictPath, "sentinel.txt"), "preserve-conflict");
            }

            var version = Environment.GetEnvironmentVariable("FAKE_DOTNET_SDK_VERSION") ?? "99.0.100";
            Console.WriteLine(version + " [C:\\fake]");
        }

        return 0;
    }
}
'@

        & dotnet build `
            (Join-Path $script:FakeHostProjectRoot 'FakeDotNet.csproj') `
            -c Release `
            -o $script:FakeHostOutput `
            --nologo `
            --verbosity quiet
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to build the deterministic fake dotnet host. Exit code: $LASTEXITCODE"
        }
    }

    AfterAll {
        Remove-Item -LiteralPath $script:FakeHostProjectRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-transaction-tests-{0}" -f [guid]::NewGuid())
        $script:TestHome = Join-Path $script:TestRoot 'home'
        $script:ToolRoot = Join-Path $script:TestHome 'dotnet-sdks'
        $script:ToolPath = Join-Path $script:ToolRoot 'isolated-dotnet-sdk.ps1'
        $script:Version = '99.0.100'
        $script:InstallDir = Join-Path $script:ToolRoot $script:Version
        $script:OriginalHomeValue = [Environment]::GetEnvironmentVariable($script:HomeVariableName, 'Process')
        $script:InstallerPath = Join-Path $script:TestRoot 'fake-installer.ps1'
        $script:InstallerTargetPath = Join-Path $script:TestHome 'installer-target.txt'
        $script:DownloadTargetPath = Join-Path $script:TestHome 'download-target.txt'

        New-Item -ItemType Directory -Path $script:ToolRoot -Force | Out-Null
        Copy-Item -LiteralPath $script:ToolScript -Destination $script:ToolPath -Force
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:TestHome, 'Process')
        $env:ISOLATED_DOTNET_SDK_TOOL_PATH = $script:ToolPath
        $env:ISOLATED_DOTNET_SDK_FAKE_INSTALLER = $script:InstallerPath
        $env:ISOLATED_DOTNET_SDK_FAKE_HOST_ROOT = $script:FakeHostOutput
        $env:ISOLATED_DOTNET_SDK_INSTALLER_TARGET = $script:InstallerTargetPath
        $env:ISOLATED_DOTNET_SDK_DOWNLOAD_TARGET = $script:DownloadTargetPath
        $env:FAKE_DOTNET_SDK_VERSION = $script:Version
        Remove-Item Env:FAKE_DOTNET_EXIT_CODE -ErrorAction SilentlyContinue
        Remove-Item Env:FAKE_DOTNET_CREATE_CONFLICT -ErrorAction SilentlyContinue
    }

    AfterEach {
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:OriginalHomeValue, 'Process')
        Remove-Item Env:ISOLATED_DOTNET_SDK_TOOL_PATH -ErrorAction SilentlyContinue
        Remove-Item Env:ISOLATED_DOTNET_SDK_FAKE_INSTALLER -ErrorAction SilentlyContinue
        Remove-Item Env:ISOLATED_DOTNET_SDK_FAKE_HOST_ROOT -ErrorAction SilentlyContinue
        Remove-Item Env:ISOLATED_DOTNET_SDK_INSTALLER_TARGET -ErrorAction SilentlyContinue
        Remove-Item Env:ISOLATED_DOTNET_SDK_DOWNLOAD_TARGET -ErrorAction SilentlyContinue
        Remove-Item Env:FAKE_DOTNET_SDK_VERSION -ErrorAction SilentlyContinue
        Remove-Item Env:FAKE_DOTNET_EXIT_CODE -ErrorAction SilentlyContinue
        Remove-Item Env:FAKE_DOTNET_CREATE_CONFLICT -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'uses operation-scoped install-helper state on download failure' {
        $stableHelper = Join-Path $script:ToolRoot 'dotnet-install.ps1'
        Set-Content -LiteralPath $stableHelper -Value 'preserve-stable-helper'

        $failureOutput = @(& pwsh -NoProfile -Command '
function Invoke-WebRequest {
    param($Uri, $OutFile)
    Set-Content -LiteralPath $env:ISOLATED_DOTNET_SDK_DOWNLOAD_TARGET -Value $OutFile
    Set-Content -LiteralPath $OutFile -Value "partial-download"
    throw "download-failed"
}
& $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -Version 99.0.100 -Yes
' 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        (Get-Content -LiteralPath $stableHelper -Raw).Trim() | Should -Be 'preserve-stable-helper'
        $downloadTarget = (Get-Content -LiteralPath $script:DownloadTargetPath -Raw).Trim()
        $downloadTarget | Should -Not -Be $stableHelper
        $downloadTarget | Should -Match ([regex]::Escape($script:ToolRoot) + '[\\/]dotnet-install\.[^\\/]+\.ps1$')
        Test-Path -LiteralPath $downloadTarget | Should -BeFalse
        ($failureOutput -join [Environment]::NewLine) | Should -Match 'download-failed'
    }

    It 'preserves a pre-existing non-valid destination and fails before download' {
        New-Item -ItemType Directory -Path $script:InstallDir -Force | Out-Null
        $sentinel = Join-Path $script:InstallDir 'sentinel.txt'
        Set-Content -LiteralPath $sentinel -Value 'preserve-me'

        $failureOutput = @(& pwsh -NoProfile -Command '
function Invoke-WebRequest { throw "continued-to-download" }
& $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -Version 99.0.100 -Yes
' 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        ($failureOutput -join [Environment]::NewLine) | Should -Match 'destination already exists'
        ($failureOutput -join [Environment]::NewLine) | Should -Not -Match 'continued-to-download'
        (Get-Content -LiteralPath $sentinel -Raw).Trim() | Should -Be 'preserve-me'
    }

    It 'uses staging for installer failure and cleans the failed attempt' {
        Set-Content -LiteralPath $script:InstallerPath -Value @'
param([string]$Version, [string]$InstallDir, [switch]$NoPath)
Set-Content -LiteralPath $env:ISOLATED_DOTNET_SDK_INSTALLER_TARGET -Value $InstallDir
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Set-Content -LiteralPath (Join-Path $InstallDir 'partial.txt') -Value 'partial'
exit 73
'@

        $failureOutput = @(& pwsh -NoProfile -Command '
function Invoke-WebRequest { param($Uri, $OutFile) Copy-Item -LiteralPath $env:ISOLATED_DOTNET_SDK_FAKE_INSTALLER -Destination $OutFile -Force }
& $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -Version 99.0.100 -Yes
' 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        ($failureOutput -join [Environment]::NewLine) | Should -Match 'dotnet-install failed for SDK 99\.0\.100 with exit code 73\.'
        $target = (Get-Content -LiteralPath $script:InstallerTargetPath -Raw).Trim()
        $target | Should -Not -Be $script:InstallDir
        $target | Should -Match ([regex]::Escape($script:ToolRoot) + '[\\/]\.install-99\.0\.100-[^\\/]+$')
        Test-Path -LiteralPath $target | Should -BeFalse
        Test-Path -LiteralPath $script:InstallDir | Should -BeFalse
    }

    It 'cleans staging when the installer does not produce a host' {
        Set-Content -LiteralPath $script:InstallerPath -Value @'
param([string]$Version, [string]$InstallDir, [switch]$NoPath)
Set-Content -LiteralPath $env:ISOLATED_DOTNET_SDK_INSTALLER_TARGET -Value $InstallDir
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
exit 0
'@

        $failureOutput = @(& pwsh -NoProfile -Command '
function Invoke-WebRequest { param($Uri, $OutFile) Copy-Item -LiteralPath $env:ISOLATED_DOTNET_SDK_FAKE_INSTALLER -Destination $OutFile -Force }
& $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -Version 99.0.100 -Yes
' 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        ($failureOutput -join [Environment]::NewLine) | Should -Match 'isolated dotnet executable was not found'
        $target = (Get-Content -LiteralPath $script:InstallerTargetPath -Raw).Trim()
        Test-Path -LiteralPath $target | Should -BeFalse
        Test-Path -LiteralPath $script:InstallDir | Should -BeFalse
    }

    It 'blocks promotion when the staged host exits nonzero' {
        $env:FAKE_DOTNET_EXIT_CODE = '74'
        Set-Content -LiteralPath $script:InstallerPath -Value @'
param([string]$Version, [string]$InstallDir, [switch]$NoPath)
Set-Content -LiteralPath $env:ISOLATED_DOTNET_SDK_INSTALLER_TARGET -Value $InstallDir
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Copy-Item -Path (Join-Path $env:ISOLATED_DOTNET_SDK_FAKE_HOST_ROOT '*') -Destination $InstallDir -Recurse -Force
exit 0
'@

        $failureOutput = @(& pwsh -NoProfile -Command '
function Invoke-WebRequest { param($Uri, $OutFile) Copy-Item -LiteralPath $env:ISOLATED_DOTNET_SDK_FAKE_INSTALLER -Destination $OutFile -Force }
& $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -Version 99.0.100 -Yes
' 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        ($failureOutput -join [Environment]::NewLine) | Should -Match 'Unable to verify isolated SDK 99\.0\.100 with exit code 74\.'
        $target = (Get-Content -LiteralPath $script:InstallerTargetPath -Raw).Trim()
        Test-Path -LiteralPath $target | Should -BeFalse
        Test-Path -LiteralPath $script:InstallDir | Should -BeFalse
    }

    It 'blocks promotion when staged inventory omits the requested version' {
        $env:FAKE_DOTNET_SDK_VERSION = '98.0.100'
        Set-Content -LiteralPath $script:InstallerPath -Value @'
param([string]$Version, [string]$InstallDir, [switch]$NoPath)
Set-Content -LiteralPath $env:ISOLATED_DOTNET_SDK_INSTALLER_TARGET -Value $InstallDir
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Copy-Item -Path (Join-Path $env:ISOLATED_DOTNET_SDK_FAKE_HOST_ROOT '*') -Destination $InstallDir -Recurse -Force
exit 0
'@

        $failureOutput = @(& pwsh -NoProfile -Command '
function Invoke-WebRequest { param($Uri, $OutFile) Copy-Item -LiteralPath $env:ISOLATED_DOTNET_SDK_FAKE_INSTALLER -Destination $OutFile -Force }
& $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -Version 99.0.100 -Yes
' 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        ($failureOutput -join [Environment]::NewLine) | Should -Match 'SDK 99\.0\.100 was not found after installation\.'
        $target = (Get-Content -LiteralPath $script:InstallerTargetPath -Raw).Trim()
        Test-Path -LiteralPath $target | Should -BeFalse
        Test-Path -LiteralPath $script:InstallDir | Should -BeFalse
    }

    It 'preserves a destination that appears before promotion' {
        $env:FAKE_DOTNET_CREATE_CONFLICT = $script:InstallDir
        Set-Content -LiteralPath $script:InstallerPath -Value @'
param([string]$Version, [string]$InstallDir, [switch]$NoPath)
Set-Content -LiteralPath $env:ISOLATED_DOTNET_SDK_INSTALLER_TARGET -Value $InstallDir
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Copy-Item -Path (Join-Path $env:ISOLATED_DOTNET_SDK_FAKE_HOST_ROOT '*') -Destination $InstallDir -Recurse -Force
exit 0
'@

        $failureOutput = @(& pwsh -NoProfile -Command '
function Invoke-WebRequest { param($Uri, $OutFile) Copy-Item -LiteralPath $env:ISOLATED_DOTNET_SDK_FAKE_INSTALLER -Destination $OutFile -Force }
& $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -Version 99.0.100 -Yes
' 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        ($failureOutput -join [Environment]::NewLine) | Should -Match 'destination already exists'
        (Get-Content -LiteralPath (Join-Path $script:InstallDir 'sentinel.txt') -Raw).Trim() | Should -Be 'preserve-conflict'
        $target = (Get-Content -LiteralPath $script:InstallerTargetPath -Raw).Trim()
        Test-Path -LiteralPath $target | Should -BeFalse
    }

    It 'promotes only a verified staged installation' {
        Set-Content -LiteralPath $script:InstallerPath -Value @'
param([string]$Version, [string]$InstallDir, [switch]$NoPath)
Set-Content -LiteralPath $env:ISOLATED_DOTNET_SDK_INSTALLER_TARGET -Value $InstallDir
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Copy-Item -Path (Join-Path $env:ISOLATED_DOTNET_SDK_FAKE_HOST_ROOT '*') -Destination $InstallDir -Recurse -Force
exit 0
'@

        $successOutput = @(& pwsh -NoProfile -Command '
function Invoke-WebRequest { param($Uri, $OutFile) Copy-Item -LiteralPath $env:ISOLATED_DOTNET_SDK_FAKE_INSTALLER -Destination $OutFile -Force }
& $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -Version 99.0.100 -Yes
' 2>&1)

        $LASTEXITCODE | Should -Be 0
        ($successOutput -join [Environment]::NewLine) | Should -Match 'Isolated SDK installation completed successfully\.'
        $target = (Get-Content -LiteralPath $script:InstallerTargetPath -Raw).Trim()
        $target | Should -Not -Be $script:InstallDir
        Test-Path -LiteralPath $target | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:InstallDir 'dotnet.exe') | Should -BeTrue
        @(Get-ChildItem -LiteralPath $script:ToolRoot -Filter 'dotnet-install.*.ps1' -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'retries deterministically after a failed clean-start attempt' {
        Set-Content -LiteralPath $script:InstallerPath -Value @'
param([string]$Version, [string]$InstallDir, [switch]$NoPath)
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Set-Content -LiteralPath (Join-Path $InstallDir 'partial.txt') -Value 'partial'
exit 73
'@

        @(& pwsh -NoProfile -Command '
function Invoke-WebRequest { param($Uri, $OutFile) Copy-Item -LiteralPath $env:ISOLATED_DOTNET_SDK_FAKE_INSTALLER -Destination $OutFile -Force }
& $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -Version 99.0.100 -Yes
' 2>&1) | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
        Test-Path -LiteralPath $script:InstallDir | Should -BeFalse

        Set-Content -LiteralPath $script:InstallerPath -Value @'
param([string]$Version, [string]$InstallDir, [switch]$NoPath)
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Copy-Item -Path (Join-Path $env:ISOLATED_DOTNET_SDK_FAKE_HOST_ROOT '*') -Destination $InstallDir -Recurse -Force
exit 0
'@

        @(& pwsh -NoProfile -Command '
function Invoke-WebRequest { param($Uri, $OutFile) Copy-Item -LiteralPath $env:ISOLATED_DOTNET_SDK_FAKE_INSTALLER -Destination $OutFile -Force }
& $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -Version 99.0.100 -Yes
' 2>&1) | Out-Null
        $LASTEXITCODE | Should -Be 0
        Test-Path -LiteralPath (Join-Path $script:InstallDir 'dotnet.exe') | Should -BeTrue
    }
}
