# Delegate reading / log digging / research to an executor and get back a short cited summary,
# so CC never has to load the raw material into its own context.
#   & "$env:COLLAB_HOME\bin\ask.ps1" -Project <dir> -Question '...' [-Files a,b] [-Network] [-Executor gemini|codex]
# Writes collab/tasks/R<timestamp>.md, runs it, prints only the report.
param(
    [Parameter(Mandatory)][string]$Project,
    [Parameter(Mandatory)][string]$Question,
    [string[]]$Files,
    [string]$Executor = 'gemini',   # any enabled executor id in roster.json
    [switch]$Network,
    [int]$MaxWords = 400,
    [int]$TimeoutMin = 15
)
$ErrorActionPreference = 'Stop'
$Project = (Resolve-Path $Project).Path
if (-not (Test-Path (Join-Path $Project 'collab\_templates\report.md'))) { & (Join-Path $PSScriptRoot 'init-collab.ps1') -Project $Project | Out-Null }

$id = 'R' + (Get-Date -Format 'yyyyMMdd-HHmmss')
# Two asks started in the same second must not share (and overwrite) one task file: claim the first free suffix atomically.
$tasksDir = Join-Path $Project 'collab\tasks'
for ($n = 0; ; $n++) {
    $try = if ($n) { "$id-$n" } else { $id }
    try { [IO.File]::Open((Join-Path $tasksDir "$try.md"), 'CreateNew').Dispose(); $id = $try; break }
    catch [IO.IOException] { if ($n -ge 50) { throw } }
}
. (Join-Path $PSScriptRoot 'tools.ps1')
$inputsEn = if ($Files) { ($Files | ForEach-Object { "- $_" }) -join "`n" } else { '- Find the relevant files in the project directory yourself' }
$netEn = if ($Network) { 'yes: only for reading web pages/docs (Invoke-WebRequest / curl on public pages); no uploads, no logins' } else { 'no' }
$taskEn = @"
# ${id}: research / reading

- Executor: $Executor
- Type: research
- Timeout: $TimeoutMin minutes
- Network: $netEn
- Toolchain: none

## Background
The controller (Claude Code) does not want to read the raw material itself; you read it and return a short summary. The controller only sees your report, so it must be self-contained and accurate.

## Question
$Question

## Inputs
$inputsEn

## Files allowed to change
- collab/reports/$id.md (report)

## Steps
1. Read only, change nothing: read the inputs (for large files use Select-String / ranged reads, don't print whole files); search for related files or web pages if needed.
2. Answer the "Question".

## Report format (replaces the "What was done" section of the template)
- First a "Conclusion": answer the question directly, at most $MaxWords words.
- Then "Evidence": every key point with its source — files as ``path:line``, web pages as URL; quote a short excerpt (one line max) where possible.
- Anything uncertain or not found: say "not found / uncertain" explicitly; don't guess.
- "Files changed" lists only the report itself.

## Executor rules (do not modify this section)
- Only change files listed in "Files allowed to change".
- Do not connect over SSH, do not access routers, VPSes or any remote server, do not deploy, publish or send messages.
- When network is allowed, only read public web pages/docs; do not upload anything, do not log in anywhere, do not download executables.
- When done, write the report to collab/reports/$id.md following collab/_templates/report.md (in English). Mark anything not verified as not verified.
"@
$inputsZh = if ($Files) { ($Files | ForEach-Object { "- $_" }) -join "`n" } else { '- 自行在项目目录中查找相关文件' }
$netZh = if ($Network) { '是：只用于读取网页/文档（可用 Invoke-WebRequest / curl 抓取公开页面），不上传、不登录' } else { '否' }
$taskZh = @"
# ${id}：调研 / 阅读

- 执行者：$Executor
- 类型：调研
- 时限：$TimeoutMin 分钟
- 联网：$netZh
- 工具链：无

## 背景
主控（Claude Code）不想亲自读原始材料，由你代读并交回一份短摘要。主控只看你的回报，所以回报必须自足、准确。

## 问题
$Question

## 输入
$inputsZh

## 允许修改的文件
- collab/reports/$id.md（回报）

## 要做什么
1. 只读不改：阅读输入材料（大文件用 Select-String / 分段读取，不要整个打印），需要时自己搜索相关文件或网页。
2. 回答「问题」。

## 回报格式（覆盖通用模板的「做了什么」一节）
- 先写「结论」：直接回答问题，不超过 $MaxWords 字。
- 再写「依据」：每条关键结论附出处——文件用 ``路径:行号``，网页用 URL；能引用原文就引用一小段（一行以内）。
- 不确定或没找到的，明确写「未找到 / 不确定」，不要猜。
- 「修改的文件」只写回报本身。

## 执行者守则（不要改动这一节）
- 只修改「允许修改的文件」里列出的文件。
- 不要连接 SSH，不要访问路由器、VPS 或任何远程服务器，不要部署、发布、发消息。
- 允许联网时，只读取公开网页/文档；不要上传任何东西，不要登录任何服务，不要下载可执行程序。
- 完成后按 collab/_templates/report.md 写回报到 collab/reports/$id.md（中文）。没验证的就写没验证。
"@
$task = L $taskEn $taskZh
[IO.File]::WriteAllText((Join-Path $Project "collab\tasks\$id.md"), ($task -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding $false))

& (Join-Path $PSScriptRoot 'run-executor.ps1') -Executor $Executor -Project $Project -Task $id -TimeoutMin $TimeoutMin -Network:$Network | Out-Host
$rc = $LASTEXITCODE
$report = Join-Path $Project "collab\reports\$id.md"
if (Test-Path $report) { Get-Content $report -Encoding utf8 } else { "no report (exit $rc)" }
exit $rc
