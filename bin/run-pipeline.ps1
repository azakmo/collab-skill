# One task, end to end, without waking CC: dispatch → verify → visual review → auto-rework (≤ MaxRework) → escalate
# along the task's 「升级路径」 → write collab/logs/<Task>.pipeline.json. CC only reads the final result.
#   & "$env:COLLAB_HOME\bin\run-pipeline.ps1" -Project <dir> -Task T00n [-MaxRework 2] [-MaxResume 2] [-ProviderWaitMin 15]
# Result: PASS | NO_TEST (no 验收测试 block, CC must review) | NEEDS_CC (every executor in the chain failed)
# Interruptions are not rework: a crash (exit code other than 0/2/3), a stall (4) or an unreachable provider waits for
# the provider and resumes the same codex session (keeps its progress) up to MaxResume times, without using up a
# rework round. Exit 2 (finished without a report) gets one resume that only asks for the report.
param(
    [Parameter(Mandatory)][string]$Project,
    [Parameter(Mandatory)][string]$Task,
    [int]$MaxRework = 2,
    [int]$MaxResume = 2,
    [int]$ProviderWaitMin = 15
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tools.ps1')
$Project = (Resolve-Path $Project).Path
$taskFile = Join-Path $Project "collab\tasks\$Task.md"
if (-not (Test-Path $taskFile)) { throw "task file not found: $taskFile" }

# Settings come from the task file itself, so CC writes them once there.
$first = ((Get-TaskField $taskFile '执行者') -split '[\s|（(,，]')[0].ToLower()
$timeout = [int](((Get-TaskField $taskFile '时限') -replace '[^\d].*$', '') -as [int]); if (-not $timeout) { $timeout = 30 }
$net = (Get-TaskField $taskFile '联网') -match '^(是|yes)'
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

# One executor run. A runner that throws before starting (provider down, ...) counts as an interruption (-100).
function Invoke-Run([string]$ex, [string]$resume, [string]$prompt) {
    $a = @{ Executor = $ex; Project = $Project; Task = $Task; TimeoutMin = $timeout; Network = $net; Toolchain = $tc }
    if ($resume) { $a.Resume = $resume; if ($prompt) { $a.ResumePrompt = $prompt } }
    try { & (Join-Path $PSScriptRoot 'run-executor.ps1') @a | Out-Host; $LASTEXITCODE }
    catch { Write-Host "  runner failed: $($_.Exception.Message)"; -100 }
}

function Wait-Provider([string]$ex) {
    $deadline = (Get-Date).AddMinutes($ProviderWaitMin)
    while (-not (Test-ProviderHealthy $ex)) {
        if ((Get-Date) -gt $deadline) { Write-Host "  provider of $ex still down after ${ProviderWaitMin}m"; return }
        Write-Host "  [$(Get-Date -Format s)] provider of $ex not answering, waiting..."
        Start-Sleep -Seconds 30
    }
}

# Session started by this round (log newer than $since), so we never resume an older round's session.
function Get-RoundSession([string]$ex, [datetime]$since) {
    $log = Get-ChildItem (Join-Path $Project 'collab\logs') -Filter "$Task-*.$ex.err.log" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $since } | Sort-Object LastWriteTime | Select-Object -First 1
    if (-not $log) { return '' }
    $m = Select-String -Path $log.FullName -Pattern '^session id:\s*([0-9a-f-]{36})' -Encoding utf8 | Select-Object -First 1
    if ($m) { $m.Matches[0].Groups[1].Value } else { '' }
}

