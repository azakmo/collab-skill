# One task, end to end, without waking CC: dispatch → verify → auto-rework (≤ MaxRework) → escalate along
# the task's 「升级路径」 → write collab/logs/<Task>.pipeline.json. CC only reads the final result.
#   & "$env:COLLAB_HOME\bin\run-pipeline.ps1" -Project <dir> -Task T00n [-MaxRework 2]
# Result: PASS | NO_TEST (no 验收测试 block, CC must review) | NEEDS_CC (every executor in the chain failed)
param(
    [Parameter(Mandatory)][string]$Project,
    [Parameter(Mandatory)][string]$Task,
    [int]$MaxRework = 2
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tools.ps1')
$Project = (Resolve-Path $Project).Path
$taskFile = Join-Path $Project "collab\tasks\$Task.md"
if (-not (Test-Path $taskFile)) { throw "task file not found: $taskFile" }

# Settings come from the task file itself, so CC writes them once there.
$first = ((Get-TaskField $taskFile '执行者') -split '[\s|（(,，]')[0].ToLower()
$timeout = [int](((Get-TaskField $taskFile '时限') -replace '[^\d].*$', '') -as [int]); if (-not $timeout) { $timeout = 30 }
$net = (Get-TaskField $taskFile '联网') -like '是*'
$tc = if ((Get-TaskField $taskFile '工具链') -match '^(android)') { $Matches[1] } else { '' }

$roster = Get-Roster
$enabled = @($roster.executors | Where-Object enabled | ForEach-Object id)
$path = (Get-TaskField $taskFile '升级路径') -split '\s*(?:→|->|>|,|，)\s*' | ForEach-Object { ($_ -split '\s')[0].ToLower() } | Where-Object { $_ }
if (-not $path) { $path = @($first) + @($roster.executors | Where-Object { $_.enabled -and $_.layer -eq 'impl' } | ForEach-Object id) }
$chain = @(@($first) + @($path | Select-Object -Skip ([array]::IndexOf(@($path), $first) + 1))) |
    Where-Object { $_ -in $enabled } | Select-Object -Unique
if (-not $chain) { throw "no enabled executor for $Task (执行者=$first, 升级路径=$($path -join '→'))" }

function Add-TaskNote([string]$text) {
    [IO.File]::AppendAllText($taskFile, "`n$text`n", (New-Object Text.UTF8Encoding $false))
}

$attempts = @(); $result = 'NEEDS_CC'; $prev = $null
:outer foreach ($ex in $chain) {
    if ($prev) {
        Add-TaskNote "## 换人（主控流水线自动追加）`n前一位执行者 $prev 返工 $MaxRework 轮后验收测试仍未通过，现在由你（$ex）接手。先读现有产物和 collab/reports/$Task.md，再修复，直到验收测试全部通过。"
    }
    for ($round = 0; $round -le $MaxRework; $round++) {
        & (Join-Path $PSScriptRoot 'run-executor.ps1') -Executor $ex -Project $Project -Task $Task -TimeoutMin $timeout `
            -Network:$net -Toolchain $tc | Out-Host
        $rc = $LASTEXITCODE
        if ($rc -ne 0) {
            $attempts += [pscustomobject]@{ executor = $ex; round = $round; rc = $rc; verify = 'skipped' }
            try { & (Join-Path $PSScriptRoot 'ledger-mark.ps1') -Project $Project -Task $Task -Review 失败 -Note "pipeline rc=$rc" | Out-Null } catch {}
            Add-TaskNote "## 返工 第 $($round + 1) 轮（主控流水线自动追加）`n上一轮执行异常结束（退出码 $rc：2=没写回报，3=超时）。请在时限内完成，并务必写回报。"
            continue
        }
        $vout = @(& (Join-Path $PSScriptRoot 'verify.ps1') -Project $Project -Task $Task -Mark 2>&1 | ForEach-Object { "$_" })
        $vrc = $LASTEXITCODE
        if ($vrc -eq 4) { $attempts += [pscustomobject]@{ executor = $ex; round = $round; rc = 0; verify = 'no-test' }; $result = 'NO_TEST'; break outer }
        $summary = ($vout | Where-Object { $_ -like 'RESULT*' }) -join ''
        $attempts += [pscustomobject]@{ executor = $ex; round = $round; rc = 0; verify = $summary }
        if ($vrc -eq 0) { $result = 'PASS'; break outer }
        $fails = ($vout | Where-Object { $_ -match '^(FAIL|TIMEOUT|---|\s)' }) -join "`n"
        if ($round -lt $MaxRework) {
            Add-TaskNote "## 返工 第 $($round + 1) 轮（主控流水线自动追加）`n上一轮验收测试没通过，失败项：`n``````text`n$fails`n```````n修复后重新跑「验收测试」直到全部 PASS，并更新回报。不要修改验收测试。"
        }
    }
    $prev = $ex
}

$final = $attempts | Select-Object -Last 1
$out = [pscustomobject]@{
    task = $Task; result = $result; chain = $chain; attempts = $attempts
    final_executor = $final.executor; report = "collab/reports/$Task.md"
}
$json = Join-Path $Project "collab\logs\$Task.pipeline.json"
[IO.File]::WriteAllText($json, ($out | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))
"PIPELINE $Task : $result (by $($final.executor), $(@($attempts).Count) attempt(s); chain $($chain -join '→'))"
exit $(if ($result -eq 'PASS') { 0 } elseif ($result -eq 'NO_TEST') { 5 } else { 6 })
