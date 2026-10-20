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
function Get-SandboxArgs([switch]$Network, [string[]]$AddDir, [string]$Toolchain) {
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
    foreach ($d in ($dirs | Select-Object -Unique)) { $a += @('--add-dir', $d) }
    $a
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
    '难度' = 'Difficulty'; '升级路径' = 'Escalation'; '状态' = 'Status'
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
        $rows = @(if (Test-Path $script:LedgerPath) { Import-Csv $script:LedgerPath -Encoding utf8 }) + $row
        Save-Ledger $rows
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
    if (-not $p.WaitForExit($TimeoutMin * 60 * 1000)) {
        & taskkill.exe /PID $p.Id /T /F | Out-Null
        Write-Host "[$(Get-Date -Format s)] $Name TIMEOUT after ${TimeoutMin}m, process tree killed"
        Remove-Item $stdin -ErrorAction SilentlyContinue
        return 3
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
