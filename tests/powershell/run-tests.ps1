param(
    [ValidateSet('All', 'Verify')]
    [string]$Suite = 'All',

    [switch]$TraceVerifyProcesses,

    [switch]$TraceVerifySteps,

    [switch]$TraceVerifyStack,

    [switch]$TraceVerifyPrewarmHost
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$config = Get-Content -LiteralPath (Join-Path $repoRoot '.config/test-frameworks.json') -Raw |
    ConvertFrom-Json
$expectedVersion = [version][string]$config.pesterVersion

if ($null -eq $expectedVersion) {
    throw 'pesterVersion is required in .config/test-frameworks.json.'
}

$availablePester = Get-Module -ListAvailable -Name Pester |
    Where-Object { $_.Version -eq $expectedVersion } |
    Select-Object -First 1

if ($null -eq $availablePester) {
    throw "Pester $expectedVersion is required. See docs/maintainers/testing/testing.md."
}

Import-Module Pester -RequiredVersion $expectedVersion -Force

if ($TraceVerifyPrewarmHost -and -not $TraceVerifyStack) {
    throw '-TraceVerifyPrewarmHost requires -TraceVerifyStack.'
}
if ($TraceVerifyStack -and ($TraceVerifyProcesses -or $TraceVerifySteps)) {
    throw '-TraceVerifyStack includes all step and process tracing; do not combine the switches.'
}
if ($TraceVerifyStack) {
    $TraceVerifySteps = $true
}
if ($TraceVerifyProcesses -and $Suite -ne 'Verify') {
    throw '-TraceVerifyProcesses requires -Suite Verify to keep traces scoped to one test file.'
}
if ($TraceVerifySteps -and $Suite -ne 'Verify') {
    throw '-TraceVerifySteps requires -Suite Verify.'
}
if ($TraceVerifySteps -and $TraceVerifyProcesses) {
    throw '-TraceVerifySteps already includes the existing Verify process trace; do not specify both switches.'
}
$traceEnabled = $TraceVerifyProcesses -or $TraceVerifySteps

$traceRoot = $null
$previousVerifyTrace = [Environment]::GetEnvironmentVariable('ISOLATED_DOTNET_SDK_VERIFY_TRACE_PATH', 'Process')
$previousHostTrace = [Environment]::GetEnvironmentVariable('ISOLATED_DOTNET_SDK_FAKE_HOST_TRACE_PATH', 'Process')
$previousChildTrace = [Environment]::GetEnvironmentVariable('ISOLATED_DOTNET_SDK_VERIFY_CHILD_TRACE_PATH', 'Process')
$previousInvocation = [Environment]::GetEnvironmentVariable('ISOLATED_DOTNET_SDK_VERIFY_TRACE_INVOCATION', 'Process')
$previousStepTrace = [Environment]::GetEnvironmentVariable('ISOLATED_DOTNET_SDK_VERIFY_STEP_TRACE_PATH', 'Process')
$previousStepScenario = [Environment]::GetEnvironmentVariable('ISOLATED_DOTNET_SDK_VERIFY_STEP_SCENARIO', 'Process')
$previousStackTrace = [Environment]::GetEnvironmentVariable('ISOLATED_DOTNET_SDK_VERIFY_STACK_TRACE_PATH', 'Process')
$previousStackHostTrace = [Environment]::GetEnvironmentVariable('ISOLATED_DOTNET_SDK_FAKE_HOST_STACK_TRACE_PATH', 'Process')
$previousParentPrewarm = [Environment]::GetEnvironmentVariable('ISOLATED_DOTNET_SDK_VERIFY_PARENT_PREWARM_HOST', 'Process')

if ($traceEnabled) {
    $traceRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
        'isolated-dotnet-sdk-verify-trace-{0}-{1}' -f
        (Get-Date -Format 'yyyyMMdd-HHmmss'), [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $traceRoot -Force | Out-Null
    $env:ISOLATED_DOTNET_SDK_VERIFY_TRACE_PATH = Join-Path $traceRoot 'verify-invocations.csv'
    $env:ISOLATED_DOTNET_SDK_FAKE_HOST_TRACE_PATH = Join-Path $traceRoot 'fake-host-events.tsv'
    $env:ISOLATED_DOTNET_SDK_VERIFY_CHILD_TRACE_PATH = Join-Path $traceRoot 'verify-child-events.tsv'
    if ($TraceVerifySteps) {
        $env:ISOLATED_DOTNET_SDK_VERIFY_STEP_TRACE_PATH = Join-Path $traceRoot 'step-timings.csv'
    }
    else {
        Remove-Item Env:ISOLATED_DOTNET_SDK_VERIFY_STEP_TRACE_PATH -ErrorAction SilentlyContinue
    }
    if ($TraceVerifyStack) {
        $env:ISOLATED_DOTNET_SDK_VERIFY_STACK_TRACE_PATH = Join-Path $traceRoot 'stack-launch-probes.csv'
        $env:ISOLATED_DOTNET_SDK_FAKE_HOST_STACK_TRACE_PATH = Join-Path $traceRoot 'stack-host-startup.tsv'
        if ($TraceVerifyPrewarmHost) {
            $env:ISOLATED_DOTNET_SDK_VERIFY_PARENT_PREWARM_HOST = '1'
        }
        else {
            Remove-Item Env:ISOLATED_DOTNET_SDK_VERIFY_PARENT_PREWARM_HOST -ErrorAction SilentlyContinue
        }
    }
    else {
        Remove-Item Env:ISOLATED_DOTNET_SDK_VERIFY_STACK_TRACE_PATH -ErrorAction SilentlyContinue
        Remove-Item Env:ISOLATED_DOTNET_SDK_FAKE_HOST_STACK_TRACE_PATH -ErrorAction SilentlyContinue
        Remove-Item Env:ISOLATED_DOTNET_SDK_VERIFY_PARENT_PREWARM_HOST -ErrorAction SilentlyContinue
    }
}

function Get-ProfileTestRow {
    param([object]$Block)

    foreach ($test in @($Block.Tests)) {
        if ($null -eq $test) { continue }
        [pscustomobject]@{
            Test = $test.ExpandedPath
            Status = $test.Result
            StartedUtc = if ($null -eq $test.ExecutedAt) { '' } else { $test.ExecutedAt.ToUniversalTime().ToString('o') }
            DurationMs = [math]::Round($test.Duration.TotalMilliseconds, 2)
            UserMs = [math]::Round($test.UserDuration.TotalMilliseconds, 2)
            FrameworkMs = [math]::Round($test.FrameworkDuration.TotalMilliseconds, 2)
        }
    }

    foreach ($child in @($Block.Blocks)) {
        if ($null -ne $child) { Get-ProfileTestRow -Block $child }
    }
}

$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-shared-host-{0}" -f [guid]::NewGuid())
$fixtureTimer = [System.Diagnostics.Stopwatch]::StartNew()
$suiteTimer = [System.Diagnostics.Stopwatch]::StartNew()

try {
    $sharedHostRoot = & (Join-Path $PSScriptRoot 'New-FakeDotNetHost.ps1') -OutputRoot $fixtureRoot
    if ([string]::IsNullOrWhiteSpace($sharedHostRoot) -or -not (Test-Path -LiteralPath $sharedHostRoot -PathType Container)) {
        throw 'Shared deterministic fake dotnet host was not created.'
    }
    $fixtureTimer.Stop()
    $env:ISOLATED_DOTNET_SDK_SHARED_FAKE_HOST_ROOT = $sharedHostRoot
    Write-Output ("Shared fake dotnet host setup: {0:N2}s" -f $fixtureTimer.Elapsed.TotalSeconds)

    $testPath = if ($Suite -eq 'Verify') {
        Join-Path $PSScriptRoot 'verify.Tests.ps1'
    }
    else {
        Join-Path $PSScriptRoot '*.Tests.ps1'
    }

    $pesterArguments = @{
        Path = $testPath
        PassThru = $true
        Output = 'Detailed'
    }
    if ($TraceVerifySteps) {
        # Tag selects exactly one existing test, including both failure and success subcases.
        $pesterArguments.TagFilter = 'VerifyStepProfile'
    }
    $result = Invoke-Pester @pesterArguments

    $suiteTimer.Stop()
    Write-Output ("PowerShell behavioral validation wall time: {0:N2}s" -f $suiteTimer.Elapsed.TotalSeconds)

    if ($traceEnabled) {
        $rows = @(
            foreach ($container in $result.Containers) {
                foreach ($block in $container.Blocks) {
                    Get-ProfileTestRow -Block $block
                }
            }
        )
        $rows | Sort-Object StartedUtc |
            Export-Csv -LiteralPath (Join-Path $traceRoot 'test-timings.csv') -NoTypeInformation -Encoding utf8

        $invocationPath = Join-Path $traceRoot 'verify-invocations.csv'
        $calls = @(if (Test-Path -LiteralPath $invocationPath -PathType Leaf) {
                Import-Csv -LiteralPath $invocationPath
            })
        $gitHead = if (Get-Command git -ErrorAction SilentlyContinue) {
            (& git -C $repoRoot rev-parse HEAD 2>$null)
        }
        else {
            $null
        }
        [pscustomobject]@{
            GitHead = $gitHead
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
            PesterVersion = $expectedVersion.ToString()
            Suite = $Suite
            Passed = $result.PassedCount
            Failed = $result.FailedCount
            Skipped = $result.SkippedCount
            WallMs = [math]::Round($suiteTimer.Elapsed.TotalMilliseconds, 2)
            TracedChildCalls = $calls.Count
            TracedChildMs = [math]::Round(($calls | Measure-Object -Property ChildPwshMs -Sum).Sum, 2)
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $traceRoot 'summary.json') -Encoding utf8

        if ($TraceVerifySteps -and $result.Result -eq 'Passed') {
            $stepPath = Join-Path $traceRoot 'step-timings.csv'
            if (-not (Test-Path -LiteralPath $stepPath -PathType Leaf)) {
                throw 'The selected Verify test produced no step-timing report.'
            }
            $steps = @(Import-Csv -LiteralPath $stepPath)
            if (@($steps | Where-Object Scope -eq 'Child').Count -eq 0 -or
                @($steps | Where-Object Scope -eq 'Test').Count -eq 0) {
                throw 'The step-timing report must contain child and test steps.'
            }
            # The existing fake host reports its own Main-to-ProcessExit intervals.
            # Incorporate those native phases without injecting commands beside the
            # product's native invocations (which must retain their original shape).
            $nativeTrace = Join-Path $traceRoot 'fake-host-events.tsv'
            $nativeRows = @(
                if (Test-Path -LiteralPath $nativeTrace -PathType Leaf) {
                    foreach ($line in (Get-Content -LiteralPath $nativeTrace)) {
                        $columns = $line.Split("`t")
                        if ($columns.Count -ne 7 -or $columns[3] -ne 'exit') {
                            continue
                        }
                        $child = @($steps | Where-Object {
                                $_.Scope -eq 'Child' -and $_.InvocationId -eq $columns[6]
                            } | Select-Object -First 1)
                        $elapsed = 0.0
                        if (-not [double]::TryParse($columns[5],
                                [System.Globalization.NumberStyles]::Float,
                                [System.Globalization.CultureInfo]::InvariantCulture,
                                [ref]$elapsed)) {
                            throw "Invalid fake-host duration in the trace: $($columns[5])"
                        }
                        [pscustomobject]@{
                            Scope = 'Native'
                            InvocationId = $columns[6]
                            Scenario = if ($child.Count -gt 0) { $child[0].Scenario } else { 'unknown' }
                            Step = "dotnet.exe $($columns[4]) (Main to exit)"
                            ElapsedMs = [math]::Round($elapsed, 3)
                            CumulativeMs = ''
                            Utc = ''
                        }
                    }
                }
            )
            if ($nativeRows.Count -gt 0) {
                $nativeRows | Export-Csv -LiteralPath $stepPath -Append -NoTypeInformation -Encoding utf8
                $steps = @(Import-Csv -LiteralPath $stepPath)
            }
            if ($result.Result -eq 'Passed' -and $nativeRows.Count -eq 0) {
                throw 'The healthy Verify case passed but native fake-host events were not recorded.'
            }
            if ($TraceVerifyStack) {
                $probePath = $env:ISOLATED_DOTNET_SDK_VERIFY_STACK_TRACE_PATH
                if (-not (Test-Path -LiteralPath $probePath -PathType Leaf)) {
                    throw 'Stack launch profiling produced no process control records.'
                }
                $probeRows = @(Import-Csv -LiteralPath $probePath)
                foreach ($copyMode in @('Fresh', 'Existing', 'SdkLayout')) {
                    foreach ($mode in @('PowerShellNative', 'DirectProcess')) {
                        if (@($probeRows | Where-Object {
                                    $_.Mode -eq $mode -and
                                    $_.CopyMode -eq $copyMode -and
                                    $_.Phase -eq 'native-list-sdks-complete'
                                }).Count -lt 3) {
                            throw "Full-stack profiling requires multiple launch controls: $mode/$copyMode."
                        }
                    }
                }
                # Join OS process creation, first managed instruction and exit
                # by invocation ID plus PID. These are separate UTC sources.
                $startupPath = Join-Path $traceRoot 'stack-host-startup.tsv'
                if (-not (Test-Path -LiteralPath $startupPath -PathType Leaf)) {
                    throw 'The fake dotnet host emitted no deep process startup phases.'
                }
                $hostEvents = @(
                    foreach ($line in (Get-Content -LiteralPath $startupPath)) {
                        $columns = $line.Split([char]9)
                        if ($columns.Count -ne 7) {
                            throw "Invalid fake host startup event: $line"
                        }
                        [pscustomobject]@{
                            Utc = [datetimeoffset]::Parse($columns[0], [System.Globalization.CultureInfo]::InvariantCulture)
                            InvocationId = $columns[2]
                            ProcessId = $columns[3]
                            Command = $columns[4]
                            Phase = $columns[5]
                        }
                    }
                )
                $startupRows = @(
                    foreach ($group in ($hostEvents | Group-Object InvocationId, ProcessId)) {
                        $events = @($group.Group)
                        $osStart = @($events | Where-Object Phase -eq 'os-process-created' | Select-Object -First 1)
                        $mainEntry = @($events | Where-Object Phase -eq 'main-entry' | Select-Object -First 1)
                        $exitEvent = @($events | Where-Object Phase -eq 'process-exit' | Select-Object -First 1)
                        if ($osStart.Count -eq 0 -or $mainEntry.Count -eq 0 -or $exitEvent.Count -eq 0) {
                            continue
                        }
                        # In the temporary product copy, record launch
                        # boundaries separately for internal preflight and the
                        # subsequent real SDK inventory call. Choose the latest
                        # boundary preceding this specific process creation.
                        $callToProcess = ''
                        $launchMarkerStep = ''
                        if ($events[0].Command -eq '--list-sdks') {
                            $launchMarker = $null
                            foreach ($candidate in @($steps | Where-Object {
                                        $_.Scope -eq 'Child' -and
                                        $_.InvocationId -eq $events[0].InvocationId -and
                                        $_.Step -in @('internal-preflight-start', 'native-inventory-call-start')
                                    })) {
                                $candidateUtc = [datetimeoffset]::Parse(
                                    $candidate.Utc, [System.Globalization.CultureInfo]::InvariantCulture)
                                if ($candidateUtc -le $osStart[0].Utc -and
                                    ($null -eq $launchMarker -or $candidateUtc -gt $launchMarker.Utc)) {
                                    $launchMarker = [pscustomobject]@{
                                        Utc = $candidateUtc
                                        Step = $candidate.Step
                                    }
                                }
                            }
                            if ($null -ne $launchMarker) {
                                $callToProcess = [math]::Round(
                                    ($osStart[0].Utc - $launchMarker.Utc).TotalMilliseconds, 3)
                                $launchMarkerStep = $launchMarker.Step
                            }
                        }
                        [pscustomobject]@{
                            InvocationId = $events[0].InvocationId
                            ProcessId = $events[0].ProcessId
                            Command = $events[0].Command
                            ProcessCreatedUtc = $osStart[0].Utc.ToString('o')
                            ManagedMainUtc = $mainEntry[0].Utc.ToString('o')
                            ProcessExitUtc = $exitEvent[0].Utc.ToString('o')
                            LaunchMarkerStep = $launchMarkerStep
                            PowerShellMarkerToOsProcessMs = $callToProcess
                            OsProcessToManagedMainMs = [math]::Round(($mainEntry[0].Utc - $osStart[0].Utc).TotalMilliseconds, 3)
                            ManagedMainToExitMs = [math]::Round(($exitEvent[0].Utc - $mainEntry[0].Utc).TotalMilliseconds, 3)
                        }
                    }
                )
                if ($startupRows.Count -lt 4) {
                    throw "Expected at least four startup pairs; found $($startupRows.Count)."
                }
                $startupRows |
                    Export-Csv -LiteralPath (Join-Path $traceRoot 'stack-host-startup-summary.csv') -NoTypeInformation -Encoding utf8
                Write-Output ('Compiled fake host startup/managed phases: {0} correlated processes' -f $startupRows.Count)
                $startupRows |
                    Select-Object -First 16 Command, PowerShellMarkerToOsProcessMs, OsProcessToManagedMainMs, ManagedMainToExitMs |
                    Format-Table -AutoSize |
                    Out-String -Width 180 |
                    Write-Output
                Write-Output ('Independent launch controls: {0} rows' -f $probeRows.Count)
                # Correlate control process-start timestamps with the child's
                # launch-event UTC marker; recording per-process phases separately
                # avoids misattributing pre-create delays to CLR execution.
                $probeCalls = @(
                    foreach ($probe in ($probeRows | Where-Object Phase -eq 'native-list-sdks-complete')) {
                        $matchedHost = @($startupRows | Where-Object {
                                $_.InvocationId -eq $probe.InvocationId -and $_.Command -eq '--list-sdks'
                            } | Select-Object -First 1)
                        $preCreate = ''
                        $osToManaged = ''
                        if ($matchedHost.Count -gt 0) {
                            $started = [datetimeoffset]::Parse(
                                $probe.StartedUtc, [System.Globalization.CultureInfo]::InvariantCulture)
                            $created = [datetimeoffset]::Parse(
                                $matchedHost[0].ProcessCreatedUtc, [System.Globalization.CultureInfo]::InvariantCulture)
                            $preCreate = [math]::Round(($created - $started).TotalMilliseconds, 3)
                            $osToManaged = $matchedHost[0].OsProcessToManagedMainMs
                        }
                        [pscustomobject]@{
                            Mode = $probe.Mode
                            CopyMode = $probe.CopyMode
                            Iteration = $probe.Iteration
                            InvocationId = $probe.InvocationId
                            WallMs = [double]$probe.ElapsedMs
                            BeforeProcessCreatedMs = $preCreate
                            OsProcessToManagedMainMs = $osToManaged
                            ExitCode = $probe.ExitCode
                        }
                    }
                )
                $probeCalls |
                    Export-Csv -LiteralPath (Join-Path $traceRoot 'stack-launch-phase-comparison.csv') -NoTypeInformation -Encoding utf8
                $comparison = @(
                    $probeCalls | Group-Object Mode, CopyMode | ForEach-Object {
                        $ordered = @($_.Group | ForEach-Object WallMs | Sort-Object)
                        $center = [int][math]::Floor($ordered.Count / 2)
                        $median = if ($ordered.Count % 2 -eq 0) {
                            ($ordered[$center - 1] + $ordered[$center]) / 2
                        }
                        else {
                            $ordered[$center]
                        }
                        $preCreation = @($_.Group |
                                Where-Object { $_.BeforeProcessCreatedMs -ne '' } |
                                ForEach-Object { [double]$_.BeforeProcessCreatedMs } |
                                Sort-Object)
                        $preMedian = ''
                        if ($preCreation.Count -gt 0) {
                            $mid = [int][math]::Floor($preCreation.Count / 2)
                            $preMedian = [math]::Round($(if ($preCreation.Count % 2 -eq 0) {
                                        ($preCreation[$mid - 1] + $preCreation[$mid]) / 2
                                    }
                                    else { $preCreation[$mid] }), 3)
                        }
                        [pscustomobject]@{
                            Condition = $_.Name
                            Count = $_.Count
                            MedianMs = [math]::Round($median, 3)
                            PreCreateMedianMs = $preMedian
                            Failures = @($_.Group | Where-Object { $_.ExitCode -ne '0' }).Count
                        }
                    }
                )
                Write-Output 'Existing, fresh executable, and isolated SDK fixture launch comparison:'
                $comparison | Format-Table -AutoSize | Out-String -Width 180 | Write-Output
                $probeRows |
                    Where-Object Phase -eq 'native-list-sdks-complete' |
                    Select-Object Mode, CopyMode, Iteration, ElapsedMs, ExitCode |
                    Format-Table -AutoSize |
                    Out-String -Width 180 |
                    Write-Output
            }
            if ($TraceVerifyStack) {
                $internalRows = @($steps | Where-Object {
                        $_.Scope -eq 'Child' -and (
                            $_.Step -eq 'internal-preflight-complete' -or
                            $_.Step -eq 'local-proof-inventory-validated')
                    })
                if (@($internalRows | Where-Object Step -eq 'internal-preflight-complete').Count -lt 2) {
                    throw 'Expected both internal Verify preflight control measurements.'
                }
                Write-Output 'First native command versus Verify inventory (including fresh no-preflight controls):'
                $internalRows |
                    Select-Object Scenario, Step, ElapsedMs |
                    Format-Table -AutoSize |
                    Out-String -Width 180 |
                    Write-Output
            }
            Write-Output ("Recorded {0} buffered step timings from the selected Verify test:" -f $steps.Count)
            $steps |
                Select-Object Scope, Scenario, Step, ElapsedMs |
                Format-Table -AutoSize |
                Out-String -Width 180 |
                Write-Output
        }
        elseif ($TraceVerifySteps) {
            # The instrumented Pester test can fail before it starts any child
            # processes. Preserve all available raw trace records rather than
            # throwing another exception that masks the original failure.
            Write-Warning 'The Verify profile failed; archiving available partial trace files without complete-phase assertions.'
        }

        $reportFiles = @(Get-ChildItem -LiteralPath $traceRoot -File)
        $archivePath = "$traceRoot.zip"
        Compress-Archive -LiteralPath $reportFiles.FullName -DestinationPath $archivePath -Force
        Write-Output "Verify process trace: $archivePath"
    }

    if ($result.Result -ne 'Passed') {
        exit 1
    }
}
finally {
    if ($traceEnabled) {
        [Environment]::SetEnvironmentVariable('ISOLATED_DOTNET_SDK_VERIFY_STEP_TRACE_PATH', $previousStepTrace, 'Process')
        [Environment]::SetEnvironmentVariable('ISOLATED_DOTNET_SDK_VERIFY_STEP_SCENARIO', $previousStepScenario, 'Process')
        [Environment]::SetEnvironmentVariable('ISOLATED_DOTNET_SDK_VERIFY_STACK_TRACE_PATH', $previousStackTrace, 'Process')
        [Environment]::SetEnvironmentVariable('ISOLATED_DOTNET_SDK_FAKE_HOST_STACK_TRACE_PATH', $previousStackHostTrace, 'Process')
        [Environment]::SetEnvironmentVariable('ISOLATED_DOTNET_SDK_VERIFY_PARENT_PREWARM_HOST', $previousParentPrewarm, 'Process')
        [Environment]::SetEnvironmentVariable('ISOLATED_DOTNET_SDK_VERIFY_TRACE_PATH', $previousVerifyTrace, 'Process')
        [Environment]::SetEnvironmentVariable('ISOLATED_DOTNET_SDK_FAKE_HOST_TRACE_PATH', $previousHostTrace, 'Process')
        [Environment]::SetEnvironmentVariable('ISOLATED_DOTNET_SDK_VERIFY_CHILD_TRACE_PATH', $previousChildTrace, 'Process')
        [Environment]::SetEnvironmentVariable('ISOLATED_DOTNET_SDK_VERIFY_TRACE_INVOCATION', $previousInvocation, 'Process')
    }
    Remove-Item Env:ISOLATED_DOTNET_SDK_SHARED_FAKE_HOST_ROOT -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}
