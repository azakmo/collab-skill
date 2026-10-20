# Shared helpers for the collab runners. Dot-source this file.

$script:CollabHome = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Get-CodexExe {
    # The Codex desktop app keeps codex.exe under a hashed folder that changes on update.
    $exe = Get-ChildItem "$env:LOCALAPPDATA\OpenAI\Codex\bin" -Recurse -Filter codex.exe -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
    if (-not $exe) { $exe = (Get-Command codex -ErrorAction SilentlyContinue).Source }
    if (-not $exe) { throw 'codex.exe not found' }
    $exe
}

# Toolchain presets: env vars for the executor process plus extra writable dirs (caches outside the project).
# EXAMPLE ONLY — edit the paths to match your machine, or add your own presets.
$script:Toolchains = @{
    android = @{
        Env = [ordered]@{
            JAVA_HOME        = 'C:\dev\Android\jdk-17'
            ANDROID_HOME     = 'C:\dev\Android\Sdk'
            ANDROID_SDK_ROOT = 'C:\dev\Android\Sdk'
            ANDROID_NDK_HOME = 'C:\dev\Android\ndk'
            GOROOT           = 'C:\dev\go-sdk\go'
            GOPATH           = 'C:\dev\go-sdk\gopath'
            GOCACHE          = 'C:\dev\go-sdk\cache'
        }
        Path    = @('C:\dev\go-sdk\go\bin', 'C:\dev\go-sdk\gopath\bin', 'C:\dev\Android\jdk-17\bin',
                    'C:\dev\Android\Sdk\platform-tools', 'C:\dev\Android\Sdk\build-tools\35.0.0', 'C:\dev\Android\gradle\bin')
        AddDirs = @('C:\dev\go-sdk')
    }
}

# Sandbox/network/toolchain options shared by every codex-exec based runner.
# -ForResume: `codex exec resume` has no --add-dir/-s, so extra dirs go in as writable_roots instead.
function Get-SandboxArgs([switch]$Network, [string[]]$AddDir, [string]$Toolchain, [switch]$ForResume) {
    $a = @()
    if ($Network) { $a += @('-c', 'sandbox_workspace_write.network_access=true') }
    $dirs = @($AddDir | Where-Object { $_ })
    if ($Toolchain) {
        $tc = $script:Toolchains[$Toolchain]
        if (-not $tc) { throw "unknown toolchain: $Toolchain (known: $($script:Toolchains.Keys -join ', '))" }
        foreach ($k in $tc.Env.Keys) { Set-Item "env:$k" $tc.Env[$k] }
        $env:PATH = (($tc.Path -join ';') + ';' + $env:PATH)
        $dirs += $tc.AddDirs
    }
    $dirs = @($dirs | Select-Object -Unique)
    if ($ForResume) {
        $a += @('-c', 'sandbox_mode="workspace-write"')
        if ($dirs) { $a += @('-c', ('sandbox_workspace_write.writable_roots=[{0}]' -f (($dirs | ForEach-Object { "'$_'" }) -join ','))) }
    } else {
        foreach ($d in $dirs) { $a += @('--add-dir', $d) }
    }
    $a
}

# Proxy models have no Codex metadata ("Model metadata ... not found. Defaulting to fallback metadata"), so Codex
# assumes a small context window and long runs get compacted (lossy). roster executor "context_window" sets it
# explicitly. (A model_catalog_json would also silence the warning, but it needs a full base system prompt and the
# only ones available are GPT-specific, so Codex's fallback prompt is kept.)
function Get-ContextArgs([object]$Ex, [int]$ContextWindow) {
    if (-not $ContextWindow) { $ContextWindow = [int]$Ex.context_window }
    if (-not $ContextWindow) { return @() }
    @('-c', "model_context_window=$ContextWindow")
}

