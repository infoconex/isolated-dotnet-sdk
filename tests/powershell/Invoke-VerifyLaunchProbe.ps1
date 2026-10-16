# Opt-in Verify diagnostics, never invoked by production or unflagged tests.
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('PowerShellNative', 'DirectProcess')]
    [string]$Mode,

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
        $invocationId = "probe-$Mode-$iteration"
        $env:ISOLATED_DOTNET_SDK_VERIFY_TRACE_INVOCATION = $invocationId
        $startUtc = [datetime]::UtcNow
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $code = ''
        $message = ''
        try {
            if ($Mode -eq 'PowerShellNative') {
                # Identical native PowerShell invocation mechanism to production Verify.
                $output = @(& $HostPath --list-sdks)
                $code = [string]$LASTEXITCODE
                if ($code -eq '0' -and ($output -join '') -notmatch '99\.0\.100') {
                    $message = 'Host inventory output was unexpected.'
                }
            }
            else {
                # Direct .NET process-launch control, capturing both streams.
                $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
                $startInfo.FileName = $HostPath
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
    }
}
finally {
    [Environment]::SetEnvironmentVariable(
        'ISOLATED_DOTNET_SDK_VERIFY_TRACE_INVOCATION', $previousInvocation, 'Process')
    # Buffered events are emitted once after all measured commands.
    $script:ProbeEvents | Export-Csv -LiteralPath $ReportPath -Append -NoTypeInformation -Encoding utf8
}
