# Run several tasks' pipelines in parallel and return once, with one summary table.
# CC starts this in the background and is woken a single time for the whole batch.
#   & "$env:COLLAB_HOME\bin\run-batch.ps1" -Project <dir> -Tasks T001,T002,T003 [-MaxRework 2]
# Tasks must not share writable files (CC guarantees that when splitting).
param(
    [Parameter(Mandatory)][string]$Project,
    [Parameter(Mandatory)][string[]]$Tasks,
    [int]$MaxRework = 2
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tools.ps1')
$Project = (Resolve-Path $Project).Path
$logs = Join-Path $Project 'collab\logs'
New-Item -ItemType Directory -Force $logs | Out-Null
$start = Get-Date
$pipeline = Join-Path $PSScriptRoot 'run-pipeline.ps1'

$procs = foreach ($t in $Tasks) {
    Remove-Item (Join-Path $logs "$t.pipeline.json") -ErrorAction SilentlyContinue
    $p = Start-Process pwsh -ArgumentList "-NoProfile -File `"$pipeline`" -Project `"$Project`" -Task $t -MaxRework $MaxRework -Quiet" `
        -RedirectStandardOutput (Join-Path $logs "$t.pipeline.out.log") -RedirectStandardError (Join-Path $logs "$t.pipeline.err.log") `
        -NoNewWindow -PassThru
    $null = $p.Handle
    [pscustomobject]@{ Task = $t; Proc = $p }
}
Write-Host "batch started: $($Tasks -join ', ')"
$procs | ForEach-Object { $_.Proc.WaitForExit() }

$ledger = @(if (Test-Path $script:LedgerPath) { Import-Csv $script:LedgerPath -Encoding utf8 })
$rows = foreach ($x in $procs) {
    $j = Join-Path $logs "$($x.Task).pipeline.json"
    $r = if (Test-Path $j) { Get-Content $j -Raw -Encoding utf8 | ConvertFrom-Json } else { $null }
    $mine = $ledger | Where-Object { $_.project -eq $Project -and $_.task -eq $x.Task -and [datetime]$_.time -ge $start.AddMinutes(-1) }
    [pscustomobject]@{
        task     = $x.Task
        result   = if ($r) { $r.result } else { "CRASH(exit $($x.Proc.ExitCode))" }
        by       = if ($r) { $r.final_executor } else { '' }
        attempts = if ($r) { @($r.attempts).Count } else { 0 }
        visual   = if ($r -and $r.contact_sheet) { "$((@($r.attempts) | Select-Object -Last 1).visual)" } else { '' }
        tokens   = [long]($mine | ForEach-Object { [long]("0$($_.tokens)") } | Measure-Object -Sum).Sum
        minutes  = [math]::Round(((Get-Date) - $start).TotalMinutes, 1)
    }
}
$rows | Format-Table -AutoSize | Out-String -Width 160
$bad = @($rows | Where-Object result -ne 'PASS')
if ($bad) {
    $list = ($bad | ForEach-Object { "$($_.task)=$($_.result)" }) -join ', '
    L "Needs the controller: $list" "需要主控处理：$list"
    L "(pipeline details: collab/logs/<task>.pipeline.json; crashes: collab/logs/<task>.pipeline.err.log)" "（PIPELINE 详情：collab/logs/<任务>.pipeline.json；崩溃看 collab/logs/<任务>.pipeline.err.log）"
}
# One desktop notification for the whole batch.
$pass = @($rows | Where-Object result -eq 'PASS').Count
$msg = (L "$pass passed" "$pass 通过") + $(if ($bad) { (L ', needs CC: ' '，要 CC 处理：') + (($bad | ForEach-Object { "$($_.task)=$($_.result)" }) -join ', ') } else { '' }) +
    (L " · $([math]::Round(((Get-Date) - $start).TotalMinutes)) min" " · 用时 $([math]::Round(((Get-Date) - $start).TotalMinutes)) 分钟")
& (Join-Path $PSScriptRoot 'notify.ps1') -Title (L "$(Split-Path $Project -Leaf): $($Tasks.Count) task(s) finished" "$(Split-Path $Project -Leaf)：$($Tasks.Count) 个任务跑完") -Message $msg | Out-Host
exit $bad.Count