# Seconds for a correct answer to a tiny question from <Model>, or -1 on error / wrong answer / slower than $TimeoutSec.
# Probe generation itself: /models can answer while generation queues for minutes (upstream "no capacity"), and a
# retired model can return 200 instantly with a canned "no longer available" text that makes Codex loop forever.
function Measure-ModelLatency([object]$Pv, [string]$Model, [int]$TimeoutSec = 20) {
    try {
        $null = Get-ProviderArgs $Pv   # sets the key env var; throws when the endpoint does not answer
        $hdr = @{}
        if ($Pv.env_key) { $hdr.Authorization = "Bearer $([Environment]::GetEnvironmentVariable($Pv.env_key, 'Process'))" }
        # Check the answer, not just the status: retired models still return 200 with a canned
        # "... is no longer available" text.
        $q = 'What is 17+25? Reply with the number only.'
        $sw = [Diagnostics.Stopwatch]::StartNew()
        try {
            $body = @{ model = $Model; max_tokens = 64; messages = @(@{ role = 'user'; content = $q }) } | ConvertTo-Json -Depth 4
            $r = Invoke-RestMethod "$($Pv.base_url)/chat/completions" -Method Post -ContentType 'application/json' -Headers $hdr -Body $body -TimeoutSec $TimeoutSec
            $text = "$($r.choices[0].message.content)"
        } catch {
            # Responses-only providers have no /chat/completions (404/405): ask through /responses instead.
            if ($_.Exception.Response.StatusCode.value__ -notin 404, 405) { throw }
            $left = [Math]::Max(5, $TimeoutSec - [int]$sw.Elapsed.TotalSeconds)
            $body = @{ model = $Model; max_output_tokens = 64; input = $q } | ConvertTo-Json
            $r = Invoke-RestMethod "$($Pv.base_url)/responses" -Method Post -ContentType 'application/json' -Headers $hdr -Body $body -TimeoutSec $left
            $text = if ($r.output_text) { "$($r.output_text)" } else { "$(@($r.output | ForEach-Object { $_.content } | ForEach-Object { $_.text }) -join ' ')" }
        }
        if ($text -notmatch '\b42\b') { return -1 }
        [Math]::Round($sw.Elapsed.TotalSeconds, 1)
    } catch { -1 }
}

# Model to use for this run: the requested/default one, or the first roster "fallback_models" entry (must also be
# in enabled_models) that answers when the default is congested. Built-in Codex: no probe.
function Select-HealthyModel([object]$Sel, [int]$TimeoutSec = 20) {
    if ($Sel.Provider.kind -eq 'codex-builtin') { return $Sel.Model }
    $fallbacks = @($Sel.Executor.fallback_models | Where-Object { $_ -and $_ -ne $Sel.Model -and $_ -in @($Sel.Executor.enabled_models) })
    if (-not $fallbacks) { return $Sel.Model }
    if ((Measure-ModelLatency $Sel.Provider $Sel.Model $TimeoutSec) -ge 0) { return $Sel.Model }
    foreach ($m in $fallbacks) {
        $t = Measure-ModelLatency $Sel.Provider $m $TimeoutSec
        if ($t -ge 0) {
            Write-Host "  WARNING: $($Sel.Model) did not answer within ${TimeoutSec}s (upstream congestion), this run uses fallback $m (${t}s)"
            return $m
        }
    }
    $Sel.Model   # nothing better answers: keep the default; the stall watchdog / resume handle the rest
}

# Is the executor's provider answering with any of its usable models? (built-in Codex: assume yes)
function Test-ProviderHealthy([string]$ExecutorId) {
    try {
        $sel = Resolve-Executor $ExecutorId
        if ($sel.Provider.kind -eq 'codex-builtin') { return $true }
        foreach ($m in @($sel.Model) + @($sel.Executor.fallback_models | Where-Object { $_ -in @($sel.Executor.enabled_models) })) {
            if ((Measure-ModelLatency $sel.Provider $m 60) -ge 0) { return $true }
        }
        $false
    } catch { $false }
}

$script:RosterPath = Join-Path $PSScriptRoot '..\roster.json'

# First run: start from roster.example.json (roster.json is local and git-ignored).
if (-not (Test-Path $script:RosterPath)) { Copy-Item (Join-Path $PSScriptRoot '..\roster.example.json') $script:RosterPath }

function Get-Roster { Get-Content $script:RosterPath -Raw -Encoding utf8 | ConvertFrom-Json }

# Language of templates, executor notes and generated text: $env:COLLAB_LANG, else roster "language", else 'en'.
# Supported: 'en', 'zh-CN'. Task files in either language are parsed regardless of this setting.
function Get-CollabLang {
    $l = $env:COLLAB_LANG
    if (-not $l) { try { $l = (Get-Roster).language } catch {} }
    if ($l -in 'en', 'zh-CN') { $l } else { 'en' }
}

