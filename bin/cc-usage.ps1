# CC's own token spend, read from the Claude Code transcript (the controller is the biggest cost, so measure it).
#   & "$env:COLLAB_HOME\bin\cc-usage.ps1" -Since '2026-10-15 15:00' [-Transcript <jsonl>] [-Record -Project <dir> -Task <label>]
# Default transcript: the most recently written one (= the active session when CC runs this itself).
# "equiv" = input-price-equivalent tokens: input + cache_write*1.25 + cache_read*0.1 + output*5.
param(
    [Parameter(Mandatory)][datetime]$Since,
    [datetime]$Until = (Get-Date),
    [string]$Transcript,
    [switch]$Record,
    [string]$Project,
    [string]$Task = 'CC'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tools.ps1')

if (-not $Transcript) {
    $Transcript = Get-ChildItem (Join-Path $env:USERPROFILE '.claude\projects') -Recurse -Filter *.jsonl |
        Where-Object { $_.FullName -notmatch '\\subagents\\' } | Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}
$s = $Since.ToUniversalTime(); $u = $Until.ToUniversalTime()
$seen = @{}; $calls = 0; $in = 0L; $cr = 0L; $cw = 0L; $out = 0L; $model = ''
foreach ($line in [IO.File]::ReadLines($Transcript)) {
    if ($line -notmatch '"usage"') { continue }
    $o = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
    if (-not $o.message.usage -or -not $o.timestamp) { continue }
    $t = ([datetime]$o.timestamp).ToUniversalTime()
    if ($t -lt $s -or $t -gt $u) { continue }
    if ($seen.ContainsKey($o.message.id)) { continue }
    $seen[$o.message.id] = 1
    $x = $o.message.usage
    $calls++; $in += $x.input_tokens; $cr += $x.cache_read_input_tokens; $cw += $x.cache_creation_input_tokens; $out += $x.output_tokens
    if ($o.message.model) { $model = $o.message.model }
}
$total = $in + $cr + $cw + $out
$equiv = [long]($in + $cw * 1.25 + $cr * 0.1 + $out * 5)
$avgCtx = if ($calls) { [long](($in + $cr + $cw) / $calls) } else { 0 }
"CC usage $($Since.ToString('MM-dd HH:mm'))–$($Until.ToString('MM-dd HH:mm'))  model=$model"
"  calls=$calls  avg_context=$avgCtx  output=$out  cache_read=$cr  cache_write=$cw  input=$in"
"  total=$total  equiv=$equiv"

if ($Record) {
    if (-not $Project) { throw '-Record needs -Project' }
    $Project = (Resolve-Path $Project).Path
    $row = [pscustomobject][ordered]@{
        time = $Since.ToString('yyyy-MM-dd HH:mm'); project = $Project; task = $Task; type = '主控'
        executor = 'cc'; model = $model; flags = ''; exit = 0
        minutes = [math]::Round(($Until - $Since).TotalMinutes, 1); tokens = $total
        self_status = ''; review = ''; note = "calls=$calls avg_ctx=$avgCtx out=$out equiv=$equiv"
    }
    Save-Ledger (@(if (Test-Path $script:LedgerPath) { Import-Csv $script:LedgerPath -Encoding utf8 }) + $row)
    "  recorded to ledger as executor=cc task=$Task"
}
