# Handover check for a collab project: which accepted files changed since their task passed.
# A fresh session runs this first, before trusting the "Current state" section of brief.md.
#   & "$env:COLLAB_HOME\bin\handover.ps1" -Project <dir>              # summary of accepted tasks + check of every accepted file
#   & "$env:COLLAB_HOME\bin\handover.ps1" -Project <dir> -Task T002   # only the files T002 delivered
# Exit: 0 everything matches | 1 something changed / missing / not accepted | 4 nothing accepted yet
param(
    [Parameter(Mandatory)][string]$Project,
    [string[]]$Task
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tools.ps1')
$Project = (Resolve-Path $Project).Path
$hf = Join-Path $Project 'collab\handover.json'
if (-not (Test-Path $hf) -and -not $Task) { "no accepted task yet (collab\handover.json missing)"; exit 4 }

if (-not $Task -and (Test-Path $hf)) {
    $h = Get-Content $hf -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
    "accepted files: $($h.files.Count) (last update $(Format-When $h.updated))"
    $h.files.GetEnumerator() | Group-Object { $_.Value.task } | Sort-Object Name | ForEach-Object {
        "  $($_.Name): $($_.Count) file(s), accepted $(Format-When ($_.Group | ForEach-Object { $_.Value.accepted } | Sort-Object | Select-Object -Last 1))"
    }
}
$issues = @(Test-Handover $Project $Task)
if (-not $issues) { "OK: every accepted file matches its last acceptance"; exit 0 }
"CHANGED since acceptance: $($issues.Count)"
$issues | ForEach-Object {
    if ($_.change -eq 'not accepted') { "  NOT ACCEPTED  $($_.task) (no manifest: the task has not passed)" }
    else { "  {0,-9} {1}  (accepted with {2} at {3})" -f $_.change.ToUpper(), $_.path, $_.task, (Format-When $_.accepted) }
}
exit 1
