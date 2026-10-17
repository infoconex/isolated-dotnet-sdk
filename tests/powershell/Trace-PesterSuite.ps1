# Issue #181 diagnostic-only tracer. Not loaded by ordinary test runs.
# Temporary copies live beside the originals to preserve PSScriptRoot paths.

function Write-Issue181TraceEvent {
    param(
        [string]$Kind,
        [string]$File,
        [string]$Name,
        [long]$StartTicks,
        [string]$Result = ''
    )
    $path = $env:ISOLATED_DOTNET_SDK_TEST_PROFILE_EVENTS
    if ([string]::IsNullOrWhiteSpace($path)) { return }
    $elapsedMs = [math]::Round(
        ([Diagnostics.Stopwatch]::GetTimestamp() - $StartTicks) * 1000.0 /
        [Diagnostics.Stopwatch]::Frequency, 3)
    $safeName = $Name.Replace([char]9, ' ').Replace([char]10, ' ').Replace([char]13, ' ')
    $safeResult = $Result.Replace([char]9, ' ').Replace([char]10, ' ').Replace([char]13, ' ')
    $line = '{0}{1}{2}{1}{3}{1}{4}{1}{5}{1}{6}{1}{7}' -f (
        [DateTime]::UtcNow.ToString('o')), [char]9, $PID, $Kind,
        $File, $safeName, $elapsedMs.ToString([Globalization.CultureInfo]::InvariantCulture), $safeResult
    $queue = [AppDomain]::CurrentDomain.GetData('IsolatedDotNetSdkIssue181Trace')
    if ($null -ne $queue) {
        $queue.Enqueue($line)
    }
    else {
        [IO.File]::AppendAllText($path, $line + [Environment]::NewLine)
    }
}

