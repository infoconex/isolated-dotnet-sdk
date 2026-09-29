param(
    [Parameter(Mandatory = $true)]
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'

$projectRoot = Join-Path $OutputRoot 'source'
$hostOutput = Join-Path $OutputRoot 'out'
New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null
New-Item -ItemType Directory -Path $hostOutput -Force | Out-Null

$sourcePath = Join-Path $projectRoot 'Program.cs'
Set-Content -LiteralPath $sourcePath -Value @'
using System;
using System.IO;

public static class Program
{
    public static int Main(string[] args)
    {
        var exitText = Environment.GetEnvironmentVariable("FAKE_DOTNET_EXIT_CODE");
        int exitCode;
        if (!string.IsNullOrWhiteSpace(exitText) && int.TryParse(exitText, out exitCode) && exitCode != 0)
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

$compiled = $false
if ($IsWindows) {
    $frameworkRoots = @(
        (Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319'),
        (Join-Path $env:WINDIR 'Microsoft.NET/Framework/v4.0.30319')
    )
    $compiler = $frameworkRoots |
        ForEach-Object { Join-Path $_ 'csc.exe' } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1

    if ($compiler) {
        $hostPath = Join-Path $hostOutput 'dotnet.exe'
        & $compiler /nologo /target:exe "/out:$hostPath" $sourcePath
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to compile the deterministic shared fake dotnet host with csc.exe. Exit code: $LASTEXITCODE"
        }
        $compiled = $true
    }
}

if (-not $compiled) {
    $projectPath = Join-Path $projectRoot 'FakeDotNet.csproj'
    Set-Content -LiteralPath $projectPath -Value @'
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

    & dotnet build `
        $projectPath `
        -c Release `
        -o $hostOutput `
        --nologo `
        --verbosity quiet
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to build the deterministic shared fake dotnet host. Exit code: $LASTEXITCODE"
    }
}

$hostOutput
