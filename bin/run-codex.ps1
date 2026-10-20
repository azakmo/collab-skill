# Shortcut for run-executor.ps1 -Executor codex (see roster.json for its enabled models).
param(
    [Parameter(Mandatory)][string]$Project,
    [Parameter(Mandatory)][string]$Task,
    [int]$TimeoutMin = 30,
    [string]$Model,
    [switch]$Network,
    [string[]]$AddDir,
    [string]$Toolchain
)
& (Join-Path $PSScriptRoot 'run-executor.ps1') -Executor codex @PSBoundParameters
exit $LASTEXITCODE
