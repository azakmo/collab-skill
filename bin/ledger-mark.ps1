# Record CC's final-review verdict for a task in <collab>\ledger.csv (latest row of that project+task).
#   & "$env:COLLAB_HOME\bin\ledger-mark.ps1" -Project C:\work\my-project -Task T002 -Review 返工 -Note '校验缺失，转 Codex'
param(
    [Parameter(Mandatory)][string]$Project,
    [Parameter(Mandatory)][string]$Task,
    [Parameter(Mandatory)][ValidateSet('通过', '返工', '失败', '取消')][string]$Review,
    [string]$Note = ''
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tools.ps1')

$Project = (Resolve-Path $Project).Path
$rows = @(Import-Csv $script:LedgerPath -Encoding utf8)
$hit = $rows | Where-Object { $_.project -eq $Project -and $_.task -eq $Task } | Select-Object -Last 1
if (-not $hit) { throw "no ledger row for $Project / $Task" }
$hit.review = $Review
if ($Note) { $hit.note = $Note }
Save-Ledger $rows
"marked $Task -> $Review"
