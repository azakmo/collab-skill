# Shortcut for run-executor.ps1 -Executor gemini (Codex harness + an OpenAI-compatible proxy, see roster.json).
param(
    [Parameter(Mandatory)][string]$Project,
    [Parameter(Mandatory)][string]$Task,
    [int]$TimeoutMin = 20,
    [string]$Model,
    [switch]$Network,
    [string[]]$AddDir,
    [string]$Toolchain
)
if (-not $PSBoundParameters.ContainsKey('TimeoutMin')) { $PSBoundParameters['TimeoutMin'] = $TimeoutMin }
& (Join-Path $PSScriptRoot 'run-executor.ps1') -Executor gemini @PSBoundParameters
exit $LASTEXITCODE
