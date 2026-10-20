---
name: headless-edge-test
description: Render an HTML page with headless Edge and inspect the rendered DOM (Windows; works inside and outside the Codex sandbox).
---

# Headless Edge render check

## Standard snippet (copy as-is)
```powershell
$edge = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
$prof = Join-Path $env:TEMP "edge-prof-$PID"          # separate temp profile, avoids clashing with the user's Edge
$dom  = Join-Path $env:TEMP "edge-dom-$PID.html"
$url  = ([uri](Resolve-Path 'out\page.html').Path).AbsoluteUri   # local file → file:///C:/...; for a local server use http://localhost:port/path
Start-Process $edge -ArgumentList '--headless=new', '--disable-gpu', '--no-sandbox', '--no-first-run',
    "--user-data-dir=$prof", '--virtual-time-budget=5000', '--dump-dom', $url `
    -Wait -RedirectStandardOutput $dom -WindowStyle Hidden
$html = Get-Content $dom -Raw -Encoding utf8
Remove-Item $prof, $dom -Recurse -Force -ErrorAction SilentlyContinue
```

## Key points
- **You must use `Start-Process -Wait -RedirectStandardOutput`.** msedge.exe is a GUI program: with `& $edge ...` PowerShell neither waits for it nor captures stdout, so you get an empty string.
- **In the sandbox `--no-sandbox` is mandatory**, otherwise Edge crashes immediately (exit code -2147483645). It does no harm on the host.
- `--virtual-time-budget=5000` lets the page's JS (including fetch and setTimeout) finish before the DOM is dumped.
- `--dump-dom` outputs the DOM after JS ran (serialized HTML); check it with regexes, e.g. `$html -match '<td>12\.5</td>'`. Escape `<`, `.` etc.
- If the page fetches data from a local server (fetch /api/...): you can't run an HTTP server in the sandbox. Use `HostCheck` for host-only checks, or test with the data embedded in the page.
- Don't use Playwright/Puppeteer/npm packages and don't download Chrome; the local Edge is enough.

## Troubleshooting
- `$html` is empty: check whether you used `&`; check the URL (file:// must use AbsoluteUri).
- JS-generated content missing: look for JS syntax errors in the page source; temporarily add `--enable-logging=stderr --v=0 -RedirectStandardError <file>` to see console errors.