function Get-TemplateDir { Join-Path $PSScriptRoot "..\templates\$(Get-CollabLang)" }

# Pick the text for the current language: L 'English' '中文'
function L([string]$En, [string]$Zh) { if ((Get-CollabLang) -eq 'zh-CN') { $Zh } else { $En } }

# Whitelist gate: the executor must be enabled and the model must be in its enabled_models.
function Resolve-Executor([string]$Id, [string]$Model) {
    $r = Get-Roster
    $ex = $r.executors | Where-Object id -eq $Id
    if (-not $ex) { throw "executor '$Id' is not in roster.json (known: $(($r.executors.id) -join ', '))" }
    if (-not $ex.enabled) { throw "executor '$Id' is disabled in roster.json" }
    if (-not $Model) { $Model = $ex.default_model }
    if ($Model -notin @($ex.enabled_models)) {
        throw "model '$Model' is not enabled for '$Id' in roster.json (enabled: $(@($ex.enabled_models) -join ', ')). Enable it in the console first."
    }
    $pv = $r.providers | Where-Object id -eq $ex.provider
    if (-not $pv) { throw "provider '$($ex.provider)' of executor '$Id' is not in roster.json" }
    [pscustomobject]@{ Executor = $ex; Provider = $pv; Model = $Model }
}

# codex exec -c overrides that point the harness at a roster provider (nothing for the built-in one).
function Get-ProviderArgs([object]$Pv) {
    if ($Pv.kind -eq 'codex-builtin') { return @() }
    if ($Pv.kind -ne 'openai-compatible') { throw "provider kind '$($Pv.kind)' is not runnable" }
    if ($Pv.env_key) {
        $v = [Environment]::GetEnvironmentVariable($Pv.env_key, 'Process')
        if (-not $v) { $v = [Environment]::GetEnvironmentVariable($Pv.env_key, 'User') }
        if (-not $v) { throw "env var $($Pv.env_key) for provider '$($Pv.id)' is not set" }
        Set-Item "env:$($Pv.env_key)" $v
        try { $null = Invoke-RestMethod "$($Pv.base_url)/models" -Headers @{ Authorization = "Bearer $v" } -TimeoutSec 5 }
        catch { throw "provider '$($Pv.id)' not reachable at $($Pv.base_url): $($_.Exception.Message)" }
    }
    $wire = if ($Pv.wire_api) { $Pv.wire_api } else { 'responses' }
    $keyPart = if ($Pv.env_key) { ", env_key = `"$($Pv.env_key)`"" } else { '' }
    @('-c', "model_provider=`"$($Pv.id)`"",
      '-c', "model_providers.$($Pv.id)={ name = `"$($Pv.id)`", base_url = `"$($Pv.base_url)`"$keyPart, wire_api = `"$wire`" }")
}

