# Record CC's final-review verdict for a task in <collab>\ledger.csv (latest row of that project+task).
#   & "$env:COLLAB_HOME\bin\ledger-mark.ps1" -Project C:\work\my-project -Task T002 -Review rework -Note 'validation missing, moved to Codex'
# -Review: pass | rework | failed | cancelled | interrupted (or 通过 | 返工 | 失败 | 取消 | 中断). Stored in the ledger as the
# Chinese value. "interrupted" is written by the pipeline for crashed/stalled runs that get resumed (not a verdict).
param(
    [Parameter(Mandatory)][string]$Project,
    [Parameter(Mandatory)][string]$Task,
    [Parameter(Mandatory)][ValidateSet('pass', 'rework', 'failed', 'cancelled', 'interrupted', '通过', '返工', '失败', '取消', '中断')][string]$Review,
    [string]$Note = ''
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tools.ps1')
$Review = @{ pass = '通过'; rework = '返工'; failed = '失败'; cancelled = '取消'; interrupted = '中断' }[$Review] ?? $Review

$Project = (Resolve-Path $Project).Path
$rows = @(Import-Csv $script:LedgerPath -Encoding utf8)
$hit = $rows | Where-Object { $_.project -eq $Project -and $_.task -eq $Task } | Select-Object -Last 1
if (-not $hit) { throw "no ledger row for $Project / $Task" }
$hit.review = $Review
if ($Note) { $hit.note = $Note }
Save-Ledger $rows
"marked $Task -> $Review"
