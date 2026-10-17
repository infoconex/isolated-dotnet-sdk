# Opt-in Verify diagnostics, never invoked by production or unflagged tests.
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('PowerShellNative', 'DirectProcess')]
    [string]$Mode,

    [Parameter(Mandatory = $true)]
    [ValidateSet('Existing', 'Fresh')]
    [string]$CopyMode,

    [Parameter(Mandatory = $true)]
    [string]$HostPath,

    [Parameter(Mandatory = $true)]
    [string]$ReportPath,

    [ValidateRange(1, 10)]
    [int]$Iterations = 3
)

$ErrorActionPreference = 'Stop'
$script:ProbeEvents = [System.Collections.Generic.List[object]]::new()

function Add-LaunchProbeEvent {
    param(
        [int]$Iteration,
        [string]$Phase,
        [datetime]$StartedUtc,
        [double]$ElapsedMs,
        [string]$InvocationId,
        [string]$ExitCode = '',
        [string]$Detail = ''
    )
    $script:ProbeEvents.Add([pscustomobject]@{
            Mode = $Mode
            CopyMode = $CopyMode
            Iteration = $Iteration
            Phase = $Phase
            StartedUtc = $StartedUtc.ToString('o')
            ElapsedMs = [math]::Round($ElapsedMs, 3)
            InvocationId = $InvocationId
            ExitCode = $ExitCode
            Detail = $Detail.Replace([char]13, ' ').Replace([char]10, ' ').Replace([char]9, ' ')
        })
}

$scriptStarted = [datetime]::UtcNow
Add-LaunchProbeEvent -Iteration 0 -Phase 'child-script-entry' -StartedUtc $scriptStarted -ElapsedMs 0 -InvocationId ''

$previousInvocation = [Environment]::GetEnvironmentVariable(
    'ISOLATED_DOTNET_SDK_VERIFY_TRACE_INVOCATION', 'Process')
try {
    for ($iteration = 1; $iteration -le $Iterations; $iteration++) {
        $invocationId = "probe-$Mode-$CopyMode-$iteration-$([guid]::NewGuid().ToString('N'))"
        $env:ISOLATED_DOTNET_SDK_VERIFY_TRACE_INVOCATION = $invocationId
        $effectiveHostPath = $HostPath
        $copyDirectory = $null
        if ($CopyMode -eq 'Fresh') {
            $copyDirectory = Join-Path ([IO.Path]::GetTempPath()) (
                "isolated-sdk-native-probe-{0}" -f ([guid]::NewGuid().ToString('N')))
            $copyStartedUtc = [DateTime]::UtcNow
            $copyClock = [Diagnostics.Stopwatch]::StartNew()
            try {
                $null = New-Item -ItemType Directory -Path $copyDirectory -Force -ErrorAction Stop
                $effectiveHostPath = Join-Path $copyDirectory 'dotnet.exe'
                [IO.File]::Copy($HostPath, $effectiveHostPath)
            }
            finally {
                $copyClock.Stop()
            }
            Add-LaunchProbeEvent -Iteration $iteration -Phase 'fresh-executable-copy-complete' -StartedUtc $copyStartedUtc -ElapsedMs $copyClock.Elapsed.TotalMilliseconds -InvocationId $invocationId
        }
        $startUtc = [datetime]::UtcNow
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $code = ''
        $message = ''
        try {
            if ($Mode -eq 'PowerShellNative') {
                # Identical native PowerShell invocation mechanism to production Verify.
                $output = @(& $effectiveHostPath --list-sdks)
                $code = [string]$LASTEXITCODE
                if ($code -eq '0' -and ($output -join '') -notmatch '99\.0\.100') {
                    $message = 'Host inventory output was unexpected.'
                }
            }
            else {
                # Direct .NET process-launch control, capturing both streams.
                $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
                $startInfo.FileName = $effectiveHostPath
                $startInfo.Arguments = '--list-sdks'
                $startInfo.UseShellExecute = $false
                $startInfo.RedirectStandardOutput = $true
                $startInfo.RedirectStandardError = $true
                $startInfo.CreateNoWindow = $true
                $process = $null
                try {
                    $process = [System.Diagnostics.Process]::Start($startInfo)
                    $output = $process.StandardOutput.ReadToEnd()
                    $stderr = $process.StandardError.ReadToEnd()
                    $process.WaitForExit()
                    $code = [string]$process.ExitCode
                    if ($code -eq '0' -and $output -notmatch '99\.0\.100') {
                        $message = 'Host inventory output was unexpected.'
                    }
                    if ($stderr) { $message += " StandardError: $stderr" }
                }
                finally {
                    if ($null -ne $process) { $process.Dispose() }
                }
            }
        }
        catch {
            $code = 'exception'
            $message = $_.Exception.ToString()
        }
        finally {
            $timer.Stop()
        }
        Add-LaunchProbeEvent -Iteration $iteration -Phase 'native-list-sdks-complete' -StartedUtc $startUtc -ElapsedMs $timer.Elapsed.TotalMilliseconds -InvocationId $invocationId -ExitCode $code -Detail $message
        if ($null -ne $copyDirectory) {
            Remove-Item -LiteralPath $copyDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }

        # OS-native reference process in the same pwsh session; unlike the
        # compiled fake dotnet host this executable does not initialize CLR.
        if ($IsWindows) {
            $referencePath = Join-Path $env:WINDIR 'System32/cmd.exe'
            $osStartedUtc = [DateTime]::UtcNow
            $osTimer = [System.Diagnostics.Stopwatch]::StartNew()
            $osExit = ''
            $osDetail = ''
            try {
                if ($Mode -eq 'PowerShellNative') {
                    $null = @(& $referencePath /d /c exit 0)
                    $osExit = [string]$LASTEXITCODE
                }
                else {
                    $referenceInfo = [System.Diagnostics.ProcessStartInfo]::new()
                    $referenceInfo.FileName = $referencePath
                    $referenceInfo.Arguments = '/d /c exit 0'
                    $referenceInfo.UseShellExecute = $false
                    $referenceInfo.RedirectStandardOutput = $true
                    $referenceInfo.RedirectStandardError = $true
                    $referenceProcess = $null
                    try {
                        $referenceProcess = [System.Diagnostics.Process]::Start($referenceInfo)
                        $null = $referenceProcess.StandardOutput.ReadToEnd()
                        $osDetail = $referenceProcess.StandardError.ReadToEnd()
                        $referenceProcess.WaitForExit()
                        $osExit = [string]$referenceProcess.ExitCode
                    }
                    finally {
                        if ($null -ne $referenceProcess) { $referenceProcess.Dispose() }
                    }
                }
            }
            catch {
                $osExit = 'exception'
                $osDetail = $_.Exception.ToString()
            }
            finally {
                $osTimer.Stop()
            }
            Add-LaunchProbeEvent -Iteration $iteration -Phase 'os-control-complete' -StartedUtc $osStartedUtc -ElapsedMs $osTimer.Elapsed.TotalMilliseconds -InvocationId $invocationId -ExitCode $osExit -Detail $osDetail
        }
    }
}
finally {
    [Environment]::SetEnvironmentVariable(
        'ISOLATED_DOTNET_SDK_VERIFY_TRACE_INVOCATION', $previousInvocation, 'Process')
    # Buffered events are emitted once after all measured commands.
    $script:ProbeEvents | Export-Csv -LiteralPath $ReportPath -Append -NoTypeInformation -Encoding utf8
}