function Resolve-CollabTask([string]$Project, [string]$Task) {
    $Project = (Resolve-Path $Project).Path
    $collab = Join-Path $Project 'collab'
    $taskFile = Join-Path $collab "tasks\$Task.md"
    if (-not (Test-Path $taskFile)) { throw "task file not found: $taskFile" }
    New-Item -ItemType Directory -Force (Join-Path $collab 'logs'), (Join-Path $collab 'reports'), (Join-Path $collab '_templates') | Out-Null
    # Keep the project's template copies current, so old projects pick up new template sections.
    $tpl = Get-TemplateDir
    Copy-Item (Join-Path $tpl 'task.md'), (Join-Path $tpl 'report.md') (Join-Path $collab '_templates') -Force
    [pscustomobject]@{
        Project = $Project
        Collab  = $collab
        Task    = $Task
        Report  = Join-Path $collab "reports\$Task.md"
        LogBase = Join-Path $collab ("logs\{0}-{1}" -f $Task, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    }
}

function Get-ExecutorPrompt([string]$Task) {
    "You are an executor in a multi-agent workflow coordinated by Claude Code. " +
    "Read the task file collab/tasks/$Task.md (relative to the current working directory) and carry it out exactly, " +
    "obeying its executor rules section. When you finish, or if you get blocked, write your report to " +
    "collab/reports/$Task.md following the template collab/_templates/report.md. Write the report in $(L 'English' 'Chinese') and be honest: " +
    "anything you did not verify must be marked as not verified."
}

function ConvertTo-ArgString([string[]]$ArgList) {
    ($ArgList | ForEach-Object {
        if ($_ -match '[\s"]' -or $_ -eq '') { '"' + ($_ -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' } else { $_ }
    }) -join ' '
}

$script:LedgerPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\ledger.csv'))
$script:LedgerColumns = 'time', 'project', 'task', 'type', 'executor', 'model', 'flags', 'exit', 'minutes', 'tokens', 'self_status', 'review', 'note'

# Task/report fields are written as "- 执行者：x" (zh-CN) or "- Executor: x" (en); both are accepted.
$script:FieldAliases = @{
    '执行者' = 'Executor'; '类型' = 'Type'; '时限' = 'Timeout'; '联网' = 'Network'; '工具链' = 'Toolchain'
    '难度' = 'Difficulty'; '升级路径' = 'Escalation'; '状态' = 'Status'; '依赖' = 'Depends on'
}

function Get-TaskField([string]$File, [string]$Field) {
    if (-not (Test-Path $File)) { return '' }
    $names = @($Field) + @($script:FieldAliases[$Field] | Where-Object { $_ })
    $m = Select-String -Path $File -Pattern "^- (?:$($names -join '|'))\s*[：:]\s*(.+)$" -Encoding utf8 | Select-Object -First 1
    if ($m) { $m.Matches[0].Groups[1].Value.Trim() } else { '' }
}

function Save-Ledger([object[]]$Rows) {
    # UTF-8 with BOM so Excel shows Chinese correctly.
    $Rows | Select-Object $script:LedgerColumns | Export-Csv -Path $script:LedgerPath -NoTypeInformation -Encoding utf8BOM
}

# Read-modify-write of the ledger under a machine-wide lock: run-batch runs pipelines in parallel, and two unlocked
# writers that import the CSV at the same time silently drop each other's rows. $Mutate gets the rows, returns new rows.
function Update-Ledger([scriptblock]$Mutate) {
    Invoke-Locked 'ledger' {
        $rows = @(if (Test-Path $script:LedgerPath) { Import-Csv $script:LedgerPath -Encoding utf8 })
        Save-Ledger @(& $Mutate $rows)
    }
}

# Run $LockBody under the machine-wide mutex Global\collab-<LockName> (shared by parallel pipelines).
function Invoke-Locked([string]$LockName, [scriptblock]$LockBody) {
    $mx = New-Object Threading.Mutex($false, "Global\collab-$LockName")
    try { $null = $mx.WaitOne() } catch [Threading.AbandonedMutexException] {}   # previous holder died: we own it now
    try { & $LockBody } finally { $mx.ReleaseMutex(); $mx.Dispose() }
}

function Add-LedgerRow([object]$Ctx, [string]$Name, [string]$Flags, [int]$Rc, [datetime]$Start, [string]$ErrLog) {
    try {
        $log = if (Test-Path $ErrLog) { Get-Content $ErrLog -Encoding utf8 } else { @() }
        $m = $log | Select-String '^model:\s*(.+)$' | Select-Object -First 1
        $model = if ($m) { $m.Matches[0].Groups[1].Value.Trim() } else { '' }
        $tokIdx = [array]::LastIndexOf([string[]]$log, 'tokens used')
        $tokens = if ($tokIdx -ge 0 -and $tokIdx + 1 -lt $log.Count) { $log[$tokIdx + 1] -replace '[^\d]', '' } else { '' }
        $row = [pscustomobject][ordered]@{
            time        = $Start.ToString('yyyy-MM-dd HH:mm')
            project     = $Ctx.Project
            task        = $Ctx.Task
            type        = Get-TaskField (Join-Path $Ctx.Collab "tasks\$($Ctx.Task).md") '类型'
            executor    = $Name
            model       = $model
            flags       = $Flags
            exit        = $Rc
            minutes     = [math]::Round(((Get-Date) - $Start).TotalMinutes, 1)
            tokens      = $tokens
            self_status = Get-TaskField $Ctx.Report '状态'
            review      = ''
            note        = ''
        }
        Update-Ledger { param($rows) @($rows) + $row }
        Write-Host "  ledger: $($row.executor) $($row.model) tokens=$($row.tokens) $($row.minutes)min"
    } catch { Write-Host "  ledger write failed: $($_.Exception.Message)" }
}

function Invoke-Executor {
    param(
        [string]$Exe, [string[]]$ArgList, [object]$Ctx, [int]$TimeoutMin, [string]$Name, [string]$Flags = ''
    )
    $start = Get-Date
    $rc = Invoke-ExecutorCore -Exe $Exe -ArgList $ArgList -Ctx $Ctx -TimeoutMin $TimeoutMin -Name $Name
    Add-LedgerRow -Ctx $Ctx -Name $Name -Flags $Flags -Rc $rc -Start $start -ErrLog "$($Ctx.LogBase).$Name.err.log"
    $rc
}

# True when the last $Repeat model replies in a codex exec log are identical. In that log every reply starts on the
# line after a line that is exactly "codex"; only the first line of each reply is compared. Reads the last 64 KB only.
function Test-OutputLoop([string]$Path, [int]$Repeat = 6) {
    try {
        $fs = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        try {
            $n = [int][Math]::Min($fs.Length, 65536)
            $null = $fs.Seek(-$n, 'End'); $buf = New-Object byte[] $n; $null = $fs.Read($buf, 0, $n)
        } finally { $fs.Dispose() }
        $lines = [Text.Encoding]::UTF8.GetString($buf) -split "`r?`n"
        $msgs = @(for ($i = 0; $i -lt $lines.Count - 1; $i++) { if ($lines[$i] -ceq 'codex' -and $lines[$i + 1].Trim()) { $lines[$i + 1].Trim() } })
        if ($msgs.Count -lt $Repeat) { return $false }
        @($msgs | Select-Object -Last $Repeat | Select-Object -Unique).Count -eq 1
    } catch { $false }
}

function Invoke-ExecutorCore {
    param(
        [string]$Exe, [string[]]$ArgList, [object]$Ctx, [int]$TimeoutMin, [string]$Name
    )
    $before = if (Test-Path $Ctx.Report) { (Get-Item $Ctx.Report).LastWriteTimeUtc } else { $null }
    $stdin = "$($Ctx.LogBase).stdin"
    Set-Content -Path $stdin -Value '' -NoNewline
    $out = "$($Ctx.LogBase).$Name.out.log"
    $err = "$($Ctx.LogBase).$Name.err.log"
    Write-Host "[$(Get-Date -Format s)] $Name start: task=$($Ctx.Task) timeout=${TimeoutMin}m"
    Write-Host "  log: $out"
    $p = Start-Process -FilePath $Exe -ArgumentList (ConvertTo-ArgString $ArgList) -WorkingDirectory $Ctx.Project `
        -RedirectStandardInput $stdin -RedirectStandardOutput $out -RedirectStandardError $err `
        -NoNewWindow -PassThru
    $null = $p.Handle  # keep the handle so ExitCode is available later
    # Wait in slices. Two watchdogs besides the timeout:
    # - STALLED (4): the log has not grown for $stallMin (request hanging in the proxy). Long silent builds: raise
    #   COLLAB_STALL_MIN. The pipeline resumes the same session.
    # - LOOPING (5): the model's last $loopN replies are identical (e.g. a retired model answering every turn with the
    #   same canned text, so the log keeps growing). COLLAB_LOOP_REPEAT tunes N. The pipeline restarts fresh
    #   (resuming would replay the poisoned context).
    $stallMin = if ($env:COLLAB_STALL_MIN) { [int]$env:COLLAB_STALL_MIN } else { 12 }
    $loopN = if ($env:COLLAB_LOOP_REPEAT) { [int]$env:COLLAB_LOOP_REPEAT } else { 6 }
    $deadline = (Get-Date).AddMinutes($TimeoutMin)
    $lastSize = -1; $lastGrow = Get-Date
    while (-not $p.WaitForExit(30000)) {
        $size = if (Test-Path $err) { (Get-Item $err).Length } else { 0 }
        $grew = $size -ne $lastSize
        if ($grew) { $lastSize = $size; $lastGrow = Get-Date }
        $why = if ((Get-Date) -gt $deadline) { 'timeout' }
            elseif (((Get-Date) - $lastGrow).TotalMinutes -ge $stallMin) { 'stall' }
            elseif ($grew -and (Test-OutputLoop $err $loopN)) { 'loop' }
            else { '' }
        if (-not $why) { continue }
        & taskkill.exe /PID $p.Id /T /F | Out-Null
        Remove-Item $stdin -ErrorAction SilentlyContinue
        switch ($why) {
            'timeout' { Write-Host "[$(Get-Date -Format s)] $Name TIMEOUT after ${TimeoutMin}m, process tree killed"; return 3 }
            'stall' { Write-Host "[$(Get-Date -Format s)] $Name STALLED: no log output for ${stallMin}m, process tree killed"; return 4 }
            'loop' { Write-Host "[$(Get-Date -Format s)] $Name LOOPING: last $loopN model replies identical, process tree killed"; return 5 }
        }
    }
    Remove-Item $stdin -ErrorAction SilentlyContinue
    $code = $p.ExitCode
    $after = if (Test-Path $Ctx.Report) { (Get-Item $Ctx.Report).LastWriteTimeUtc } else { $null }
    Write-Host "[$(Get-Date -Format s)] $Name exit=$code"
    if ($code -ne 0) { return $code }
    if (-not $after -or ($before -and $after -le $before)) {
        Write-Host "  no new report at $($Ctx.Report)"
        return 2
    }
    Write-Host "  report: $($Ctx.Report)"
    return 0
}

# ---- Handover manifests and scope checks ----
# Every accepted task (pipeline PASS) records the SHA-256 of the files it was allowed to change in
# collab/logs/<Task>.manifest.json and in the project-wide collab/handover.json (path -> last accepted state).
# - handover.ps1 -Check: files changed / missing since their last acceptance (a fresh session runs this first).
# - Task field 「依赖」 / "Depends on": run-pipeline refuses to start while a dependency is not accepted or its files changed since.
# - Scope check: run-pipeline snapshots the project around every executor run; changes outside 「允许修改的文件」 ("Files allowed to change") are
#   reported (modified/deleted existing files block the task as NEEDS_CC; new stray files are only a warning).

# Paths listed under 「允许修改的文件」 / "Files allowed to change", relative with / separators; $null when the task has no such section.
function Get-AllowedPaths([string]$TaskFile) {
    $text = Get-Content $TaskFile -Raw -Encoding utf8
    $m = [regex]::Match($text, '(?ms)^## (?:允许修改的文件|Files allowed to change)[^\n]*\n(.*?)(?=^## |\z)')
    if (-not $m.Success) { return $null }
    @(foreach ($l in $m.Groups[1].Value -split "`n") {
        if ($l -match '^\s*-\s+`?([^`\s（(：:，,]+)' -and $Matches[1] -notmatch '\{\{') { ($Matches[1] -replace '^\./', '').Replace('\', '/') }
    })
}

# Is <Rel> covered by the allowed list (exact file, directory prefix, or * / ? glob)? collab/reports and logs always are.
function Test-PathAllowed([string]$Rel, [string[]]$Allowed) {
    $r = $Rel.Replace('\', '/')
    if ($r.StartsWith('collab/reports/', 'OrdinalIgnoreCase') -or $r.StartsWith('collab/logs/', 'OrdinalIgnoreCase')) { return $true }
    foreach ($a in $Allowed) {
        $d = $a.TrimEnd('/')
        if ($r -ieq $d -or $r.StartsWith("$d/", 'OrdinalIgnoreCase')) { return $true }
        if ($a -match '[*?]' -and $r -ilike $a) { return $true }
    }
    $false
}

# path -> "length|mtime" for every project file, skipping build/cache dirs (COLLAB_SNAPSHOT_SKIP adds more names).
$script:SnapshotSkipDirs = @('.git', '.gradle', 'build', 'node_modules', '.idea', '.kotlin', '.cxx', '__pycache__', '.venv', 'venv', '.vs')
function Get-ProjectSnapshot([string]$Project, [int]$MaxFiles = 60000) {
    $skip = $script:SnapshotSkipDirs + @("$env:COLLAB_SNAPSHOT_SKIP" -split '[,;]' | Where-Object { $_ })
    $snap = @{}; $root = $Project.TrimEnd('\').Length + 1
    $stack = [Collections.Generic.Stack[IO.DirectoryInfo]]::new(); $stack.Push([IO.DirectoryInfo]::new($Project))
    while ($stack.Count) {
        $d = $stack.Pop()
        try {
            foreach ($f in $d.EnumerateFiles()) {
                $snap[$f.FullName.Substring($root).Replace('\', '/')] = "$($f.Length)|$($f.LastWriteTimeUtc.Ticks)"
                if ($snap.Count -gt $MaxFiles) { return $null }   # too big to watch: caller skips the scope check
            }
            foreach ($s in $d.EnumerateDirectories()) {
                if ($s.Name -in $skip -or ($s.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
                if ($s.FullName.Substring($root).Replace('\', '/') -ieq 'collab/logs') { continue }
                $stack.Push($s)
            }
        } catch {}
    }
    $snap
}

function Compare-ProjectSnapshot([hashtable]$Before, [hashtable]$After) {
    foreach ($k in $After.Keys) {
        if (-not $Before.ContainsKey($k)) { [pscustomobject]@{ path = $k; change = 'added' } }
        elseif ($Before[$k] -ne $After[$k]) { [pscustomobject]@{ path = $k; change = 'modified' } }
    }
    foreach ($k in $Before.Keys) { if (-not $After.ContainsKey($k)) { [pscustomobject]@{ path = $k; change = 'deleted' } } }
}

# ConvertFrom-Json turns ISO timestamps into [datetime]; show them as yyyy-MM-dd HH:mm:ss either way.
function Format-When($v) { if ($v -is [datetime]) { $v.ToString('yyyy-MM-dd HH:mm:ss') } else { "$v" -replace 'T', ' ' } }

function Get-Sha256([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower() }

# Record an accepted task: its allowed files (dirs/globs expanded, collab/ excluded) with hashes.
function Save-TaskHandover([string]$Project, [string]$Task, [string]$Executor) {
    $allowed = Get-AllowedPaths (Join-Path $Project "collab\tasks\$Task.md")
    if (-not $allowed) { return $null }
    $snap = Get-ProjectSnapshot $Project
    if (-not $snap) { return $null }
    $files = @(foreach ($rel in ($snap.Keys | Where-Object { $_ -notlike 'collab/*' -and (Test-PathAllowed $_ $allowed) } | Sort-Object)) {
        $full = Join-Path $Project $rel
        [pscustomobject]@{ path = $rel; sha256 = Get-Sha256 $full; size = (Get-Item -LiteralPath $full).Length }
    })
    $now = (Get-Date).ToString('s')
    $m = [pscustomobject]@{ task = $Task; executor = $Executor; accepted = $now; files = $files }
    [IO.File]::WriteAllText((Join-Path $Project "collab\logs\$Task.manifest.json"), ($m | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding $false))
    $hf = Join-Path $Project 'collab\handover.json'
    Invoke-Locked 'handover' {
        $h = if (Test-Path $hf) { Get-Content $hf -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable } else { @{ files = @{} } }
        if (-not $h.files) { $h.files = @{} }
        foreach ($f in $files) { $h.files[$f.path] = [ordered]@{ sha256 = $f.sha256; size = $f.size; task = $Task; accepted = $now } }
        $h.updated = $now
        [IO.File]::WriteAllText($hf, ($h | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))
    }
    $m
}

# Accepted files whose content no longer matches their last acceptance. -Tasks: only files those tasks delivered,
# plus a 'not accepted' entry for each of them without a manifest.
function Test-Handover([string]$Project, [string[]]$Tasks) {
    $hf = Join-Path $Project 'collab\handover.json'
    $h = if (Test-Path $hf) { Get-Content $hf -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable } else { @{ files = @{} } }
    $paths = if ($Tasks) {
        foreach ($t in $Tasks) {
            $mf = Join-Path $Project "collab\logs\$t.manifest.json"
            if (-not (Test-Path $mf)) { [pscustomobject]@{ path = ''; change = 'not accepted'; task = $t; accepted = '' }; continue }
            (Get-Content $mf -Raw -Encoding utf8 | ConvertFrom-Json).files.path
        }
    } else { $h.files.Keys }
    foreach ($p in @($paths | Where-Object { $_ -is [string] } | Sort-Object -Unique)) {
        $e = $h.files[$p]; if (-not $e) { continue }
        $full = Join-Path $Project $p
        $change = if (-not (Test-Path -LiteralPath $full)) { 'missing' } elseif ((Get-Sha256 $full) -ne $e.sha256) { 'modified' } else { '' }
        if ($change) { [pscustomobject]@{ path = $p; change = $change; task = $e.task; accepted = $e.accepted } }
    }
    $paths | Where-Object { $_ -isnot [string] }   # the 'not accepted' entries
}
