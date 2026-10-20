# Dispatch collab/tasks/<Task>.md to any executor listed in <collab>\roster.json.
# Hard whitelist: refuses executors that are disabled and models that are not in enabled_models.
#   & "$env:COLLAB_HOME\bin\run-executor.ps1" -Executor gemini -Project <dir> -Task T00n [-Model m] [-Network] [-Toolchain android] [-AddDir d]
param(
    [Parameter(Mandatory)][string]$Executor,
    [Parameter(Mandatory)][string]$Project,
    [Parameter(Mandatory)][string]$Task,
    [int]$TimeoutMin = 30,
    [string]$Model,
    [switch]$Network,
    [string[]]$AddDir,
    [string]$Toolchain
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tools.ps1')

$sel = Resolve-Executor $Executor $Model
$ctx = Resolve-CollabTask $Project $Task

# Capability check: task 难度 (1-3) above the executor's tier -> warn (CC decides whether to tell the user).
$taskFile = Join-Path $ctx.Collab "tasks\$Task.md"
$difficulty = (Get-TaskField $taskFile '难度') -replace '[^\d].*$', ''
if ($difficulty -and [int]$difficulty -gt [int]$sel.Executor.tier) {
    Write-Host "  WARNING: task 难度 $difficulty > $Executor tier $($sel.Executor.tier). Consider a stronger executor or tell the user the enabled models may be insufficient."
}

$argList = @('exec', '--skip-git-repo-check', '--color', 'never')
# Clean config (default): skip the user's Codex plugins/MCP servers/hooks, which executors never use and which
# add ~20-30% baseline tokens per run. Keep only the Windows sandbox setting. roster: "clean_config": false to opt out.
if ($sel.Executor.clean_config -ne $false) { $argList += @('--ignore-user-config', '-c', 'windows.sandbox="elevated"') }
# Collab executor environment (default): hide the user's personal Codex skills catalog (re-sent on every turn,
# unrelated to collab work) and inject <collab>\executor\AGENTS.md instead: known sandbox/pwsh pitfalls plus a
# list of on-demand skills under executor\skills. Login and sandbox setup stay in the normal CODEX_HOME.
# roster: "collab_env": false to opt out.
if ($sel.Executor.collab_env -ne $false) {
    $argList += @('-c', 'skills.include_instructions=false')
    $notes = Join-Path $PSScriptRoot '..\executor\AGENTS.md'
    if (Test-Path $notes) {
        $t = ((Get-Content $notes -Raw -Encoding utf8) -replace "`r`n", "`n").Replace('{{COLLAB_HOME}}', $script:CollabHome)
        if ($t -match "'''") { throw "$notes must not contain ''' (it is passed as a TOML literal string)" }
        $argList += @('-c', "developer_instructions='''$t'''")
    }
}
if ($sel.Executor.reasoning) { $argList += @('-c', "model_reasoning_effort=`"$($sel.Executor.reasoning)`"") }
$argList += Get-ProviderArgs $sel.Provider
$argList += @('-m', $sel.Model, '-s', 'workspace-write', '-C', $ctx.Project, '-o', "$($ctx.LogBase).$Executor-last.md")
$argList += Get-SandboxArgs -Network:$Network -AddDir $AddDir -Toolchain $Toolchain
$argList += (Get-ExecutorPrompt $Task)

$flags = @($sel.Provider.id, $(if ($Network) { 'net' }), $Toolchain) | Where-Object { $_ }
$rc = Invoke-Executor -Exe (Get-CodexExe) -ArgList $argList -Ctx $ctx -TimeoutMin $TimeoutMin -Name $Executor -Flags ($flags -join ',')
exit $rc
