# Live progress for the console: running executors (codex exec processes, including proxy models run through the
# Codex harness), live pipelines, and task boards of recently active projects.
# Read-only: process command lines, collab\logs and collab\tasks; changes nothing. console.ps1 serves it at /api/live.

# Last $Bytes of a file that may still be written to (share ReadWrite), cut to whole lines.
function Read-Tail([string]$Path, [int]$Bytes = 65536) {
    $fs = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    try {
        $n = [Math]::Min($Bytes, $fs.Length)
        $fs.Seek(-$n, 'End') | Out-Null
        $buf = New-Object byte[] $n
        $read = $fs.Read($buf, 0, $n)
        $text = [Text.Encoding]::UTF8.GetString($buf, 0, $read)
        if ($n -lt $fs.Length) { $text = $text.Substring([Math]::Max(0, $text.IndexOf("`n") + 1)) }
        $text -replace "`r", ''
    } finally { $fs.Dispose() }
}

# The executor's last narration: the block after the last line that is exactly "codex".
function Get-LastNarration([string[]]$Lines) {
    if (-not $Lines) { return '' }
    for ($i = $Lines.Count - 1; $i -ge 0; $i--) {
        if ($Lines[$i] -ceq 'codex') {
            if ($i -ge $Lines.Count - 1) { return '' }
            $out = [Collections.Generic.List[string]]::new()
            foreach ($l in $Lines[($i + 1)..($Lines.Count - 1)]) {
                if ($l -cmatch '^(exec|user|thinking|codex|tokens used|apply patch|patch: .*|file update.*|diff --git .*)$') { break }
                if ($l.Trim()) { $out.Add($l) } elseif ($out.Count) { break }
                if ($out.Count -ge 12) { break }
            }
            return ($out -join "`n").Trim()
        }
    }
    ''
}

# Long command output can push the last narration far back, so remember it per log and read only new bytes.
$script:NarrCache = @{}
function Get-LogNarration([string]$Path) {
    $c = $script:NarrCache[$Path]
    if (-not $c) { $c = @{ Offset = 0L; Text = ''; Carry = '' }; $script:NarrCache[$Path] = $c }
    $fs = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    try {
        if ($fs.Length -lt $c.Offset) { $c.Offset = 0L; $c.Text = ''; $c.Carry = '' }
        $fs.Seek($c.Offset, 'Begin') | Out-Null
        $n = [int]($fs.Length - $c.Offset)
        if ($n -le 0) { return $c.Text }
        $buf = New-Object byte[] $n
        $read = $fs.Read($buf, 0, $n)
        # Keep a partial last line (and any split UTF-8 sequence) for next time.
        $cut = [Array]::LastIndexOf($buf, [byte]10, $read - 1)
        if ($cut -lt 0) { return $c.Text }
        $text = $c.Carry + [Text.Encoding]::UTF8.GetString($buf, 0, $cut + 1) -replace "`r", ''
        $c.Offset += $cut + 1
        # Re-scan from the previous narration header so a block that grew across reads stays complete.
        $lines = @($text -split "`n")
        $nar = Get-LastNarration $lines
        if ($nar) {
            $c.Text = $nar
            $i = [Array]::LastIndexOf($lines, 'codex')
            $c.Carry = ($lines[$i..($lines.Count - 1)] -join "`n")
            if ($c.Carry.Length -gt 20000) { $c.Carry = '' }
        } else { $c.Carry = '' }
        $c.Text
    } finally { $fs.Dispose() }
}

function Get-TaskTitle([string]$Project, [string]$Task) {
    $f = Join-Path $Project "collab\tasks\$Task.md"
    if (-not (Test-Path $f)) { return '' }
    $h = Get-Content $f -TotalCount 5 -Encoding utf8 | Where-Object { $_ -match '^#\s' } | Select-Object -First 1
    ($h -replace '^#\s*', '' -replace "^$Task[:：]\s*", '').Trim()
}

