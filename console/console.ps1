# 协同控制台：本机网页，编辑 <collab>\roster.json（执行者、模型白名单、分层）；/ledger 是账本页面。
#   pwsh -File "$env:COLLAB_HOME\console\console.ps1"            # 打开 http://localhost:8790/
# 只监听本机；密钥只按环境变量名读取，永远不返回给网页。按 Ctrl+C 退出。
param([int]$Port = 8790, [switch]$NoBrowser)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\bin\tools.ps1')
. (Join-Path $PSScriptRoot 'ledger-stats.ps1')

$html = Join-Path $PSScriptRoot 'console.html'
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "协同控制台已启动：http://localhost:$Port/  （Ctrl+C 退出）"
if (-not $NoBrowser) { Start-Process "http://localhost:$Port/" }

function Send($ctx, [int]$code, [string]$type, [string]$body) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($body)
    $ctx.Response.StatusCode = $code
    $ctx.Response.ContentType = "$type; charset=utf-8"
    $ctx.Response.Headers['Cache-Control'] = 'no-store'
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $ctx.Response.Close()
}
function SendJson($ctx, $obj, [int]$code = 200) { Send $ctx $code 'application/json' ($obj | ConvertTo-Json -Depth 10 -Compress) }

function Get-EnvValue([string]$name) {
    if (-not $name) { return $null }
    $v = [Environment]::GetEnvironmentVariable($name, 'Process')
    if (-not $v) { $v = [Environment]::GetEnvironmentVariable($name, 'User') }
    $v
}

function Invoke-Probe($pv) {
    switch ($pv.kind) {
        'codex-builtin' {
            $home_ = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { [Environment]::GetEnvironmentVariable('CODEX_HOME', 'User') }
            if (-not $home_) { $home_ = Join-Path $env:USERPROFILE '.codex' }
            $cache = Join-Path $home_ 'models_cache.json'
            if (-not (Test-Path $cache)) { throw "找不到 $cache（先在 Codex 里用一次）" }
            return @((Get-Content $cache -Raw -Encoding utf8 | ConvertFrom-Json).models | ForEach-Object { $_.slug })
        }
        'openai-compatible' {
            $h = @{}
            if ($pv.env_key) {
                $k = Get-EnvValue $pv.env_key
                if (-not $k) { throw "环境变量 $($pv.env_key) 没有设置" }
                $h.Authorization = "Bearer $k"
            }
            $r = Invoke-RestMethod "$($pv.base_url.TrimEnd('/'))/models" -Headers $h -TimeoutSec 10
            $list = if ($r.data) { $r.data } elseif ($r.models) { $r.models } else { $r }
            return @($list | ForEach-Object { if ($_.id) { $_.id } elseif ($_.name) { $_.name } else { "$_" } })
        }
        default { throw "未知的 provider 类型：$($pv.kind)" }
    }
}

function Test-Roster($r) {
    if (-not $r.providers -or -not $r.executors) { throw 'roster 必须包含 providers 和 executors' }
    $pids = @($r.providers.id)
    foreach ($p in $r.providers) {
        if ($p.id -notmatch '^[a-z][a-z0-9_-]*$') { throw "provider id 只能用小写字母、数字、- 和 _：$($p.id)" }
        if ($p.kind -eq 'openai-compatible' -and $p.base_url -notmatch '^https?://') { throw "provider $($p.id) 的 base_url 必须以 http:// 或 https:// 开头" }
        if ($p.env_key -and $p.env_key -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { throw "provider $($p.id) 的 env_key 只能是环境变量名，不能填密钥本身" }
    }
    foreach ($e in $r.executors) {
        if ($e.id -notmatch '^[a-z][a-z0-9_-]*$') { throw "执行者 id 只能用小写字母、数字、- 和 _：$($e.id)" }
        if ($e.provider -notin $pids) { throw "执行者 $($e.id) 引用了不存在的 provider：$($e.provider)" }
        if ($e.layer -notin 'impl', 'labor') { throw "执行者 $($e.id) 的 layer 只能是 impl 或 labor" }
        if ($e.enabled -and @($e.enabled_models).Count -eq 0) { throw "执行者 $($e.id) 已启用，但一个模型都没勾选" }
        if ($e.enabled -and $e.default_model -notin @($e.enabled_models)) { throw "执行者 $($e.id) 的默认模型必须在已勾选的模型里" }
    }
}

try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        $req = $ctx.Request
        try {
            $path = $req.Url.AbsolutePath
            if ($req.HttpMethod -eq 'GET' -and $path -eq '/') { Send $ctx 200 'text/html' (Get-Content $html -Raw -Encoding utf8); continue }
            if ($req.HttpMethod -eq 'GET' -and $path -eq '/ledger') {
                $ledgerHtml = Join-Path $PSScriptRoot 'ledger.html'
                if (Test-Path $ledgerHtml) {
                    Send $ctx 200 'text/html' (Get-Content $ledgerHtml -Raw -Encoding utf8)
                } else {
                    Send $ctx 404 'text/plain' 'ledger.html 不存在'
                }
                continue
            }
            # Every API call needs the custom header: browsers cannot send it cross-site without a preflight we never answer.
            if ($req.Headers['X-Collab'] -ne '1') { SendJson $ctx @{ error = 'forbidden' } 403; continue }
            $body = if ($req.HasEntityBody) { [IO.StreamReader]::new($req.InputStream, [Text.Encoding]::UTF8).ReadToEnd() } else { '' }

            if ($req.HttpMethod -eq 'GET' -and $path -eq '/api/ledger') {
                Send $ctx 200 'application/json' (Get-LedgerStatsJson $script:LedgerPath)
            }
            elseif ($req.HttpMethod -eq 'GET' -and $path -eq '/api/roster') {
                $r = Get-Roster
                $envState = @{}
                foreach ($p in $r.providers) { if ($p.env_key) { $envState[$p.env_key] = [bool](Get-EnvValue $p.env_key) } }
                SendJson $ctx @{ roster = $r; env = $envState }
            }
            elseif ($req.HttpMethod -eq 'POST' -and $path -eq '/api/probe') {
                $pv = $body | ConvertFrom-Json
                try { SendJson $ctx @{ models = @(Invoke-Probe $pv) } }
                catch { SendJson $ctx @{ error = $_.Exception.Message } 200 }
            }
            elseif ($req.HttpMethod -eq 'POST' -and $path -eq '/api/roster') {
                $r = $body | ConvertFrom-Json
                try { Test-Roster $r } catch { SendJson $ctx @{ error = $_.Exception.Message } 400; continue }
                Copy-Item $script:RosterPath "$($script:RosterPath).bak" -Force
                $json = ($r | ConvertTo-Json -Depth 10) -replace "`r`n", "`n"
                [IO.File]::WriteAllText($script:RosterPath, $json + "`n", (New-Object Text.UTF8Encoding $false))
                SendJson $ctx @{ ok = $true }
            }
            else { SendJson $ctx @{ error = 'not found' } 404 }
        } catch {
            try { SendJson $ctx @{ error = $_.Exception.Message } 500 } catch {}
        }
    }
} finally { $listener.Stop() }