function Save-Issue181TraceEventBatch {
    $queue = [AppDomain]::CurrentDomain.GetData('IsolatedDotNetSdkIssue181Trace')
    $path = $env:ISOLATED_DOTNET_SDK_TEST_PROFILE_EVENTS
    if ($null -eq $queue -or [string]::IsNullOrWhiteSpace($path)) { return }
    $lines = [Collections.Generic.List[string]]::new()
    $item = ''
    while ($queue.TryDequeue([ref]$item)) {
        $lines.Add($item)
    }
    if ($lines.Count -gt 0) {
        [IO.File]::AppendAllLines($path, $lines)
    }
}
function ConvertTo-Issue181InstrumentedPesterFile {
    param(
        [Parameter(Mandatory)][string]$OriginalFile,
        [Parameter(Mandatory)][string]$OutputFile
    )
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile(
        $OriginalFile, [ref]$tokens, [ref]$parseErrors)
    if (@($parseErrors).Count -ne 0) {
        throw "Cannot instrument a PowerShell test file with parse errors: $OriginalFile"
    }
    $source = [IO.File]::ReadAllText($OriginalFile)
    $fileLabel = [IO.Path]::GetFileName($OriginalFile)
    $edits = [Collections.Generic.List[object]]::new()
    $nodes = @($ast.FindAll({
                param($node)
                if ($node -is [Management.Automation.Language.FunctionDefinitionAst]) {
                    return $true
                }
                if ($node -isnot [Management.Automation.Language.CommandAst]) {
                    return $false
                }
                return $node.GetCommandName() -in @('It', 'BeforeAll', 'BeforeEach', 'AfterEach', 'AfterAll', 'pwsh')
            }, $true))
    $counts = [ordered]@{ It = 0; Hook = 0; Function = 0; ChildPwsh = 0; Skipped = 0 }
    foreach ($node in $nodes) {
        if ($node -is [Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -eq 'pwsh') {
            $commandWord = $node.CommandElements[0].Extent
            $edits.Add([pscustomobject]@{
                    Offset = $commandWord.StartOffset
                    Length = $commandWord.EndOffset - $commandWord.StartOffset
                    Text = 'Invoke-Issue181ChildPwsh'
                })
            $counts.ChildPwsh++
            continue
        }
        $kind = ''
        $label = ''
        $body = $null
        if ($node -is [Management.Automation.Language.FunctionDefinitionAst]) {
            $kind = 'Function'
            $label = $node.Name
            $body = $node.Body
        }
        else {
            $kind = [string]$node.GetCommandName()
            $scriptBlock = @($node.CommandElements |
                    Where-Object { $_ -is [Management.Automation.Language.ScriptBlockExpressionAst] } |
                    Select-Object -Last 1)
            if ($scriptBlock.Count -eq 0) {
                $counts.Skipped++
                continue
            }
            $body = $scriptBlock[0].ScriptBlock
            $label = if ($kind -eq 'It') {
                $stringArg = @($node.CommandElements |
                        Where-Object { $_ -is [Management.Automation.Language.StringConstantExpressionAst] } |
                        Select-Object -Skip 1 -First 1)
                if ($stringArg.Count -ne 0) {
                    $stringArg[0].Value
                }
                else { $node.Extent.Text.Substring(0, [math]::Min(100, $node.Extent.Text.Length)) }
            }
            else { $kind }
        }
        if ($body.BeginBlock -or $body.ProcessBlock -or $body.DynamicParamBlock) {
            $counts.Skipped++
            continue
        }
        $begin = $body.Extent.StartOffset + 1
        if ($null -ne $body.ParamBlock) { $begin = $body.ParamBlock.Extent.EndOffset }
        $end = $body.Extent.EndOffset - 1
        $fileB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($fileLabel))
        $nameB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($label))
        $textKind = $kind.Replace("'", "''")
        $prefix = @'

        $__issue181Start = [Diagnostics.Stopwatch]::GetTimestamp()
        try {

'@
        $suffix = @'

        } finally {
            Write-Issue181TraceEvent -Kind '__KIND__' -File (
                [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__FILE__'))) -Name (
                [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__NAME__'))) -StartTicks $__issue181Start
        }
'@
        $suffix = $suffix.Replace('__KIND__', $textKind).Replace('__FILE__', $fileB64).Replace('__NAME__', $nameB64)
        if ($kind -eq 'It') {
            # Tag both ordinary pwsh children and native fake hosts with the
            # currently running Pester case. Restore even when an assertion throws.
            $caseB64 = [Convert]::ToBase64String(
                [Text.Encoding]::UTF8.GetBytes("$fileLabel :: $label"))
            $casePrefix = @'
        $__issue181PreviousCase = [Environment]::GetEnvironmentVariable(
            'ISOLATED_DOTNET_SDK_TEST_PROFILE_CASE', 'Process')
        $env:ISOLATED_DOTNET_SDK_TEST_PROFILE_CASE = (
            [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__CASE__')))

'@
            $prefix = $casePrefix.Replace('__CASE__', $caseB64) + $prefix
            $suffix = $suffix.Replace(
                '-StartTicks $__issue181Start',
                '-StartTicks $__issue181Start' + [Environment]::NewLine +
                '            [Environment]::SetEnvironmentVariable(' +
                "'ISOLATED_DOTNET_SDK_TEST_PROFILE_CASE', " +
                '$__issue181PreviousCase, ' + "'Process')" )
        }
        $edits.Add([pscustomobject]@{ Offset = $begin; Length = 0; Text = $prefix })
        $edits.Add([pscustomobject]@{ Offset = $end; Length = 0; Text = $suffix })
        if ($kind -eq 'It') { $counts.It++ }
        elseif ($kind -eq 'Function') { $counts.Function++ }
        else { $counts.Hook++ }
    }
    foreach ($edit in @($edits | Sort-Object Offset -Descending)) {
        $source = $source.Remove($edit.Offset, $edit.Length).Insert($edit.Offset, $edit.Text)
    }
    [IO.File]::WriteAllText($OutputFile, $source, [Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{
        File = $fileLabel
        ItBlocks = $counts.It
        Hooks = $counts.Hook
        Functions = $counts.Function
        ChildPwsh = $counts.ChildPwsh
        Skipped = $counts.Skipped
    }
}

function Enable-Issue181NativeProcessTrace {
    [AppDomain]::CurrentDomain.SetData('IsolatedDotNetSdkIssue181Trace',
        [Collections.Concurrent.ConcurrentQueue[string]]::new())
    $real = @(Get-Command pwsh -CommandType Application -ErrorAction Stop |
            Select-Object -First 1)
    if ($real.Count -ne 1) { throw 'Cannot locate the real pwsh executable.' }
    $env:ISOLATED_DOTNET_SDK_TEST_REAL_PWSH = $real[0].Source
    # Instrument only AST-confirmed native pwsh calls in temporary test copies.
    # Do NOT shadow the real 'pwsh' command: behavioral tests use
    # Get-Command pwsh to locate the executable and must still get its Source.
    # ProcessStartInfo callers remain visible through enclosing helpers.
    function global:Invoke-Issue181ChildPwsh {
        $start = [Diagnostics.Stopwatch]::GetTimestamp()
        try {
            & $env:ISOLATED_DOTNET_SDK_TEST_REAL_PWSH @args
        }
        finally {
            $childExit = $LASTEXITCODE
            Write-Issue181TraceEvent -Kind 'ChildPwsh' -File $env:ISOLATED_DOTNET_SDK_TEST_PROFILE_CASE -Name (
                ($args | Select-Object -First 5) -join ' ') -StartTicks $start -Result ([string]$childExit)
            $global:LASTEXITCODE = $childExit
        }
    }
}

function Disable-Issue181NativeProcessTrace {
    Save-Issue181TraceEventBatch
    [AppDomain]::CurrentDomain.SetData('IsolatedDotNetSdkIssue181Trace', $null)
    Remove-Item Function:\Invoke-Issue181ChildPwsh -ErrorAction SilentlyContinue
    Remove-Item Env:ISOLATED_DOTNET_SDK_TEST_REAL_PWSH -ErrorAction SilentlyContinue
}