function Get-ArgValue([string]$Cmd, [string]$Flag) {
    if ($Cmd -match "(?:^|\s)$Flag\s+(?:`"([^`"]+)`"|(\S+))") { if ($Matches[1]) { $Matches[1] } else { $Matches[2] } }
}

function Get-LiveJson {
    $now = Get-Date
    $stallMin = if ($env:COLLAB_STALL_MIN) { [int]$env:COLLAB_STALL_MIN } else { 12 }
    $procs = @(Get-CimInstance Win32_Process -Filter "Name='codex.exe' or Name='pwsh.exe' or Name='powershell.exe'" -ErrorAction SilentlyContinue)

    # Executors: codex.exe exec ... -o <LogBase>.<name>-last.md
    $runs = foreach ($p in $procs | Where-Object { $_.Name -eq 'codex.exe' -and $_.CommandLine -match '\sexec\s' }) {
        $o = Get-ArgValue $p.CommandLine '-o'
        if (-not $o -or $o -notmatch '^(.*\\collab\\logs\\(T[^\\-]+)-(\d{8}-\d{6}))\.([\w-]+)-last\.md$') { continue }
        $logBase = $Matches[1]; $task = $Matches[2]; $name = $Matches[4]
        $project = Split-Path (Split-Path (Split-Path $logBase))
        $start = [datetime]::ParseExact($Matches[3], 'yyyyMMdd-HHmmss', $null)
        $err = "$logBase.$name.err.log"
        $tail = @(); $idle = $null; $size = 0
        if (Test-Path $err) {
            $fi = Get-Item $err; $size = $fi.Length
            $idle = [int]($now - $fi.LastWriteTime).TotalSeconds
            $tail = @((Read-Tail $err) -split "`n")
        }
        $show = @($tail | Select-Object -Last 40 | ForEach-Object { if ($_.Length -gt 300) { $_.Substring(0, 300) + ' …' } else { $_ } })
        [pscustomobject]@{
            pid = $p.ProcessId; project = $project; task = $task; title = Get-TaskTitle $project $task
            executor = $name; model = Get-ArgValue $p.CommandLine '-m'
            resume = [bool]($p.CommandLine -match '\sexec\s+resume\s')
            readonly = -not ($p.CommandLine -match '\s-s\s+workspace-write')
            start = $start.ToString('s'); elapsed = [int]($now - $start).TotalSeconds
            idle = $idle; stalled = ($idle -ne $null -and $idle -ge $stallMin * 60); log_kb = [int]($size / 1KB)
            narration = $(if (Test-Path $err) { Get-LogNarration $err } else { '' }); tail = $show
        }
    }
    $runs = @($runs)

    # Pipelines / batches that are alive (they may be between executor runs: verifying, waiting for provider ...)
    $pipes = @(foreach ($p in $procs | Where-Object { $_.CommandLine -match 'run-pipeline\.ps1' }) {
        $proj = Get-ArgValue $p.CommandLine '-Project'; $t = Get-ArgValue $p.CommandLine '-Task'
        if ($proj -and $t) { [pscustomobject]@{ project = $proj.TrimEnd('\'); task = $t; pid = $p.ProcessId } }
    })

    # Projects: from ledger + live runs + live pipelines; board only for those active in the last 24h.
    $projects = @()
    if (Test-Path $script:LedgerPath) { $projects += @(Import-Csv $script:LedgerPath -Encoding utf8 | ForEach-Object project) }
    $projects += @($runs.project) + @($pipes.project)
    $boards = foreach ($proj in $projects | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') } | Sort-Object -Unique) {
        $logs = Join-Path $proj 'collab\logs'
        if (-not (Test-Path $logs)) { continue }
        $logFiles = @(Get-ChildItem $logs -File -ErrorAction SilentlyContinue)
        $last = ($logFiles | Measure-Object LastWriteTime -Maximum).Maximum
        $live = @($runs | Where-Object project -eq $proj).Count + @($pipes | Where-Object project -eq $proj).Count
        if (-not $live -and (-not $last -or ($now - $last).TotalHours -gt 24)) { continue }
        $tasks = foreach ($tf in Get-ChildItem (Join-Path $proj 'collab\tasks') -Filter 'T*.md' -ErrorAction SilentlyContinue | Sort-Object Name) {
            $t = $tf.BaseName
            $run = $runs | Where-Object { $_.project -eq $proj -and $_.task -eq $t } | Select-Object -First 1
            $pipe = $pipes | Where-Object { $_.project -eq $proj -and $_.task -eq $t } | Select-Object -First 1
            $pj = Join-Path $logs "$t.pipeline.json"
            $attempts = @($logFiles | Where-Object { $_.Name -like "$t-*.err.log" }).Count
            $recent = $logFiles | Where-Object { ($_.Name -like "$t-*" -or $_.Name -like "$t.verify*") -and ($now - $_.LastWriteTime).TotalMinutes -lt 3 } |
                Sort-Object LastWriteTime | Select-Object -Last 1
            $state = ''; $detail = ''; $when = $null
            if ($run) { $state = 'running'; $detail = (L "$($run.executor) running" "$($run.executor) 运行中") }
            elseif ($pipe) { $state = 'running'; $detail = (L 'pipeline: verifying / waiting / handing over' '流水线：验收 / 等待 / 换人中') }
            elseif ($recent -and (-not (Test-Path $pj) -or (Get-Item $pj).LastWriteTime -lt $recent.LastWriteTime)) {
                $state = 'between'; $detail = (L 'a round just ended: verifying / rework / handover' '一轮刚结束：验收 / 返工 / 换人中')
            }
            elseif (Test-Path $pj) {
                $r = Get-Content $pj -Raw -Encoding utf8 | ConvertFrom-Json
                $state = $r.result; $when = (Get-Item $pj).LastWriteTime.ToString('s')
                $v = @($r.attempts)[-1].verify
                $detail = "$($r.final_executor)$(if ($v) { ' · ' + ($v -replace '^RESULT\s+\S+\s*:\s*', '') })"
            }
            elseif ($attempts) { $state = 'ran'; $detail = (L "ran $attempts time(s), no pipeline result" "跑过 $attempts 次，没有流水线结果") }
            else { $state = 'todo' }
            [pscustomobject]@{ task = $t; title = Get-TaskTitle $proj $t; state = $state; detail = $detail; when = $when; attempts = $attempts }
        }
        [pscustomobject]@{ project = $proj; name = Split-Path $proj -Leaf; last = if ($last) { $last.ToString('s') }; tasks = @($tasks) }
    }

    [pscustomobject]@{ now = $now.ToString('s'); stall_min = $stallMin; runs = $runs; pipelines = $pipes; boards = @($boards) } |
        ConvertTo-Json -Depth 6 -Compress
}
