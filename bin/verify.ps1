# Run the 「验收测试」 block of collab/tasks/<Task>.md in the project root and print only PASS/FAIL lines.
# CC's final review starts here: one call, a few lines of output, no code reading needed when all pass.
#   & "$env:COLLAB_HOME\bin\verify.ps1" -Project <dir> -Task T00n [-Mark]   (-Mark writes 通过/返工 into ledger.csv)
param(
    [Parameter(Mandatory)][string]$Project,
    [Parameter(Mandatory)][string]$Task,
    [int]$TimeoutSec = 600,
    [switch]$Mark
)
$ErrorActionPreference = 'Stop'
$Project = (Resolve-Path $Project).Path
$taskFile = Join-Path $Project "collab\tasks\$Task.md"
$md = Get-Content $taskFile -Raw -Encoding utf8
$m = [regex]::Match($md, '(?s)## 验收测试.*?```powershell\r?\n(.*?)\r?\n```')
if (-not $m.Success) { "no 验收测试 block in $taskFile"; exit 4 }

$script = Join-Path $Project "collab\logs\$Task.verify.ps1"
New-Item -ItemType Directory -Force (Split-Path $script) | Out-Null
[IO.File]::WriteAllText($script, $m.Groups[1].Value, (New-Object Text.UTF8Encoding $true))
$out = Join-Path $Project "collab\logs\$Task.verify.log"

$p = Start-Process pwsh -ArgumentList "-NoProfile -File `"$script`"" -WorkingDirectory $Project `
    -RedirectStandardOutput $out -RedirectStandardError "$out.err" -NoNewWindow -PassThru
$null = $p.Handle
if (-not $p.WaitForExit($TimeoutSec * 1000)) { & taskkill.exe /PID $p.Id /T /F | Out-Null; "TIMEOUT after ${TimeoutSec}s"; exit 3 }
$rc = $p.ExitCode

$lines = @(Get-Content $out -Encoding utf8 -ErrorAction SilentlyContinue)
$lines | Where-Object { $_ -match '^(PASS|FAIL)' } | ForEach-Object { $_.Substring(0, [Math]::Min(200, $_.Length)) }
$errTail = @(Get-Content "$out.err" -Encoding utf8 -ErrorAction SilentlyContinue) | Select-Object -Last 5
if ($errTail) { '--- stderr (last 5):'; $errTail }
$pass = @($lines | Where-Object { $_ -match '^PASS' }).Count
$fail = @($lines | Where-Object { $_ -match '^FAIL' }).Count
"RESULT $Task : $pass pass, $fail fail, exit $rc"

if ($Mark) {
    $verdict = if ($rc -eq 0 -and $fail -eq 0) { '通过' } else { '返工' }
    & (Join-Path $PSScriptRoot 'ledger-mark.ps1') -Project $Project -Task $Task -Review $verdict -Note "verify: $pass pass / $fail fail"
}
exit $rc
