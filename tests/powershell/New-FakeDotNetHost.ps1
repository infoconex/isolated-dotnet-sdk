param(
    [Parameter(Mandatory = $true)]
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'

$projectRoot = Join-Path $OutputRoot 'source'
$hostOutput = Join-Path $OutputRoot 'out'
New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null

Set-Content -LiteralPath (Join-Path $projectRoot 'FakeDotNet.csproj') -Value @'
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

Set-Content -LiteralPath (Join-Path $projectRoot 'Program.cs') -Value @'
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
    (Join-Path $projectRoot 'FakeDotNet.csproj') `
    -c Release `
    -o $hostOutput `
    --nologo `
    --verbosity quiet
if ($LASTEXITCODE -ne 0) {
    throw "Unable to build the deterministic shared fake dotnet host. Exit code: $LASTEXITCODE"
}

$hostOutput
