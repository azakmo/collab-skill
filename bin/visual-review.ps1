# Visual acceptance: an executor with vision looks at the task's screenshots against its visual checklist
# (section "## Visual acceptance" or "## 视觉验收"). Run by run-pipeline after the acceptance tests pass; also by hand.
#   & "$env:COLLAB_HOME\bin\visual-review.ps1" -Project <dir> -Task T00n [-Executor gemini] [-TimeoutMin 10]
# Writes collab/logs/<Task>.visual.md (verdict) and collab/logs/<Task>.contact.png (one contact sheet for CC).
# Exit: 0 PASS | 1 FAIL (issue lines printed) | 4 task has no visual section | 5 no screenshots | other = reviewer error
param(
    [Parameter(Mandatory)][string]$Project,
    [Parameter(Mandatory)][string]$Task,
    [string]$Executor = 'gemini',
    [int]$TimeoutMin = 10,
    [int]$MaxImages = 16
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tools.ps1')
$Project = (Resolve-Path $Project).Path
$taskFile = Join-Path $Project "collab\tasks\$Task.md"
$text = Get-Content $taskFile -Raw -Encoding utf8
$m = [regex]::Match($text, '(?ms)^## (?:视觉验收|Visual acceptance)[^\n]*\n(.*?)(?=^## |\z)')
if (-not $m.Success) { "no visual acceptance section in $taskFile"; exit 4 }
$section = $m.Groups[1].Value.Trim()
function Get-Field([string[]]$names) {
    $f = [regex]::Match($section, "(?m)^- (?:$($names -join '|'))\s*[：:]\s*(.+)$")
    if ($f.Success) { $f.Groups[1].Value.Trim() -replace '`', '' } else { '' }
}

$shotDir = Join-Path $Project (Get-Field '截图目录', 'Screenshot dir')
$shots = @(if (Test-Path $shotDir) { Get-ChildItem $shotDir -Recurse -File -Include *.png, *.jpg, *.jpeg, *.webp | Sort-Object FullName })
if (-not $shots) { "VISUAL RESULT: FAIL`nFAIL no screenshots in $shotDir"; exit 5 }
$refs = @((Get-Field '参考图', 'Reference images') -split '[,，;；]' | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notin '无', 'none' } |
    ForEach-Object { Join-Path $Project $_ } | Where-Object { Test-Path $_ } | ForEach-Object { Get-Item $_ })
if ($shots.Count + $refs.Count -gt $MaxImages) { $shots = $shots | Select-Object -First ($MaxImages - $refs.Count) }

# Contact sheet: every screenshot scaled to 480px tall, 4 per row, file name under each. CC looks at this one image.
Add-Type -AssemblyName System.Drawing
$h = 480; $pad = 12; $label = 28; $cols = [Math]::Min(4, $shots.Count)
$imgs = foreach ($s in $shots) { $i = [Drawing.Image]::FromFile($s.FullName); [pscustomobject]@{ Img = $i; W = [int]($i.Width * $h / $i.Height); Name = $s.Name } }
$cellW = ($imgs | Measure-Object W -Maximum).Maximum
$rows = [Math]::Ceiling($imgs.Count / $cols)
$sheet = New-Object Drawing.Bitmap ([int]($cols * ($cellW + $pad) + $pad)), ([int]($rows * ($h + $label + $pad) + $pad))
$g = [Drawing.Graphics]::FromImage($sheet); $g.Clear([Drawing.Color]::FromArgb(128, 128, 128))
$g.InterpolationMode = 'HighQualityBicubic'; $font = New-Object Drawing.Font 'Segoe UI', 12
for ($k = 0; $k -lt $imgs.Count; $k++) {
    $x = $pad + ($k % $cols) * ($cellW + $pad); $y = $pad + [Math]::Floor($k / $cols) * ($h + $label + $pad)
    $g.DrawImage($imgs[$k].Img, $x, $y, $imgs[$k].W, $h)
    $g.DrawString($imgs[$k].Name, $font, [Drawing.Brushes]::White, $x, $y + $h + 4)
    $imgs[$k].Img.Dispose()
}
$contact = Join-Path $Project "collab\logs\$Task.contact.png"
$sheet.Save($contact, [Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $sheet.Dispose()

# Reviewer: read-only, no tools needed; images go in with -i in this order (references first).
$sel = Resolve-Executor $Executor
$all = @($refs) + @($shots)
$list = ($all | ForEach-Object -Begin { $n = 0 } -Process { $n++; $kind = if ($_ -in $refs) { 'reference' } else { 'screenshot' }; "$n. [$kind] $($_.Name)" }) -join "`n"
$prompt = @"
You are a visual acceptance reviewer. The attached images are in this order (references are design mockups,
screenshots are the executor's actual output):
$list

Check every screenshot against the visual acceptance requirements below. Judge only what is actually visible in the
image; check numbers, proportions and text item by item, do not pass something just because it looks roughly right.
---
$section
---
Output exactly this format and nothing else$(L '' ' (write the problem descriptions in Chinese)'):
One line per screenshot: "PASS <file name>" or "FAIL <file name>: <concrete problem: what you see, what it should be>"
Last line: "VISUAL RESULT: PASS" (all passed) or "VISUAL RESULT: FAIL"
"@
$out = Join-Path $Project "collab\logs\$Task.visual.md"
$errLog = Join-Path $Project "collab\logs\$Task.visual.err.log"
$argList = @('exec', '--skip-git-repo-check', '--ephemeral', '--color', 'never', '--ignore-user-config',
    '-c', 'skills.include_instructions=false') + (Get-ProviderArgs $sel.Provider) + (Get-ContextArgs $sel.Executor 0) +
    @('-m', $sel.Model, '-s', 'read-only', '-C', $Project, '-o', $out)
foreach ($a in $all) { $argList += @('-i', $a.FullName) }
$argList += @('--', $prompt)
if (Test-Path $out) { Remove-Item $out }
$stdin = Join-Path $Project "collab\logs\$Task.visual.stdin"; Set-Content $stdin '' -NoNewline
$p = Start-Process -FilePath (Get-CodexExe) -ArgumentList (ConvertTo-ArgString $argList) -WorkingDirectory $Project `
    -RedirectStandardInput $stdin -RedirectStandardOutput (Join-Path $Project "collab\logs\$Task.visual.out.log") `
    -RedirectStandardError $errLog -NoNewWindow -PassThru
$null = $p.Handle
if (-not $p.WaitForExit($TimeoutMin * 60000)) { & taskkill.exe /PID $p.Id /T /F | Out-Null; "visual reviewer timeout"; exit 3 }
Remove-Item $stdin -ErrorAction SilentlyContinue
if (-not (Test-Path $out)) { "visual reviewer gave no verdict (exit $($p.ExitCode)), see $errLog"; exit 6 }
$verdict = Get-Content $out -Encoding utf8
$verdict | Where-Object { $_ -match '^(PASS|FAIL|VISUAL RESULT)' }
"contact sheet: $contact"
$res = $verdict | Where-Object { $_ -match '^VISUAL RESULT:\s*(PASS|FAIL)' } | Select-Object -Last 1
if (-not $res) { "visual reviewer output not in the expected format, see $out"; exit 6 }
if ($res -match 'PASS' -and -not ($verdict -match '^FAIL')) { exit 0 } else { exit 1 }