$attempts = @(); $result = 'NEEDS_CC'; $prev = $null
:outer foreach ($ex in $chain) {
    if ($prev) {
        Add-TaskNote (L "## Handover (appended by the controller pipeline)`nThe previous executor $prev still failed the acceptance test after $MaxRework rework rounds; you ($ex) are taking over. First read the existing output and collab/reports/$Task.md, then fix it until the acceptance test passes completely." `
            "## 换人（主控流水线自动追加）`n前一位执行者 $prev 返工 $MaxRework 轮后验收测试仍未通过，现在由你（$ex）接手。先读现有产物和 collab/reports/$Task.md，再修复，直到验收测试全部通过。")
    }
    for ($round = 0; $round -le $MaxRework; $round++) {
        $since = (Get-Date).AddSeconds(-2)
        $rc = Invoke-Run $ex
        # Interrupted (crash / stall / proxy outage): wait for the provider, resume the same session; not a rework round.
        $resumes = 0
        while ($rc -notin 0, 2, 3 -and $resumes -lt $MaxResume) {
            $resumes++
            $attempts += [pscustomobject]@{ executor = $ex; round = $round; rc = $rc; verify = "interrupted, resume $resumes" }
            try { & (Join-Path $PSScriptRoot 'ledger-mark.ps1') -Project $Project -Task $Task -Review interrupted -Note "pipeline rc=$rc, resume $resumes" | Out-Null } catch {}
            Wait-Provider $ex
            $sid = Get-RoundSession $ex $since
            Write-Host "  interrupted (rc=$rc) -> $(if ($sid) { "resume session $sid" } else { 'no session yet, fresh start' })"
            $rc = Invoke-Run $ex $sid
        }
        # Finished without a report: one cheap resume that only asks for it.
        if ($rc -eq 2) {
            $sid = Get-RoundSession $ex $since
            if ($sid) {
                $rc = Invoke-Run $ex $sid "You stopped without writing collab/reports/$Task.md. Run the acceptance tests in collab/tasks/$Task.md, then write the report (in $(L 'English' 'Chinese')) following collab/_templates/report.md. Do not redo finished work."
            }
        }
        if ($rc -ne 0) {
            $attempts += [pscustomobject]@{ executor = $ex; round = $round; rc = $rc; verify = 'skipped' }
            try { & (Join-Path $PSScriptRoot 'ledger-mark.ps1') -Project $Project -Task $Task -Review 失败 -Note "pipeline rc=$rc" | Out-Null } catch {}
            Add-TaskNote (L "## Rework round $($round + 1) (appended by the controller pipeline)`nThe previous run ended abnormally (exit code ${rc}: 2 = no report written, 3 = timed out). Finish within the timeout and be sure to write the report." `
                "## 返工 第 $($round + 1) 轮（主控流水线自动追加）`n上一轮执行异常结束（退出码 $rc：2=没写回报，3=超时）。请在时限内完成，并务必写回报。")
            continue
        }
        $vout = @(& (Join-Path $PSScriptRoot 'verify.ps1') -Project $Project -Task $Task -Mark 2>&1 | ForEach-Object { "$_" })
        $vrc = $LASTEXITCODE
        if ($vrc -eq 4) { $attempts += [pscustomobject]@{ executor = $ex; round = $round; rc = 0; verify = 'no-test' }; $result = 'NO_TEST'; break outer }
        $summary = ($vout | Where-Object { $_ -like 'RESULT*' }) -join ''
        $attempts += [pscustomobject]@{ executor = $ex; round = $round; rc = 0; verify = $summary }
        if ($vrc -eq 0) {
            # Visual acceptance (only for tasks with a visual section): a vision reviewer checks the screenshots.
            $vis = @(& (Join-Path $PSScriptRoot 'visual-review.ps1') -Project $Project -Task $Task 2>&1 | ForEach-Object { "$_" })
            $visRc = $LASTEXITCODE
            if ($visRc -eq 4) { $result = 'PASS'; break outer }
            $attempts[-1] | Add-Member visual (($vis | Where-Object { $_ -match '^VISUAL RESULT' }) -join '') -Force
            if ($visRc -eq 0) { $result = 'PASS'; break outer }
            if ($visRc -notin 1, 5) {
                # Reviewer itself failed (proxy down, bad output): don't block on it, CC looks at the contact sheet.
                $attempts[-1].visual = "reviewer error ($visRc): $($vis | Select-Object -Last 1)"
                $result = 'PASS'; break outer
            }
            try { & (Join-Path $PSScriptRoot 'ledger-mark.ps1') -Project $Project -Task $Task -Review rework -Note (L 'tests passed, visual review failed' '测试通过，视觉验收未过') | Out-Null } catch {}
            if ($round -lt $MaxRework) {
                $block = "``````text`n$(($vis | Where-Object { $_ -match '^(FAIL|VISUAL)' }) -join "`n")`n``````"
                Add-TaskNote (L "## Rework round $($round + 1) (appended by the controller pipeline)`nThe acceptance test passed, but the visual review did not (a reviewer checked every screenshot):`n$block`nFix the UI problems, regenerate the screenshots listed in the visual section, re-run the acceptance test and update the report." `
                    "## 返工 第 $($round + 1) 轮（主控流水线自动追加）`n验收测试通过了，但视觉验收没通过（审查员逐张看截图的结论）：`n$block`n修复界面问题，重新生成「视觉验收」里的截图，再跑一遍验收测试，并更新回报。")
            }
            continue
        }
        $fails = ($vout | Where-Object { $_ -match '^(FAIL|TIMEOUT|---|\s)' }) -join "`n"
        if ($round -lt $MaxRework) {
            $block = "``````text`n$fails`n``````"
            Add-TaskNote (L "## Rework round $($round + 1) (appended by the controller pipeline)`nThe acceptance test did not pass last round. Failures:`n$block`nFix them, re-run the acceptance test until everything PASSes, and update the report. Do not modify the acceptance test." `
                "## 返工 第 $($round + 1) 轮（主控流水线自动追加）`n上一轮验收测试没通过，失败项：`n$block`n修复后重新跑「验收测试」直到全部 PASS，并更新回报。不要修改验收测试。")
        }
    }
    $prev = $ex
}

$final = $attempts | Select-Object -Last 1
$out = [pscustomobject]@{
    task = $Task; result = $result; chain = $chain; attempts = $attempts
    final_executor = $final.executor; report = "collab/reports/$Task.md"
    contact_sheet = $(if (Test-Path (Join-Path $Project "collab\logs\$Task.contact.png")) { "collab/logs/$Task.contact.png" } else { $null })
}
$json = Join-Path $Project "collab\logs\$Task.pipeline.json"
[IO.File]::WriteAllText($json, ($out | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))
"PIPELINE $Task : $result (by $($final.executor), $(@($attempts).Count) attempt(s); chain $($chain -join '→'))"
if ($out.contact_sheet) { "  visual: $($final.visual)  contact sheet: $($out.contact_sheet)" }
exit $(if ($result -eq 'PASS') { 0 } elseif ($result -eq 'NO_TEST') { 5 } else { 6 })
