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
        // Opt-in records cover the managed fake-host stack. Windows loader and CLR
        // initialization occur before Main; process StartTime anchors that gap.
        var stackPath = Environment.GetEnvironmentVariable("ISOLATED_DOTNET_SDK_FAKE_HOST_STACK_TRACE_PATH");
        var stackRows = string.IsNullOrWhiteSpace(stackPath) ? null : new System.Collections.Generic.List<string>();
        var mainClock = stackRows == null ? null : System.Diagnostics.Stopwatch.StartNew();
        var stackInvocation = stackRows == null ? "" : (Environment.GetEnvironmentVariable("ISOLATED_DOTNET_SDK_VERIFY_TRACE_INVOCATION") ?? "");
        var stackCase = stackRows == null ? "" : (Environment.GetEnvironmentVariable("ISOLATED_DOTNET_SDK_TEST_PROFILE_CASE") ?? Environment.GetEnvironmentVariable("ISOLATED_DOTNET_SDK_VERIFY_TRACE_CASE") ?? "");
        var stackArgument = stackRows == null ? "" : string.Join(" ", args);
        var stackPid = stackRows == null ? 0 : System.Diagnostics.Process.GetCurrentProcess().Id;
        Action<string> markStack = delegate(string phase)
        {
            if (stackRows != null)
            {
                stackRows.Add(DateTime.UtcNow.ToString("o") + "\t" + stackCase +
                    "\t" + stackInvocation + "\t" + stackPid + "\t" + stackArgument +
                    "\t" + phase + "\t" + mainClock.Elapsed.TotalMilliseconds.ToString(
                        System.Globalization.CultureInfo.InvariantCulture));
            }
        };
        markStack("main-entry");
        if (stackRows != null)
        {
            try
            {
                using (var process = System.Diagnostics.Process.GetCurrentProcess())
                {
                    stackRows.Add(process.StartTime.ToUniversalTime().ToString("o") + "\t" + stackCase +
                        "\t" + stackInvocation + "\t" + stackPid + "\t" + stackArgument +
                        "\t" + "os-process-created" + "\t" + "0");
                }
                markStack("os-process-time-read");
            }
            catch (Exception ex)
            {
                markStack("os-process-time-unavailable-" + ex.GetType().Name);
            }
            AppDomain.CurrentDomain.ProcessExit += delegate(object sender, EventArgs e)
            {
                markStack("process-exit");
                // Buffered write at exit, off by default.
                File.AppendAllLines(stackPath, stackRows);
            };
            markStack("stack-exit-handler-registered");
        }
        // Optional, test-only process markers. Never enabled during normal validation.
        var tracePath = Environment.GetEnvironmentVariable("ISOLATED_DOTNET_SDK_FAKE_HOST_TRACE_PATH");
        if (!string.IsNullOrWhiteSpace(tracePath))
        {
            var processId = System.Diagnostics.Process.GetCurrentProcess().Id;
            var caseId = Environment.GetEnvironmentVariable("ISOLATED_DOTNET_SDK_TEST_PROFILE_CASE") ?? Environment.GetEnvironmentVariable("ISOLATED_DOTNET_SDK_VERIFY_TRACE_CASE") ?? "";
            var invocationId = Environment.GetEnvironmentVariable("ISOLATED_DOTNET_SDK_VERIFY_TRACE_INVOCATION") ?? "";
            var arguments = string.Join(" ", args);
            var clock = System.Diagnostics.Stopwatch.StartNew();
            try
            {
                // Measures native process creation -> first managed Main code.
                // It intentionally excludes any delay before the OS created this process.
                var mainUtc = DateTime.UtcNow;
                var processStartUtc = System.Diagnostics.Process.GetCurrentProcess().StartTime.ToUniversalTime();
                var startupMs = (mainUtc - processStartUtc).TotalMilliseconds;
                File.AppendAllText(tracePath,
                    mainUtc.ToString("o") + "\t" + caseId + "\t" + processId +
                    "\tstartup\t" + arguments + "\t" +
                    startupMs.ToString(System.Globalization.CultureInfo.InvariantCulture) +
                    "\t" + invocationId + Environment.NewLine);
            }
            catch
            {
                // Tracing must not change native fake-host test behavior.
            }
            File.AppendAllText(tracePath,
                DateTime.UtcNow.ToString("o") + "\t" + caseId + "\t" + processId +
                "\tstart\t" + arguments + "\t0\t" + invocationId + Environment.NewLine);
            AppDomain.CurrentDomain.ProcessExit += delegate(object sender, EventArgs e)
            {
                clock.Stop();
                File.AppendAllText(tracePath,
                    DateTime.UtcNow.ToString("o") + "\t" + caseId + "\t" + processId +
                    "\texit\t" + arguments + "\t" +
                    clock.Elapsed.TotalMilliseconds.ToString(System.Globalization.CultureInfo.InvariantCulture) +
                    "\t" + invocationId + Environment.NewLine);
            };
        }

        markStack("fake-exit-code-check-start");
        var exitText = Environment.GetEnvironmentVariable("FAKE_DOTNET_EXIT_CODE");
        int exitCode;
        if (!string.IsNullOrWhiteSpace(exitText) && int.TryParse(exitText, out exitCode) && exitCode != 0)
        {
            return exitCode;
        }

        markStack("fake-exit-code-check-end");
        if (args.Length > 0 && args[0] == "--info")
        {
            markStack("info-enter");
            if (string.Equals(Environment.GetEnvironmentVariable("FAKE_DOTNET_LEGACY_HOST"), "true", StringComparison.OrdinalIgnoreCase))
            {
                var legacyVersion = Environment.GetEnvironmentVariable("FAKE_DOTNET_RESOLVED_VERSION")
                    ?? Environment.GetEnvironmentVariable("FAKE_DOTNET_SDK_VERSION") ?? "1.1.14";
                var basePath = Environment.GetEnvironmentVariable("FAKE_DOTNET_LEGACY_BASE_PATH")
                    ?? Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "sdk", legacyVersion);
                var infoExit = Environment.GetEnvironmentVariable("FAKE_DOTNET_LEGACY_INFO_EXIT_CODE");
                if (!string.IsNullOrEmpty(infoExit)) { return int.Parse(infoExit); }
                Console.WriteLine(".NET Command Line Tools (" + legacyVersion + ")");
                Console.WriteLine("Product Information:");
                Console.WriteLine(" Version: " + legacyVersion);
                Console.WriteLine("Runtime Environment:");
                if (!string.Equals(Environment.GetEnvironmentVariable("FAKE_DOTNET_LEGACY_MISSING_BASE_PATH"), "true", StringComparison.OrdinalIgnoreCase))
                {
                    Console.WriteLine(" Base Path: " + basePath);
                }
                var extraBasePath = Environment.GetEnvironmentVariable("FAKE_DOTNET_LEGACY_EXTRA_BASE_PATH");
                if (extraBasePath != null) { Console.WriteLine(" Base Path: " + extraBasePath); }
                var legacyRid = Environment.GetEnvironmentVariable("FAKE_DOTNET_LEGACY_RID");
                if (!string.IsNullOrEmpty(legacyRid)) { Console.WriteLine(" RID: " + legacyRid); }
                return 0;
            }
            Console.WriteLine("Runtime Environment:");
            Console.WriteLine(" RID:         win10-x64");
            Console.WriteLine();
            var legacyInfo = string.Equals(Environment.GetEnvironmentVariable("FAKE_DOTNET_LEGACY_INFO"), "true", StringComparison.OrdinalIgnoreCase);
            Console.WriteLine(legacyInfo ? "Host (useful for support):" : "Host:");
            Console.WriteLine("  Version:      99.0.9");
            if (!legacyInfo)
            {
                Console.WriteLine("  Architecture: x64");
            }
        }
        markStack("runtime-command-dispatch");
        if (args.Length > 0 && args[0] == "--list-runtimes")
        {
            markStack("runtime-enter");
            var probeMarker = Environment.GetEnvironmentVariable("FAKE_DOTNET_RUNTIME_PROBE_MARKER");
            if (!string.IsNullOrWhiteSpace(probeMarker)) { File.WriteAllText(probeMarker, "probed"); }
        }
        if (args.Length > 0 && args[0] == "--list-runtimes" &&
            string.Equals(Environment.GetEnvironmentVariable("FAKE_DOTNET_LEGACY_HOST"), "true", StringComparison.OrdinalIgnoreCase))
        {
            Console.Error.WriteLine("Unknown option: --list-runtimes");
            return 72;
        }
        if (args.Length > 0 && args[0] == "--list-runtimes")
        {
            var runtimeExitText = Environment.GetEnvironmentVariable("FAKE_DOTNET_RUNTIME_EXIT_CODE");
            if (!string.IsNullOrWhiteSpace(runtimeExitText)) { return int.Parse(runtimeExitText); }
            var runtimePath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "shared", "Microsoft.NETCore.App");
            Console.WriteLine("Microsoft.NETCore.App 99.0.9 [" + runtimePath + "]");
            var unrelated = Environment.GetEnvironmentVariable("FAKE_DOTNET_EXTRA_RUNTIME_ROOT");
            if (!string.IsNullOrEmpty(unrelated))
            {
                Console.WriteLine("Microsoft.AspNetCore.App 99.0.9 [" + unrelated + "]");
            }
        }

        if (args.Length > 0 && args[0] == "--list-sdks")
        {
            markStack("inventory-enter");
            if (string.Equals(Environment.GetEnvironmentVariable("FAKE_DOTNET_LEGACY_HOST"), "true", StringComparison.OrdinalIgnoreCase))
            {
                Console.Error.WriteLine("Unknown option: --list-sdks");
                return 1;
            }
            var conflictPath = Environment.GetEnvironmentVariable("FAKE_DOTNET_CREATE_CONFLICT");
            if (!string.IsNullOrWhiteSpace(conflictPath))
            {
                Directory.CreateDirectory(conflictPath);
                File.WriteAllText(Path.Combine(conflictPath, "sentinel.txt"), "preserve-conflict");
            }

            var version = Environment.GetEnvironmentVariable("FAKE_DOTNET_SDK_VERSION") ?? "99.0.100";
            var origin = Environment.GetEnvironmentVariable("FAKE_DOTNET_SDK_ORIGIN") ?? Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "sdk");
            markStack("inventory-output-start");
            Console.WriteLine(version + " [" + origin + "]");
            markStack("inventory-output-complete");
        }

        if (args.Length > 0 && args[0] == "--version")
        {
            markStack("version-enter");
            var resolved = Environment.GetEnvironmentVariable("FAKE_DOTNET_RESOLVED_VERSION")
                ?? Environment.GetEnvironmentVariable("FAKE_DOTNET_SDK_VERSION") ?? "99.0.100";
            var expectedLookup = Environment.GetEnvironmentVariable("FAKE_DOTNET_EXPECT_MULTILEVEL_LOOKUP");
            if (!string.IsNullOrEmpty(expectedLookup) && Environment.GetEnvironmentVariable("DOTNET_MULTILEVEL_LOOKUP") != expectedLookup)
            {
                return 74;
            }
            var forbiddenCwd = Environment.GetEnvironmentVariable("FAKE_DOTNET_FORBIDDEN_WORK_DIR");
            if (!string.IsNullOrWhiteSpace(forbiddenCwd) && Environment.CurrentDirectory.StartsWith(forbiddenCwd, StringComparison.OrdinalIgnoreCase))
            {
                return 75;
            }
            if (string.Equals(Environment.GetEnvironmentVariable("FAKE_DOTNET_REQUIRE_PINNED_VERSION"), "true", StringComparison.OrdinalIgnoreCase))
            {
                var globalJson = Path.Combine(Environment.CurrentDirectory, "global.json");
                if (!File.Exists(globalJson) ||
                    !File.ReadAllText(globalJson).Contains("\"version\": \"" + resolved + "\"") ||
                    Environment.GetEnvironmentVariable("DOTNET_MULTILEVEL_LOOKUP") != "0" ||
                    Environment.GetEnvironmentVariable("DOTNET_ROOT") != AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar))
                {
                    return 76;
                }
            }
            if (!string.Equals(Environment.GetEnvironmentVariable("FAKE_DOTNET_LEGACY_SUPPRESS_VERSION"), "true", StringComparison.OrdinalIgnoreCase))
            {
                Console.WriteLine(resolved);
            }
            var extraVersion = Environment.GetEnvironmentVariable("FAKE_DOTNET_LEGACY_EXTRA_VERSION");
            if (extraVersion != null) { Console.WriteLine(extraVersion); }
        }

        markStack("main-success-return");
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
