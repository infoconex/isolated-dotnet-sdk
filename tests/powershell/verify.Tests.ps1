Describe 'PowerShell isolated SDK verification' {
    BeforeAll {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:ToolScript = Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1'
        $script:HomeVariableName = if ($IsWindows) { 'USERPROFILE' } else { 'HOME' }

        function Add-VerifyTestStep {
            param([string]$Step)
            if ($null -eq $script:VerifyStepTimer) { return }
            $nowMs = $script:VerifyStepTimer.Elapsed.TotalMilliseconds
            $script:VerifyStepRecords.Add([pscustomobject]@{
                    Scope = 'Test'
                    InvocationId = ''
                    Scenario = $script:VerifyStepScenario
                    Step = $Step
                    ElapsedMs = [math]::Round($nowMs - $script:VerifyStepLastMs, 3)
                    CumulativeMs = [math]::Round($nowMs, 3)
                    Utc = [DateTime]::UtcNow.ToString('o')
                })
            $script:VerifyStepLastMs = $nowMs
        }

        function Initialize-VerifyStepInstrumentedTool {
            # Modify only the one case's temporary installed-tool copy.
            # The committed product script and other cases are untouched.
            $content = Get-Content -LiteralPath $script:ToolPath -Raw
            # Git on Windows can check out CRLF. Normalize only the disposable
            # installed-tool copy so source-marker matching is deterministic.
            $content = $content.Replace("`r`n", "`n")
            $markers = @(
                @{ Text = '    $Checks = [System.Collections.Generic.List[object]]::new()'; Before = 'local-proof-enter'; After = '' }
                @{ Text = '    $PreviousMultiLevel = [Environment]::GetEnvironmentVariable(''DOTNET_MULTILEVEL_LOOKUP'', ''Process'')'; Before = 'local-proof-paths-checked'; After = '' }
                @{ Text = '        # Original 1.x and early 2.x hosts cannot enumerate SDKs.'; Before = 'local-proof-environment-ready'; After = '' }
                @{ Text = '        $Inventory = @()'; Before = 'local-proof-inventory-start'; After = '' }
                @{ Text = '            $ExpectedOrigin = [System.IO.Path]::GetFullPath((Join-Path $InstallDirectory ''sdk'')).TrimEnd('; Before = 'local-proof-inventory-validated'; After = '' }
                @{ Text = '            if (-not $FoundVersion) {'; Before = 'local-proof-origin-comparison-complete'; After = '' }
                @{ Text = '                $Checks.Add([pscustomobject]@{ Label = ''SDK inventory''; Status = ''OK''; Detail = "$Version from $ExpectedOrigin" })'; Before = 'local-proof-version-start'; After = '' }
                @{ Text = '                    $Checks.Add([pscustomobject]@{ Label = ''SDK resolution''; Status = ''OK''; Detail = $Version })'; Before = 'local-proof-version-complete'; After = '' }
                @{ Text = '        [Environment]::SetEnvironmentVariable(''DOTNET_MULTILEVEL_LOOKUP'', $PreviousMultiLevel, ''Process'')'; Before = 'local-proof-cleanup-in-progress'; After = '' }
                @{ Text = '$ErrorActionPreference = ''Stop'''; Before = 'product-parameters-bound'; After = 'product-error-preference-set' }
                @{ Text = "`nInstall-ToolIfNeeded`n"; Before = 'bootstrap-start'; After = 'bootstrap-complete' }
                @{ Text = 'Push-Location $SdkRoot'; Before = 'tool-sdk-root-prepared'; After = 'tool-sdk-root-entered' }
                @{ Text = "        Test-IsolatedSdk`n"; Before = 'verify-action-dispatched'; After = 'verify-action-returned' }
                @{ Text = 'function Test-IsolatedSdk {'; Before = ''; After = 'verify-function-enter' }
                @{ Text = "    Write-ToolHeading 'Verify isolated .NET SDK'"; Before = 'local-proof-complete'; After = '' }
                @{ Text = '        # Microsoft lifecycle information is optional; local checks remain authoritative.'; Before = 'classification-error-caught'; After = '' }
                @{ Text = '    if (($Message.StartsWith('; Before = 'error-render-function-enter'; After = '' }
                @{ Text = '        Write-Error -Message $Message -ErrorAction Continue'; Before = 'failure-write-error-start'; After = 'failure-write-error-complete' }
                @{ Text = '        throw $Validation.Failure'; Before = 'verification-failure-thrown'; After = '' }
                @{ Text = '    Write-ToolSuccess "Isolated SDK $SdkVersion verified successfully."'; Before = 'verify-success-render-start'; After = '' }
                @{ Text = '        $Classification = Get-VerifyAuditClassification -Version $SdkVersion'; Before = 'classification-start'; After = 'classification-complete' }
                @{ Text = "    Write-ToolHeading 'SDK information:'"; Before = 'report-sdk-information-start'; After = '' }
                @{ Text = "    Write-ToolHeading 'Installed components:'"; Before = 'report-sdk-information-complete'; After = '' }
                @{ Text = '        # Legacy hosts expose architecture in the RID but not as a separate field.'; Before = 'components-info-native-finished'; After = '' }
                @{ Text = '        # Original 1.x and early 2.x hosts do not support --list-runtimes.'; Before = 'components-info-processed'; After = '' }
                @{ Text = '            $Items = [System.Collections.Generic.List[object]]::new()'; Before = 'components-runtimes-native-finished'; After = '' }
                @{ Text = '            $Result.Runtimes = @($Items | Sort-Object Name, Version)'; Before = 'components-runtimes-parsed'; After = '' }
                @{ Text = '        [Environment]::SetEnvironmentVariable(''DOTNET_MULTILEVEL_LOOKUP'', $PreviousMulti, ''Process'')'; Before = 'components-cleanup-start'; After = '' }
                @{ Text = '        Get-IsolatedSdkComponent -InstallDirectory $InstallDir -DotNetPath $IsolatedDotNet -Version $SdkVersion'; Before = 'components-start'; After = 'components-complete' }
                @{ Text = "    Write-ToolHeading 'Verification:'"; Before = 'report-verification-start'; After = '' }
            )
            foreach ($marker in $markers) {
                $needle = [string]$marker.Text
                if ([regex]::Matches($content, [regex]::Escape($needle)).Count -ne 1) {
                    throw "Verify step instrumentation boundary changed: $needle"
                }
                $prefix = if ($marker.Before) {
                    "Mark-VerifyChildStep '$($marker.Before)'" + [Environment]::NewLine
                }
                else { '' }
                $suffix = if ($marker.After) {
                    [Environment]::NewLine + "Mark-VerifyChildStep '$($marker.After)'"
                }
                else { '' }
                $content = $content.Replace($needle, $prefix + $needle + $suffix)
            }
            [System.IO.File]::WriteAllText(
                $script:ToolPath, $content, [System.Text.UTF8Encoding]::new($false))
        }

        function Invoke-VerifyStackLaunchProbe {
            $probeFile = Join-Path $script:RepositoryRoot 'tests/powershell/Invoke-VerifyLaunchProbe.ps1'
            $hostPath = Join-Path (Join-Path $script:ToolRoot '99.0.100') 'dotnet.exe'
            $reportPath = $env:ISOLATED_DOTNET_SDK_VERIFY_STACK_TRACE_PATH
            $parentReport = Join-Path (Split-Path -Parent $reportPath) 'stack-probe-processes.csv'
            # Balance invocation mechanism, new executable copies, and warm
            # executable reuse across fresh child PowerShell processes.
            $controls = @(
                @{ Mode = 'PowerShellNative'; CopyMode = 'Fresh' }
                @{ Mode = 'DirectProcess'; CopyMode = 'Existing' }
                @{ Mode = 'DirectProcess'; CopyMode = 'Fresh' }
                @{ Mode = 'PowerShellNative'; CopyMode = 'Existing' }
                @{ Mode = 'PowerShellNative'; CopyMode = 'Existing' }
                @{ Mode = 'DirectProcess'; CopyMode = 'Fresh' }
                @{ Mode = 'DirectProcess'; CopyMode = 'Existing' }
                @{ Mode = 'PowerShellNative'; CopyMode = 'Fresh' }
                @{ Mode = 'PowerShellNative'; CopyMode = 'SdkLayout' }
                @{ Mode = 'DirectProcess'; CopyMode = 'SdkLayout' }
                @{ Mode = 'DirectProcess'; CopyMode = 'SdkLayout' }
                @{ Mode = 'PowerShellNative'; CopyMode = 'SdkLayout' }
            )
            foreach ($control in $controls) {
                $mode = $control.Mode
                $copyMode = $control.CopyMode
                $startedUtc = [DateTime]::UtcNow
                $clock = [System.Diagnostics.Stopwatch]::StartNew()
                $output = @(& pwsh -NoProfile -File $probeFile -Mode $mode -CopyMode $copyMode -HostPath $hostPath -ReportPath $reportPath -Iterations 3 2>&1)
                $resultCode = $LASTEXITCODE
                $clock.Stop()
                [pscustomobject]@{
                    Mode = $mode
                    CopyMode = $copyMode
                    StartedUtc = $startedUtc.ToString('o')
                    ChildPwshMs = [math]::Round($clock.Elapsed.TotalMilliseconds, 3)
                    ExitCode = $resultCode
                } | Export-Csv -LiteralPath $parentReport -Append -NoTypeInformation -Encoding utf8
                if ($resultCode -ne 0) {
                    throw "Stack launch control ($mode) failed with $resultCode. Output: $($output -join ' ')"
                }
            }
        }

        function Install-FakeIsolatedHost {
            param(
                [Alias('SdkVersion')]
                [string]$Version = '99.0.100',
                [string]$ReportedVersion = '99.0.100'
            )

            $installDirectory = Join-Path $script:ToolRoot $Version
            New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
            Copy-Item `
                -Path (Join-Path $env:ISOLATED_DOTNET_SDK_SHARED_FAKE_HOST_ROOT '*') `
                -Destination $installDirectory `
                -Recurse `
                -Force
            New-Item -ItemType Directory -Path (Join-Path $installDirectory 'sdk') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $installDirectory 'shared/Microsoft.NETCore.App') -Force | Out-Null
            $env:FAKE_DOTNET_SDK_VERSION = $ReportedVersion
            return $installDirectory
        }

        function Invoke-VerifyTool {
            param([string]$Version = '')
            $env:VERIFY_TARGET_VERSION = $Version
            $env:VERIFY_TOOL_PATH = $script:ToolPath
            Add-VerifyTestStep 'child-parameters-ready'
            $command = @'
function Invoke-RestMethod {
    param([string]$Uri)
    if ($env:VERIFY_METADATA_ROOT) {
        $name = if ($Uri -like "*releases-index.json") { "index.json" } else { "channel.json" }
        $path = Join-Path $env:VERIFY_METADATA_ROOT $name
        if (Test-Path -LiteralPath $path) {
            return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        }
    }
    throw "Synthetic Microsoft metadata unavailable"
}
& $env:VERIFY_TOOL_PATH -Action Verify -SdkVersion $env:VERIFY_TARGET_VERSION
'@
            $tracePath = $env:ISOLATED_DOTNET_SDK_VERIFY_TRACE_PATH
            if (-not [string]::IsNullOrWhiteSpace($tracePath)) {
                # Add child-side milestones only for the opt-in trace path.
                $tracePrefix = @'
function Write-VerifyChildTraceEvent {
    param([string]$EventName, [string]$Detail = '')
    $stamp = [DateTime]::UtcNow.ToString('o')
    $caseId = $env:ISOLATED_DOTNET_SDK_VERIFY_TRACE_CASE
    $invocation = $env:ISOLATED_DOTNET_SDK_VERIFY_TRACE_INVOCATION
    $safeDetail = $Detail.Replace("`t", ' ').Replace("`r", ' ').Replace("`n", ' ')
    [System.IO.File]::AppendAllText(
        $env:ISOLATED_DOTNET_SDK_VERIFY_CHILD_TRACE_PATH,
        "$stamp`t$caseId`t$invocation`t$PID`t$EventName`t$safeDetail" + [Environment]::NewLine)
}
Write-VerifyChildTraceEvent -EventName 'child-command-start'
'@
                $command = $tracePrefix + [Environment]::NewLine + $command
                $command = $command.Replace(
                    '    if ($env:VERIFY_METADATA_ROOT) {',
                    '    Write-VerifyChildTraceEvent -EventName ''metadata-start'' -Detail $Uri' +
                        [Environment]::NewLine + '    if ($env:VERIFY_METADATA_ROOT) {')
                $command = $command.Replace(
                    '            return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json',
                    '            $metadata = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json' +
                        [Environment]::NewLine +
                        '            Write-VerifyChildTraceEvent -EventName ''metadata-success'' -Detail $Uri' +
                        [Environment]::NewLine +
                        '            return $metadata')
                $command = $command.Replace(
                    '    throw "Synthetic Microsoft metadata unavailable"',
                    '    Write-VerifyChildTraceEvent -EventName ''metadata-failure'' -Detail $Uri' +
                        [Environment]::NewLine +
                        '    throw "Synthetic Microsoft metadata unavailable"')
                $command = $command.Replace(
                    '& $env:VERIFY_TOOL_PATH -Action Verify -SdkVersion $env:VERIFY_TARGET_VERSION',
                    'Write-VerifyChildTraceEvent -EventName ''product-entry''' +
                        [Environment]::NewLine +
                        '& $env:VERIFY_TOOL_PATH -Action Verify -SdkVersion $env:VERIFY_TARGET_VERSION' +
                        [Environment]::NewLine +
                        '$verifyExitCode = $LASTEXITCODE' +
                        [Environment]::NewLine +
                        'Write-VerifyChildTraceEvent -EventName ''product-return''' +
                        [Environment]::NewLine +
                        'exit $verifyExitCode')
            }
            if (-not [string]::IsNullOrWhiteSpace($env:ISOLATED_DOTNET_SDK_VERIFY_STEP_TRACE_PATH)) {
                # Buffer monotonic child timestamps; write them only after Verify returns.
                $stepPrefix = @'
$global:VerifyStepState = [pscustomobject]@{
    Timer = [System.Diagnostics.Stopwatch]::StartNew()
    LastMs = 0.0
    Events = [System.Collections.Generic.List[object]]::new()
}
function Mark-VerifyChildStep {
    param([string]$Step)
    # Global state is private to this disposable child pwsh process. Unlike
    # $script: variables, it is shared by the command and the invoked .ps1.
    $state = $global:VerifyStepState
    $nowMs = $state.Timer.Elapsed.TotalMilliseconds
    $state.Events.Add([pscustomobject]@{
        Scope = 'Child'
        InvocationId = $env:ISOLATED_DOTNET_SDK_VERIFY_TRACE_INVOCATION
        Scenario = $env:ISOLATED_DOTNET_SDK_VERIFY_STEP_SCENARIO
        Step = $Step
        ElapsedMs = [math]::Round($nowMs - $state.LastMs, 3)
        CumulativeMs = [math]::Round($nowMs, 3)
        Utc = [DateTime]::UtcNow.ToString('o')
    })
    $state.LastMs = $nowMs
}
Mark-VerifyChildStep 'child-command-start'
'@
                $command = $stepPrefix + [Environment]::NewLine + $command
                $stepChanges = @(
                    @{ Old = 'function Invoke-RestMethod {'; New = "Mark-VerifyChildStep 'metadata-mock-definition'" + [Environment]::NewLine + 'function Invoke-RestMethod {' }
                    @{ Old = '    param([string]$Uri)'; New = '    param([string]$Uri)' + [Environment]::NewLine + "    Mark-VerifyChildStep 'metadata-mock-enter'" }
                    @{ Old = '        $path = Join-Path $env:VERIFY_METADATA_ROOT $name'; New = '        $path = Join-Path $env:VERIFY_METADATA_ROOT $name' + [Environment]::NewLine + "        Mark-VerifyChildStep 'metadata-path-selected'" }
                    @{ Old = '            Write-VerifyChildTraceEvent -EventName ''metadata-success'' -Detail $Uri'; New = "            Mark-VerifyChildStep 'metadata-json-parsed'" + [Environment]::NewLine + '            Write-VerifyChildTraceEvent -EventName ''metadata-success'' -Detail $Uri' }
                    @{ Old = '    Write-VerifyChildTraceEvent -EventName ''metadata-failure'' -Detail $Uri'; New = "    Mark-VerifyChildStep 'metadata-unavailable'" + [Environment]::NewLine + '    Write-VerifyChildTraceEvent -EventName ''metadata-failure'' -Detail $Uri' }
                    @{ Old = 'Write-VerifyChildTraceEvent -EventName ''product-entry'''; New = "Mark-VerifyChildStep 'product-entry'" + [Environment]::NewLine + 'Write-VerifyChildTraceEvent -EventName ''product-entry''' }
                    @{ Old = '$verifyExitCode = $LASTEXITCODE'; New = '$verifyExitCode = $LASTEXITCODE' + [Environment]::NewLine + "Mark-VerifyChildStep 'product-return'" }
                    @{ Old = 'exit $verifyExitCode'; New = "Mark-VerifyChildStep 'child-buffer-flush'" +
                            [Environment]::NewLine +
                            '$global:VerifyStepState.Events | Export-Csv -LiteralPath $env:ISOLATED_DOTNET_SDK_VERIFY_STEP_TRACE_PATH -Append -NoTypeInformation -Encoding utf8' +
                            [Environment]::NewLine + 'exit $verifyExitCode' }
                )
                foreach ($change in $stepChanges) {
                    if (-not $command.Contains($change.Old)) {
                        throw "Verify child step marker changed: $($change.Old)"
                    }
                    $command = $command.Replace($change.Old, $change.New)
                }
                Add-VerifyTestStep 'child-command-instrumented'
            }
            if ([string]::IsNullOrWhiteSpace($tracePath)) {
                $lines = @(& pwsh -NoProfile -Command $command 2>&1)
                $script:VerifyExitCode = $LASTEXITCODE
            }
            else {
                $startedUtc = [DateTime]::UtcNow
                $invocationId = [guid]::NewGuid().ToString('N')
                $previousInvocation = [Environment]::GetEnvironmentVariable(
                    'ISOLATED_DOTNET_SDK_VERIFY_TRACE_INVOCATION', 'Process')
                $timer = [System.Diagnostics.Stopwatch]::StartNew()
                try {
                    $env:ISOLATED_DOTNET_SDK_VERIFY_TRACE_INVOCATION = $invocationId
                    $lines = @(& pwsh -NoProfile -Command $command 2>&1)
                    $exitCode = $LASTEXITCODE
                }
                finally {
                    $timer.Stop()
                    [Environment]::SetEnvironmentVariable(
                        'ISOLATED_DOTNET_SDK_VERIFY_TRACE_INVOCATION', $previousInvocation, 'Process')
                }
                $script:VerifyExitCode = $exitCode
                Add-VerifyTestStep 'child-process-completed'
                [pscustomobject]@{
                    StartedUtc = $startedUtc.ToString('o')
                    EndedUtc = [DateTime]::UtcNow.ToString('o')
                    CaseId = $env:ISOLATED_DOTNET_SDK_VERIFY_TRACE_CASE
                    InvocationId = $invocationId
                    SdkVersion = $Version
                    ChildPwshMs = [math]::Round($timer.Elapsed.TotalMilliseconds, 2)
                    ExitCode = $exitCode
                } | Export-Csv -LiteralPath $tracePath -Append -NoTypeInformation -Encoding utf8
                Add-VerifyTestStep 'child-invocation-recorded'
            }
            return $lines
        }
    }

    BeforeEach {
        $script:VerifyStepTimer = $null
        $script:VerifyStepRecords = $null
        $script:VerifyStepLastMs = 0.0
        $script:VerifyStepScenario = 'setup'
        if (-not [string]::IsNullOrWhiteSpace($env:ISOLATED_DOTNET_SDK_VERIFY_STEP_TRACE_PATH)) {
            $script:VerifyStepTimer = [System.Diagnostics.Stopwatch]::StartNew()
            $script:VerifyStepRecords = [System.Collections.Generic.List[object]]::new()
            Add-VerifyTestStep 'beforeeach-start'
        }
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-verify-tests-{0}" -f [guid]::NewGuid())
        $script:TestHome = Join-Path $script:TestRoot 'home'
        $script:ToolRoot = Join-Path $script:TestHome 'dotnet-sdks'
        $script:ToolPath = Join-Path $script:ToolRoot 'isolated-dotnet-sdk.ps1'
        $script:SourceCopy = Join-Path $script:TestRoot 'isolated-dotnet-sdk-source.ps1'
        $script:OriginalHomeValue = [Environment]::GetEnvironmentVariable($script:HomeVariableName, 'Process')
        Add-VerifyTestStep 'test-paths-prepared'
        $script:OriginalTraceCase = [Environment]::GetEnvironmentVariable('ISOLATED_DOTNET_SDK_VERIFY_TRACE_CASE', 'Process')
        if (-not [string]::IsNullOrWhiteSpace($env:ISOLATED_DOTNET_SDK_VERIFY_TRACE_PATH)) {
            $env:ISOLATED_DOTNET_SDK_VERIFY_TRACE_CASE = [IO.Path]::GetFileName($script:TestRoot)
        }

        # Most Verify scenarios exercise an already-installed tool in a real child process.
        # Install directly in this unique test HOME instead of running a second,
        # unrelated bootstrap process before each test.
        New-Item -ItemType Directory -Path $script:ToolRoot -Force | Out-Null
        Copy-Item -LiteralPath $script:ToolScript -Destination $script:ToolPath -Force -ErrorAction Stop
        Add-VerifyTestStep 'tool-fixture-copied'
        Test-Path -LiteralPath $script:ToolPath -PathType Leaf | Should -BeTrue
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:TestHome, 'Process')
        Add-VerifyTestStep 'beforeeach-complete'
    }

    AfterEach {
        Add-VerifyTestStep 'aftereach-start'
        [Environment]::SetEnvironmentVariable('ISOLATED_DOTNET_SDK_VERIFY_TRACE_CASE', $script:OriginalTraceCase, 'Process')
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:OriginalHomeValue, 'Process')
        Remove-Item Env:FAKE_DOTNET_EXIT_CODE -ErrorAction SilentlyContinue
        Remove-Item Env:ISOLATED_DOTNET_SDK_VERIFY_STEP_SCENARIO -ErrorAction SilentlyContinue
        foreach ($name in @('FAKE_DOTNET_LEGACY_HOST', 'FAKE_DOTNET_REQUIRE_PINNED_VERSION', 'FAKE_DOTNET_LEGACY_BASE_PATH', 'FAKE_DOTNET_LEGACY_EXTRA_BASE_PATH', 'FAKE_DOTNET_LEGACY_INFO_EXIT_CODE', 'FAKE_DOTNET_LEGACY_MISSING_BASE_PATH', 'FAKE_DOTNET_LEGACY_EXTRA_VERSION', 'FAKE_DOTNET_LEGACY_SUPPRESS_VERSION', 'FAKE_DOTNET_LEGACY_RID', 'FAKE_DOTNET_SDK_VERSION', 'FAKE_DOTNET_SDK_ORIGIN', 'FAKE_DOTNET_RESOLVED_VERSION', 'FAKE_DOTNET_EXPECT_MULTILEVEL_LOOKUP', 'FAKE_DOTNET_FORBIDDEN_WORK_DIR', 'VERIFY_METADATA_ROOT', 'VERIFY_TOOL_PATH', 'VERIFY_TARGET_VERSION', 'FAKE_DOTNET_EXTRA_RUNTIME_ROOT', 'FAKE_DOTNET_LEGACY_INFO', 'FAKE_DOTNET_RUNTIME_EXIT_CODE', 'FAKE_DOTNET_RUNTIME_PROBE_MARKER')) {
            Remove-Item "Env:$name" -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
        Add-VerifyTestStep 'aftereach-cleanup-complete'
        if ($null -ne $script:VerifyStepRecords) {
            $script:VerifyStepRecords |
                Export-Csv -LiteralPath $env:ISOLATED_DOTNET_SDK_VERIFY_STEP_TRACE_PATH -Append -NoTypeInformation -Encoding utf8
            $script:VerifyStepRecords = $null
            $script:VerifyStepTimer = $null
        }
    }

    It 'preserves success and failure exit codes in optional Verify tracing' -Tag VerifyStepProfile {
        $previousTrace = [Environment]::GetEnvironmentVariable('ISOLATED_DOTNET_SDK_VERIFY_TRACE_PATH', 'Process')
        $previousChildTrace = [Environment]::GetEnvironmentVariable('ISOLATED_DOTNET_SDK_VERIFY_CHILD_TRACE_PATH', 'Process')
        try {
            if ($null -ne $script:VerifyStepRecords) {
                Add-VerifyTestStep 'scenario-start'
                Initialize-VerifyStepInstrumentedTool
                Add-VerifyTestStep 'tool-copy-instrumented'
            }
            # Exercise the actual traced child command even in an ordinary CI run.
            $tracePath = if ([string]::IsNullOrWhiteSpace($previousTrace)) {
                Join-Path $script:TestRoot 'verify-invocations.csv'
            }
            else {
                $previousTrace
            }
            $childTracePath = if ([string]::IsNullOrWhiteSpace($previousChildTrace)) {
                Join-Path $script:TestRoot 'verify-child-events.tsv'
            }
            else {
                $previousChildTrace
            }
            $env:ISOLATED_DOTNET_SDK_VERIFY_TRACE_PATH = $tracePath
            $env:ISOLATED_DOTNET_SDK_VERIFY_CHILD_TRACE_PATH = $childTracePath
            Add-VerifyTestStep 'trace-paths-ready'
            $previousCount = if (Test-Path -LiteralPath $tracePath -PathType Leaf) {
                @(Import-Csv -LiteralPath $tracePath).Count
            }
            else {
                0
            }

            $script:VerifyStepScenario = 'missing-sdk'
            if ($null -ne $script:VerifyStepRecords) {
                $env:ISOLATED_DOTNET_SDK_VERIFY_STEP_SCENARIO = $script:VerifyStepScenario
            }
            Add-VerifyTestStep 'missing-sdk-invocation-start'
            $missing = @(Invoke-VerifyTool -Version '99.0.100')
            Add-VerifyTestStep 'missing-sdk-invocation-complete'
            $script:VerifyExitCode | Should -Be 1
            ($missing -join [Environment]::NewLine) | Should -Match 'not installed'
            Add-VerifyTestStep 'missing-sdk-assertions-complete'

            $script:VerifyStepScenario = 'healthy-sdk'
            if ($null -ne $script:VerifyStepRecords) {
                $env:ISOLATED_DOTNET_SDK_VERIFY_STEP_SCENARIO = $script:VerifyStepScenario
            }
            Add-VerifyTestStep 'healthy-fixture-install-start'
            Install-FakeIsolatedHost -Version '99.0.100' | Out-Null
            Add-VerifyTestStep 'healthy-fixture-install-complete'
            $healthy = @(Invoke-VerifyTool -Version '99.0.100')
            Add-VerifyTestStep 'healthy-sdk-invocation-complete'
            if ($null -ne $script:VerifyStepRecords -and $script:VerifyExitCode -ne 0) {
                # On an unexpected failure keep the child output outside the disposable
                # HOME and print it before Pester reports the failed exit-code assertion.
                $errorText = ($healthy | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
                $diagnosticPath = Join-Path (Split-Path -Parent $env:ISOLATED_DOTNET_SDK_VERIFY_STEP_TRACE_PATH) 'unexpected-healthy-output.txt'
                [System.IO.File]::WriteAllText($diagnosticPath, $errorText)
                Write-Information 'Unexpected healthy Verify child output:' -InformationAction Continue
                Write-Information $errorText -InformationAction Continue

                # Diagnostic-only independent launch. This is deliberately after
                # the measured child process, and runs only if that process fails.
                # Keep native probe events separate from the normal trace.
                $hostExe = Join-Path (Join-Path $script:ToolRoot '99.0.100') 'dotnet.exe'
                $probeLines = [System.Collections.Generic.List[string]]::new()
                $probeLines.Add("Host exists: $(Test-Path -LiteralPath $hostExe -PathType Leaf)")
                $probeLines.Add("PowerShell: $($PSVersionTable.PSVersion)")
                $probeLines.Add("Host file: $hostExe")
                if (Test-Path -LiteralPath $hostExe -PathType Leaf) {
                    $probeLines.Add("Host length: $((Get-Item -LiteralPath $hostExe).Length)")
                    $probeProcess = $null
                    $previousHostTrace = [Environment]::GetEnvironmentVariable(
                        'ISOLATED_DOTNET_SDK_FAKE_HOST_TRACE_PATH', 'Process')
                    try {
                        $env:ISOLATED_DOTNET_SDK_FAKE_HOST_TRACE_PATH = Join-Path (
                            Split-Path -Parent $diagnosticPath) 'probe-fake-host-events.tsv'
                        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
                        $startInfo.FileName = $hostExe
                        $startInfo.Arguments = '--list-sdks'
                        $startInfo.UseShellExecute = $false
                        $startInfo.RedirectStandardOutput = $true
                        $startInfo.RedirectStandardError = $true
                        $startInfo.CreateNoWindow = $true
                        $probeProcess = [System.Diagnostics.Process]::Start($startInfo)
                        $stdout = $probeProcess.StandardOutput.ReadToEnd()
                        $stderr = $probeProcess.StandardError.ReadToEnd()
                        $probeProcess.WaitForExit()
                        $probeLines.Add("Direct .NET launch exit: $($probeProcess.ExitCode)")
                        $probeLines.Add("Direct .NET stdout: $stdout")
                        $probeLines.Add("Direct .NET stderr: $stderr")
                    }
                    catch {
                        $probeLines.Add("Direct .NET launch exception: $($_.Exception.ToString())")
                    }
                    finally {
                        if ($null -ne $probeProcess) { $probeProcess.Dispose() }
                        [Environment]::SetEnvironmentVariable(
                            'ISOLATED_DOTNET_SDK_FAKE_HOST_TRACE_PATH', $previousHostTrace, 'Process')
                    }
                }
                $probeText = $probeLines -join [Environment]::NewLine
                [System.IO.File]::AppendAllText(
                    $diagnosticPath, [Environment]::NewLine + $probeText)
                Write-Information $probeText -InformationAction Continue
            }
            if (-not [string]::IsNullOrWhiteSpace($env:ISOLATED_DOTNET_SDK_VERIFY_STACK_TRACE_PATH)) {
                $script:VerifyStepScenario = 'stack-probe'
                Add-VerifyTestStep 'stack-launch-controls-start'
                try {
                    Invoke-VerifyStackLaunchProbe
                }
                finally {
                    Add-VerifyTestStep 'stack-launch-controls-complete'
                    $script:VerifyStepScenario = 'healthy-sdk'
                }
            }
            $script:VerifyExitCode | Should -Be 0
            ($healthy -join [Environment]::NewLine) | Should -Match 'verified successfully'
            Add-VerifyTestStep 'healthy-sdk-assertions-complete'

            $newCalls = @(Import-Csv -LiteralPath $tracePath | Select-Object -Skip $previousCount)
            $newCalls.Count | Should -Be 2
            $newCalls[0].ExitCode | Should -Be '1'
            $newCalls[1].ExitCode | Should -Be '0'
            (Get-Content -LiteralPath $childTracePath -Raw) | Should -Match 'product-return'
            Add-VerifyTestStep 'trace-assertions-complete'
        }
        finally {
            [Environment]::SetEnvironmentVariable(
                'ISOLATED_DOTNET_SDK_VERIFY_TRACE_PATH', $previousTrace, 'Process')
            [Environment]::SetEnvironmentVariable(
                'ISOLATED_DOTNET_SDK_VERIFY_CHILD_TRACE_PATH', $previousChildTrace, 'Process')
        }
    }

    It 'reports a healthy exact isolated SDK without mutating it' {
        $version = '99.0.100'
        $installDirectory = Install-FakeIsolatedHost -SdkVersion $version -ReportedVersion $version
        $sentinelPath = Join-Path $installDirectory 'verify-sentinel.txt'
        Set-Content -LiteralPath $sentinelPath -Value 'preserve-me' -NoNewline
        $fileCountBefore = @(Get-ChildItem -LiteralPath $installDirectory -File -Recurse -Force).Count

        $verifyOutput = @(Invoke-VerifyTool -Version $version)

        $script:VerifyExitCode | Should -Be 0
        ($verifyOutput -join [Environment]::NewLine) | Should -Match "Isolated SDK $([regex]::Escape($version)) verified successfully\."
        $outputText = $verifyOutput -join [Environment]::NewLine
        $outputText | Should -Match 'SDK information:'
        $outputText | Should -Match 'SDK version\s+99\.0\.100'
        $outputText | Should -Match 'Installed components:'
        $outputText | Should -Match 'Host version\s+99\.0\.9'
        $outputText | Should -Match 'Architecture\s+x64'
        $outputText | Should -Match 'Runtime identifier\s+win10-x64'
        $outputText | Should -Match 'Microsoft\.NETCore\.App\s+99\.0\.9'
        $outputText | Should -Match 'SDK inventory\s+OK\s+Exact SDK found in isolated installation'
        $outputText | Should -Match 'SDK resolution\s+OK\s+Correct SDK selected'
        $outputText | Should -Not -Match '(?m)^Location:'
        (Get-Content -LiteralPath $sentinelPath -Raw) | Should -Be 'preserve-me'
        @(Get-ChildItem -LiteralPath $installDirectory -File -Recurse -Force).Count | Should -Be $fileCountBefore
    }

    It 'bootstrapped Verify succeeds when optional modern runtime diagnostics fail' {
        $version = '99.0.100'
        Install-FakeIsolatedHost -Version $version -ReportedVersion $version | Out-Null
        $env:FAKE_DOTNET_RUNTIME_EXIT_CODE = '72'
        $env:FAKE_DOTNET_RUNTIME_PROBE_MARKER = Join-Path $script:TestRoot 'runtime-probed.txt'

        # Exercise the real bootstrap boundary: the installed tool must be absent
        # when the source entry point starts, then installed by that process.
        Copy-Item -LiteralPath $script:ToolScript -Destination $script:SourceCopy -Force
        Remove-Item -LiteralPath $script:ToolPath -Force
        Test-Path -LiteralPath $script:ToolPath | Should -BeFalse

        $output = @(& pwsh -NoProfile -File $script:SourceCopy -Action Verify -SdkVersion $version 2>&1)

        Test-Path -LiteralPath $script:ToolPath -PathType Leaf | Should -BeTrue

        $LASTEXITCODE | Should -Be 0
        $text = $output -join [Environment]::NewLine
        $text | Should -Match 'Isolated SDK 99\.0\.100 verified successfully\.'
        $text | Should -Match 'SDK inventory\s+OK'
        $text | Should -Match 'SDK resolution\s+OK'
        $text | Should -Match '(?s)\.NET runtimes:\s+Unavailable'
        Test-Path -LiteralPath $env:FAKE_DOTNET_RUNTIME_PROBE_MARKER | Should -BeTrue
    }

    It 'bootstrapped early 2.x Verify skips unsupported runtime probing and exits zero' {
        $version = '2.1.105'
        $target = Install-FakeIsolatedHost -Version $version -ReportedVersion $version
        New-Item -ItemType Directory -Path (Join-Path (Join-Path $target 'sdk') $version) -Force | Out-Null
        $env:FAKE_DOTNET_LEGACY_HOST = 'true'
        $env:FAKE_DOTNET_SDK_VERSION = $version
        $env:FAKE_DOTNET_RUNTIME_PROBE_MARKER = Join-Path $script:TestRoot 'runtime-probed.txt'

        # Exercise the real bootstrap boundary: the installed tool must be absent
        # when the source entry point starts, then installed by that process.
        Copy-Item -LiteralPath $script:ToolScript -Destination $script:SourceCopy -Force
        Remove-Item -LiteralPath $script:ToolPath -Force
        Test-Path -LiteralPath $script:ToolPath | Should -BeFalse

        $output = @(& pwsh -NoProfile -File $script:SourceCopy -Action Verify -SdkVersion $version 2>&1)

        Test-Path -LiteralPath $script:ToolPath -PathType Leaf | Should -BeTrue

        $LASTEXITCODE | Should -Be 0
        $text = $output -join [Environment]::NewLine
        $text | Should -Match 'Isolated SDK 2\.1\.105 verified successfully\.'
        $text | Should -Match 'SDK origin\s+OK'
        $text | Should -Match 'SDK resolution\s+OK'
        $text | Should -Match '(?s)\.NET runtimes:\s+Unavailable'
        Test-Path -LiteralPath $env:FAKE_DOTNET_RUNTIME_PROBE_MARKER | Should -BeFalse
    }

    It 'reads legacy Host information and infers architecture from RID' {
        $version = '2.2.207'
        Install-FakeIsolatedHost -Version $version -ReportedVersion $version | Out-Null
        $env:FAKE_DOTNET_LEGACY_INFO = 'true'

        $verifyOutput = @(Invoke-VerifyTool -Version $version)

        $script:VerifyExitCode | Should -Be 0
        $outputText = $verifyOutput -join [Environment]::NewLine
        $outputText | Should -Match 'Host version\s+99\.0\.9'
        $outputText | Should -Match 'Architecture\s+x64'
        $outputText | Should -Match 'Runtime identifier\s+win10-x64'
        $outputText | Should -Match 'Isolated SDK 2\.2\.207 verified successfully'
    }

    It 'fails clearly when the selected version is not installed' {
        $version = '99.0.100'

        $verifyOutput = @(Invoke-VerifyTool -Version $version)

        $script:VerifyExitCode | Should -Not -Be 0
        ($verifyOutput -join [Environment]::NewLine) | Should -Match "Isolated SDK $([regex]::Escape($version)) is not installed under"
    }

    It 'fails clearly when the installation directory has no host' {
        $version = '99.0.100'
        $installDirectory = Join-Path $script:ToolRoot $version
        New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null

        $verifyOutput = @(Invoke-VerifyTool -Version $version)

        $script:VerifyExitCode | Should -Not -Be 0
        ($verifyOutput -join [Environment]::NewLine) | Should -Match 'expected dotnet host was not found'
        Test-Path -LiteralPath $installDirectory -PathType Container | Should -BeTrue
    }

    It 'fails with launch context when the host cannot be launched' {
        $version = '99.0.100'
        $installDirectory = Join-Path $script:ToolRoot $version
        $hostPath = Join-Path $installDirectory 'dotnet.exe'
        New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null

        # Lock a valid executable instead of launching malformed executable
        # bytes, which opens blocking "Unsupported 16-Bit Application" dialogs
        # on Windows during otherwise unattended test runs.
        $fixtureHost = Join-Path $env:ISOLATED_DOTNET_SDK_SHARED_FAKE_HOST_ROOT 'dotnet.exe'
        Copy-Item -LiteralPath $fixtureHost -Destination $hostPath
        $exclusiveLock = [System.IO.File]::Open(
            $hostPath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None)

        try {
            $verifyOutput = @(Invoke-VerifyTool -Version $version)

            $script:VerifyExitCode | Should -Not -Be 0
            ($verifyOutput -join [Environment]::NewLine) | Should -Match "Unable to launch isolated SDK $([regex]::Escape($version)) host"
            Test-Path -LiteralPath $hostPath -PathType Leaf | Should -BeTrue
        }
        finally {
            $exclusiveLock.Dispose()
        }
    }

    It 'fails with the native exit code when the host reports execution failure' {
        $version = '99.0.100'
        Install-FakeIsolatedHost -SdkVersion $version -ReportedVersion $version | Out-Null
        $env:FAKE_DOTNET_EXIT_CODE = '73'

        $verifyOutput = @(Invoke-VerifyTool -Version $version)

        $script:VerifyExitCode | Should -Not -Be 0
        ($verifyOutput -join [Environment]::NewLine) | Should -Match "Unable to verify isolated SDK $([regex]::Escape($version)) with exit code 73\."
    }

    It 'fails when the isolated host does not report the requested SDK version' {
        $version = '99.0.100'
        Install-FakeIsolatedHost -SdkVersion $version -ReportedVersion '98.0.100' | Out-Null

        $verifyOutput = @(Invoke-VerifyTool -Version $version)

        $script:VerifyExitCode | Should -Not -Be 0
        ($verifyOutput -join [Environment]::NewLine) | Should -Match "Isolated SDK $([regex]::Escape($version)) failed verification: the host did not report SDK $([regex]::Escape($version))\."
    }

    It 'rejects an identical SDK version reported from another location' {
        $version = '99.0.100'
        Install-FakeIsolatedHost -Version $version -ReportedVersion $version | Out-Null
        $wrongOrigin = Join-Path $script:TestRoot 'system/sdk'
        New-Item -ItemType Directory -Path $wrongOrigin -Force | Out-Null
        $env:FAKE_DOTNET_SDK_ORIGIN = $wrongOrigin

        $verifyOutput = @(Invoke-VerifyTool -Version $version)
        $script:VerifyExitCode | Should -Not -Be 0
        ($verifyOutput -join [Environment]::NewLine) | Should -Match 'was not reported from'
        ($verifyOutput -join [Environment]::NewLine) | Should -Match 'SDK inventory'
    }

    It 'rejects missing isolated SDK origin directory even when a host reports that path' {
        $version = '99.0.100'
        $installDirectory = Install-FakeIsolatedHost -Version $version -ReportedVersion $version
        Remove-Item -LiteralPath (Join-Path $installDirectory 'sdk') -Recurse -Force

        $verifyOutput = @(Invoke-VerifyTool -Version $version)
        $script:VerifyExitCode | Should -Not -Be 0
        ($verifyOutput -join [Environment]::NewLine) | Should -Match 'SDK inventory'
        ($verifyOutput -join [Environment]::NewLine) | Should -Match 'was not reported from'
    }

    It 'rejects --version mismatch and preserves its own failure context' {
        $version = '99.0.100'
        Install-FakeIsolatedHost -Version $version -ReportedVersion $version | Out-Null
        $env:FAKE_DOTNET_RESOLVED_VERSION = '98.0.100'

        $verifyOutput = @(Invoke-VerifyTool -Version $version)
        $script:VerifyExitCode | Should -Not -Be 0
        ($verifyOutput -join [Environment]::NewLine) | Should -Match '--version resolved 98.0.100 instead of 99.0.100'
    }

    It 'forces single-location lookup and ignores ambient global.json' {
        $version = '99.0.100'
        Install-FakeIsolatedHost -Version $version -ReportedVersion $version | Out-Null
        Set-Content -LiteralPath (Join-Path $script:ToolRoot 'global.json') -Value '{ "sdk": {"version": "1.0.100"} }'
        $env:DOTNET_MULTILEVEL_LOOKUP = '1'
        $env:FAKE_DOTNET_EXPECT_MULTILEVEL_LOOKUP = '0'
        $env:FAKE_DOTNET_FORBIDDEN_WORK_DIR = $script:ToolRoot

        try {
            $verifyOutput = @(Invoke-VerifyTool -Version $version)
            $script:VerifyExitCode | Should -Be 0
            ($verifyOutput -join [Environment]::NewLine) | Should -Match 'verified successfully'
            $env:DOTNET_MULTILEVEL_LOOKUP | Should -Be '1'
        }
        finally {
            Remove-Item Env:DOTNET_MULTILEVEL_LOOKUP -ErrorAction SilentlyContinue
        }
    }

    It 'shows shared Audit classification from deterministic Microsoft metadata' {
        $version = '99.0.100'
        Install-FakeIsolatedHost -Version $version -ReportedVersion $version | Out-Null
        $metadata = Join-Path $script:TestRoot 'metadata'
        New-Item -ItemType Directory -Path $metadata -Force | Out-Null
        $env:VERIFY_METADATA_ROOT = $metadata
        @'
{"releases-index":[{"channel-version":"99.0","latest-sdk":"99.0.200","support-phase":"maintenance","release-type":"lts","eol-date":"2030-01-01","releases.json":"https://example.invalid/99.0.json"}]}
'@ | Set-Content -LiteralPath (Join-Path $metadata 'index.json')
        @'
{"releases":[{"release-date":"2026-01-01","sdk":{"version":"99.0.100"}},{"release-date":"2026-04-01","sdk":{"version":"99.0.200"}}]}
'@ | Set-Content -LiteralPath (Join-Path $metadata 'channel.json')

        $verifyOutput = @(Invoke-VerifyTool -Version $version)
        $script:VerifyExitCode | Should -Be 0
        $outputText = $verifyOutput -join [Environment]::NewLine
        $outputText | Should -Match 'Support type\s+LTS'
        $outputText | Should -Match 'Status\s+Maintenance'
        $outputText | Should -Match 'SDK release date\s+2026-01-01'
        $outputText | Should -Match 'Channel EOS date\s+2030-01-01'
        $outputText | Should -Match 'Update available\s+99\.0\.200'
        $outputText.Contains([char]27) | Should -BeFalse
    }

    It 'excludes system runtimes from the isolated component inventory' {
        $version = '99.0.100'
        Install-FakeIsolatedHost -Version $version -ReportedVersion $version | Out-Null
        $unrelated = Join-Path $script:TestRoot 'system/shared/Microsoft.AspNetCore.App'
        New-Item -ItemType Directory -Path $unrelated -Force | Out-Null
        $env:FAKE_DOTNET_EXTRA_RUNTIME_ROOT = $unrelated

        $verifyOutput = @(Invoke-VerifyTool -Version $version)
        $script:VerifyExitCode | Should -Be 0
        $outputText = $verifyOutput -join [Environment]::NewLine
        $outputText | Should -Match 'Microsoft\.NETCore\.App\s+99\.0\.9'
        $outputText | Should -Not -Match 'Microsoft\.AspNetCore\.App'
    }

    It 'requires an exact version for Verify' {
        $verifyOutput = @(Invoke-VerifyTool)

        $script:VerifyExitCode | Should -Not -Be 0
        ($verifyOutput -join [Environment]::NewLine) | Should -Match '-SdkVersion is required with -Action Verify\.'
    }

    It 'rejects invalid exact-version syntax for Verify' {
        $verifyOutput = @(Invoke-VerifyTool -Version 'invalid/version')

        $script:VerifyExitCode | Should -Not -Be 0
        ($verifyOutput -join [Environment]::NewLine) | Should -Match 'Invalid SDK version: invalid/version'
    }

    # Historical hosts deliberately reject --list-sdks and --list-runtimes.
    # Real subprocesses exercise the same CLI entry point as modern Verify.
    It 'verifies exact isolated 1.x SDK hosts without unsupported inventory commands' {
        foreach ($version in @('1.0.4', '1.1.5', '1.1.14')) {
            $directory = Install-FakeIsolatedHost -Version $version -ReportedVersion $version
            New-Item -ItemType Directory -Path (Join-Path (Join-Path $directory 'sdk') $version) -Force | Out-Null
            $env:FAKE_DOTNET_LEGACY_HOST = 'true'
            $env:FAKE_DOTNET_REQUIRE_PINNED_VERSION = 'true'
            $env:FAKE_DOTNET_SDK_VERSION = $version
            $env:DOTNET_MULTILEVEL_LOOKUP = '1'
            $originalRoot = $env:DOTNET_ROOT
            try {
                $text = (Invoke-VerifyTool -Version $version) -join [Environment]::NewLine
                $script:VerifyExitCode | Should -Be 0
                $text | Should -Match 'SDK resolution\s+OK\s+Correct SDK selected'
                $text | Should -Match 'SDK origin\s+OK\s+Exact SDK Base Path in isolated installation'
                $text | Should -Not -Match 'SDK inventory'
                $text | Should -Not -Match 'Unknown option: --list-sdks'
                $text | Should -Match 'Host version\s+Unavailable'
                $text | Should -Match 'Runtime identifier\s+Unavailable'
                $text | Should -Match '(?s)\.NET runtimes:\s+Unavailable'
                $text | Should -Match 'Release/lifecycle   Unavailable'
                $env:DOTNET_MULTILEVEL_LOOKUP | Should -Be '1'
                $env:DOTNET_ROOT | Should -Be $originalRoot
            }
            finally {
                Remove-Item Env:DOTNET_MULTILEVEL_LOOKUP -ErrorAction SilentlyContinue
                [Environment]::SetEnvironmentVariable('DOTNET_ROOT', $originalRoot, 'Process')
            }
        }
    }

    It 'rejects missing, wrong, or ambiguous exact legacy --version output' {
        $version = '1.0.4'
        $directory = Install-FakeIsolatedHost -Version $version -ReportedVersion $version
        New-Item -ItemType Directory -Path (Join-Path $directory "sdk/$version") -Force | Out-Null
        $env:FAKE_DOTNET_LEGACY_HOST = 'true'
        $env:FAKE_DOTNET_RESOLVED_VERSION = '1.1.14'
        $text = (Invoke-VerifyTool -Version $version) -join [Environment]::NewLine
        $script:VerifyExitCode | Should -Not -Be 0
        $text | Should -Match 'SDK resolution\s+FAIL'
        $env:FAKE_DOTNET_RESOLVED_VERSION = $version
        $env:FAKE_DOTNET_LEGACY_EXTRA_VERSION = $version
        $text = (Invoke-VerifyTool -Version $version) -join [Environment]::NewLine
        $script:VerifyExitCode | Should -Not -Be 0
        $text | Should -Match 'SDK resolution\s+FAIL'
        Remove-Item Env:FAKE_DOTNET_LEGACY_EXTRA_VERSION -ErrorAction SilentlyContinue
        $env:FAKE_DOTNET_LEGACY_SUPPRESS_VERSION = 'true'
        $text = (Invoke-VerifyTool -Version $version) -join [Environment]::NewLine
        $script:VerifyExitCode | Should -Not -Be 0
        $text | Should -Match 'SDK resolution\s+FAIL'
    }

    It 'rejects nonzero legacy host command exits' {
        $version = '1.1.5'
        $directory = Install-FakeIsolatedHost -Version $version -ReportedVersion $version
        New-Item -ItemType Directory -Path (Join-Path $directory "sdk/$version") -Force | Out-Null
        $env:FAKE_DOTNET_LEGACY_HOST = 'true'
        $env:FAKE_DOTNET_EXIT_CODE = '73'
        $text = (Invoke-VerifyTool -Version $version) -join [Environment]::NewLine
        $script:VerifyExitCode | Should -Not -Be 0
        $text | Should -Match '\.NET host\s+FAIL'
        Remove-Item Env:FAKE_DOTNET_EXIT_CODE -ErrorAction SilentlyContinue
        $env:FAKE_DOTNET_LEGACY_INFO_EXIT_CODE = '74'
        $text = (Invoke-VerifyTool -Version $version) -join [Environment]::NewLine
        $script:VerifyExitCode | Should -Not -Be 0
        $text | Should -Match 'SDK origin\s+FAIL'
        $text | Should -Match '--info exited with code 74'
    }

    It 'fails closed for missing, empty, ambiguous, and system-only SDK Base Paths' {
        $version = '1.1.14'
        $directory = Install-FakeIsolatedHost -Version $version -ReportedVersion $version
        New-Item -ItemType Directory -Path (Join-Path $directory "sdk/$version") -Force | Out-Null
        $env:FAKE_DOTNET_LEGACY_HOST = 'true'
        $env:FAKE_DOTNET_LEGACY_MISSING_BASE_PATH = 'true'
        $text = (Invoke-VerifyTool -Version $version) -join [Environment]::NewLine
        $script:VerifyExitCode | Should -Not -Be 0
        $text | Should -Match 'SDK origin\s+FAIL'
        Remove-Item Env:FAKE_DOTNET_LEGACY_MISSING_BASE_PATH -ErrorAction SilentlyContinue

        $env:FAKE_DOTNET_LEGACY_BASE_PATH = 'relative/sdk/1.1.14'
        $text = (Invoke-VerifyTool -Version $version) -join [Environment]::NewLine
        $script:VerifyExitCode | Should -Not -Be 0
        $text | Should -Match 'SDK origin\s+FAIL'

        Remove-Item Env:FAKE_DOTNET_LEGACY_BASE_PATH -ErrorAction SilentlyContinue
        $env:FAKE_DOTNET_LEGACY_EXTRA_BASE_PATH = Join-Path $directory "sdk/$version"
        $text = (Invoke-VerifyTool -Version $version) -join [Environment]::NewLine
        $script:VerifyExitCode | Should -Not -Be 0
        $text | Should -Match 'SDK origin\s+FAIL'

        Remove-Item Env:FAKE_DOTNET_LEGACY_EXTRA_BASE_PATH -ErrorAction SilentlyContinue
        $system = Join-Path $script:TestRoot 'system/sdk/1.1.14'
        New-Item -ItemType Directory -Path $system -Force | Out-Null
        $env:FAKE_DOTNET_LEGACY_BASE_PATH = $system
        $text = (Invoke-VerifyTool -Version $version) -join [Environment]::NewLine
        $script:VerifyExitCode | Should -Not -Be 0
        $text | Should -Match 'SDK origin\s+FAIL'
        $text | Should -Match 'does not match the isolated directory'
    }

    It 'rejects an absent installed legacy SDK directory even if the host claims that version' {
        $version = '1.0.4'
        Install-FakeIsolatedHost -Version $version -ReportedVersion $version | Out-Null
        $env:FAKE_DOTNET_LEGACY_HOST = 'true'
        $text = (Invoke-VerifyTool -Version $version) -join [Environment]::NewLine
        $script:VerifyExitCode | Should -Not -Be 0
        $text | Should -Match 'SDK origin\s+FAIL'
    }

    It 'verifies early 2.x isolated hosts via exact legacy Base Path instead of inventory' -ForEach @(
        @{ Version = '2.0.3' }
        @{ Version = '2.1.105' }
    ) {
        $target = Install-FakeIsolatedHost -Version $Version -ReportedVersion $Version
        New-Item -ItemType Directory -Path (Join-Path (Join-Path $target 'sdk') $Version) -Force | Out-Null
        $env:FAKE_DOTNET_LEGACY_HOST = 'true'
        $result = @(Invoke-VerifyTool -Version $Version)
        $script:VerifyExitCode | Should -Be 0
        ($result -join [Environment]::NewLine) | Should -Match 'SDK origin\s+OK'
        ($result -join [Environment]::NewLine) | Should -Not -Match 'SDK inventory\s+FAIL'
    }

    It 'reports only supported optional legacy RID and architecture information' {
        $version = '1.1.5'
        $directory = Install-FakeIsolatedHost -Version $version -ReportedVersion $version
        New-Item -ItemType Directory -Path (Join-Path $directory "sdk/$version") -Force | Out-Null
        $env:FAKE_DOTNET_LEGACY_HOST = 'true'
        $env:FAKE_DOTNET_LEGACY_RID = 'win10-x64'
        $text = (Invoke-VerifyTool -Version $version) -join [Environment]::NewLine
        $script:VerifyExitCode | Should -Be 0
        $text | Should -Match 'Architecture\s+x64'
        $text | Should -Match 'Runtime identifier\s+win10-x64'
        $text | Should -Match 'Host version\s+Unavailable'
        $text | Should -Match '(?s)\.NET runtimes:\s+Unavailable'
    }

}

Describe 'PowerShell Verify origin, resolution, and metadata boundaries' {
    BeforeAll {
        $script:root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    }
    It 'shares the local proof between Verify and both Install correctness boundaries' {
        $source = Get-Content -LiteralPath (Join-Path $script:root 'isolated-dotnet-sdk.ps1') -Raw
        $source | Should -Match 'function Get-LocalIsolatedSdkValidation'
        ([regex]::Matches($source, 'Get-LocalIsolatedSdkValidation -Version')).Count | Should -Be 3
        $source | Should -Match 'Get-SdkAuditClassification -Version'
    }
}
