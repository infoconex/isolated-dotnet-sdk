[CmdletBinding()]
param(
    [ValidateRange(2, 4)]
    [int[]]$WorkerCounts = @(2, 4),

    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'
$runner = Join-Path $PSScriptRoot 'run-tests.ps1'
$pwshPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$files = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.Tests.ps1' -File |
        Where-Object { $_.Name -notlike '*Issue181Profile.Tests.ps1' } |
        Sort-Object Name)
if ($files.Count -ne 32) {
    throw "The diagnostic baseline expected 32 Pester files, found $($files.Count)."
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
        'isolated-dotnet-sdk-issue181-parallel-{0}' -f [guid]::NewGuid().ToString('N'))
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$processes = [Collections.Generic.List[object]]::new()
$results = [Collections.Generic.List[object]]::new()

function Invoke-Issue181Worker {
    param([string]$Label, [string[]]$Names)
    $summaryFile = Join-Path $OutputRoot "$Label.json"
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $pwshPath
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    foreach ($arg in @('-NoProfile', '-File', $runner, '-Suite', 'All',
            '-Issue181ResultFile', $summaryFile)) {
        [void]$psi.ArgumentList.Add($arg)
    }
    if ($Names.Count -gt 0) {
        [void]$psi.ArgumentList.Add('-Issue181TestFilesCsv')
        [void]$psi.ArgumentList.Add(($Names -join ','))
    }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    if (-not $process.Start()) {
        throw "Failed to start $Label"
    }
    # Read both pipes asynchronously to avoid blocking verbose Pester children.
    $job = [pscustomobject]@{
        Label = $Label
        Process = $process
        Clock = $clock
        Stdout = $process.StandardOutput.ReadToEndAsync()
        Stderr = $process.StandardError.ReadToEndAsync()
        SummaryFile = $summaryFile
        Files = @($Names)
    }
    $processes.Add($job)
    return $job
}

function Complete-Issue181Worker {
    param([object]$Job)
    if (-not $Job.Process.WaitForExit(900000)) {
        $Job.Process.Kill($true)
        throw "Worker timed out: $($Job.Label)"
    }
    $Job.Clock.Stop()
    $stdout = $Job.Stdout.GetAwaiter().GetResult()
    $stderr = $Job.Stderr.GetAwaiter().GetResult()
    Set-Content -LiteralPath (Join-Path $OutputRoot "$($Job.Label).stdout.txt") -Value $stdout
    Set-Content -LiteralPath (Join-Path $OutputRoot "$($Job.Label).stderr.txt") -Value $stderr
    if ($Job.Process.ExitCode -ne 0) {
        Write-Output $stderr
        throw "Worker $($Job.Label) failed (exit $($Job.Process.ExitCode)); inspect retained logs."
    }
    if (-not (Test-Path -LiteralPath $Job.SummaryFile -PathType Leaf)) {
        throw "Missing summary for $($Job.Label)."
    }
    $summary = Get-Content -LiteralPath $Job.SummaryFile -Raw | ConvertFrom-Json
    if ($summary.Result -ne 'Passed' -or [int]$summary.FailedCount -ne 0) {
        throw "Worker $($Job.Label) reported unsuccessful Pester results."
    }
    return [pscustomobject]@{
        Label = $Job.Label
        FileCount = $Job.Files.Count
        Total = [int]$summary.TotalCount
        Passed = [int]$summary.PassedCount
        Failed = [int]$summary.FailedCount
        Skipped = [int]$summary.SkippedCount
        WallMs = [math]::Round($Job.Clock.Elapsed.TotalMilliseconds, 2)
    }
}

