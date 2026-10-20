# Create <Project>\collab\ with brief, board, tasks, reports, logs and local template copies (in the configured language).
param([Parameter(Mandatory)][string]$Project)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tools.ps1')
$tpl = Get-TemplateDir
New-Item -ItemType Directory -Force $Project | Out-Null
$collab = Join-Path (Resolve-Path $Project).Path 'collab'
foreach ($d in 'tasks', 'reports', 'logs', '_templates') { New-Item -ItemType Directory -Force (Join-Path $collab $d) | Out-Null }
Copy-Item (Join-Path $tpl 'task.md'), (Join-Path $tpl 'report.md') (Join-Path $collab '_templates') -Force
foreach ($f in 'brief.md', 'board.md') {
    $dst = Join-Path $collab $f
    if (-not (Test-Path $dst)) { Copy-Item (Join-Path $tpl $f) $dst }
}
"collab ready: $collab ($(Get-CollabLang))"