function Get-Issue181WorkGroup {
    param([int]$Workers)
    $groups = @(
        for ($i = 0; $i -lt $Workers; $i++) {
            [pscustomobject]@{
                Id = $i + 1
                Weight = 0.0
                Names = [Collections.Generic.List[string]]::new()
            }
        }
    )
    # Based on earlier measured high-cost files; other weights use source size.
    $weighted = @(
        foreach ($file in $files) {
            $weight = switch ($file.Name) {
                'verify.Tests.ps1' { 41; break }
                'transactional-install.Tests.ps1' { 37; break }
                'behavior.Tests.ps1' { 18; break }
                'audit.Tests.ps1' { 12; break }
                default { [math]::Max(2, [math]::Ceiling($file.Length / 1024)) }
            }
            [pscustomobject]@{ Name = $file.Name; Weight = [double]$weight }
        }
    )
    foreach ($file in ($weighted | Sort-Object Weight -Descending)) {
        $target = @($groups | Sort-Object Weight, Id)[0]
        $target.Names.Add($file.Name)
        $target.Weight += $file.Weight
    }
    $covered = @($groups | ForEach-Object { $_.Names.ToArray() })
    if ($covered.Count -ne $files.Count -or
        @($covered | Sort-Object -Unique).Count -ne $files.Count) {
        throw 'Experimental worker partition omitted or duplicated test files.'
    }
    return $groups
}

try {
    Write-Output "Issue 181 parallel pilot: $($files.Count) test files, separate PowerShell processes/fixtures."
    Write-Output "Diagnostic logs: $OutputRoot"
    $baseline = Complete-Issue181Worker (Invoke-Issue181Worker -Label 'sequential' -Names @())
    $results.Add([pscustomobject]@{
            Workers = 1; WallMs = $baseline.WallMs
            Total = $baseline.Total; Passed = $baseline.Passed
            Failed = $baseline.Failed; Skipped = $baseline.Skipped
        })
    Write-Output ("Sequential: {0:N2}s, {1}/{2} passed" -f
        ($baseline.WallMs / 1000), $baseline.Passed, $baseline.Total)

    foreach ($count in $WorkerCounts) {
        $groups = @(Get-Issue181WorkGroup -Workers $count)
        $clock = [System.Diagnostics.Stopwatch]::StartNew()
        $jobs = [Collections.Generic.List[object]]::new()
        foreach ($group in $groups) {
            $jobs.Add((Invoke-Issue181Worker -Label "workers-$count-part-$($group.Id)" -Names @($group.Names.ToArray())))
        }
        $workers = @(
            foreach ($job in $jobs) {
                Complete-Issue181Worker -Job $job
            }
        )
        $clock.Stop()
        $passed = ($workers | Measure-Object Passed -Sum).Sum
        $total = ($workers | Measure-Object Total -Sum).Sum
        $failed = ($workers | Measure-Object Failed -Sum).Sum
        $skipped = ($workers | Measure-Object Skipped -Sum).Sum
        if ($passed -ne $baseline.Passed -or $total -ne $baseline.Total -or
            $failed -ne $baseline.Failed -or $skipped -ne $baseline.Skipped) {
            throw "Parallel $count workers changed test counts: $passed/$total, baseline $($baseline.Passed)/$($baseline.Total)."
        }
        $elapsed = [math]::Round($clock.Elapsed.TotalMilliseconds, 2)
        $results.Add([pscustomobject]@{
                Workers = $count; WallMs = $elapsed
                Total = $total; Passed = $passed
                Failed = $failed; Skipped = $skipped
            })
        Write-Output ("{0} workers: {1:N2}s, {2}/{3} passed; wall reduction {4:N1}%" -f
            $count, ($elapsed / 1000), $passed, $total,
            (100 * (1 - $elapsed / $baseline.WallMs)))
        $workers | Format-Table -AutoSize | Out-String -Width 160 | Write-Output
    }
    $results | ConvertTo-Json | Set-Content -LiteralPath (
        Join-Path $OutputRoot 'comparison.json') -Encoding utf8
}
finally {
    foreach ($job in $processes) {
        if (-not $job.Process.HasExited) {
            $job.Process.Kill($true)
            $job.Process.WaitForExit()
        }
        $job.Process.Dispose()
    }
}
