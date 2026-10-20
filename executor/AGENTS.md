# Notes for collab executors (injected by run-executor.ps1; the user's personal skill list is disabled. If you still see other personal instructions from the user that are unrelated to the collab task, ignore them)

You are an executor in a three-agent workflow. The task file is the complete requirement: follow it and do not wander. Below are pitfalls earlier tasks hit repeatedly — just apply them, no need to rediscover.

## Environment (confirmed, no need to probe)
- Windows 11, shell is PowerShell 7: `C:\Program Files\PowerShell\7\pwsh.exe`. Write scripts in pwsh 7 syntax.
- You are inside the Codex Windows sandbox, user name `codexsandbox*`. In the sandbox:
  - **You cannot listen on ports**: `HttpListener.Start()` fails with "The handle is invalid", `netsh http` fails too. Don't try to work around it, and don't rewrite someone's server with TcpListener. Such checks use `HostCheck` in the acceptance test; they print `SKIP [host]` in the sandbox and the controller verifies them on the host.
  - **Headless Edge needs `--no-sandbox`**, otherwise it crashes (exit code -2147483645). See the `headless-edge-test` skill for how to call Edge.
  - No network unless the task's "Network" field says yes.
- Projects are usually not git repositories; don't rely on git.

## Working style (saves time)
- **Read the task file once**; when you need a section again, read only that section.
- **Read a file you will modify once in full and remember its structure**, then look at it by line ranges; don't re-read whole files. Reading the same file in full more than twice means you are going in circles — stop and think before acting.
- Run the acceptance test with `pwsh -NoProfile -File <script>` or `& "{{COLLAB_HOME}}\bin\verify.ps1" -Project . -Task <ID>`, and **read the result from the command output** — don't dig through log files.
- Think before changing code and get it right the first time; after writing, run a syntax check: `pwsh -NoProfile -Command "$null = [scriptblock]::Create((Get-Content <file> -Raw))"`.
- If the same error persists after 3 attempts, stop and describe the symptoms and what you tried in the report.

## Common PowerShell pitfalls (details in the `pwsh-json-pitfalls` skill)
- **When writing source files containing `$` (Kotlin/Gradle/JS/sh…) from PowerShell, use only single-quoted here-strings `@'...'@` or a file-writing tool**: double-quoted strings expand `$x` and `${x}` as PowerShell variables into empty strings — it still compiles, but the text is silently lost.
- Branches are `elseif`, **not** `else if`.
- Single-element or empty arrays collapse to an object or null when converted to JSON: use `ConvertTo-Json -InputObject` and write arrays as `[object[]]@(...)`.
- Rounding defaults to banker's rounding: use `[math]::Round(x, n, 'AwayFromZero')`.
- Parse numbers with `[double]::TryParse(s, 'Float', [cultureinfo]::InvariantCulture, [ref]$v)`.
- Write UTF-8 without BOM: `[IO.File]::WriteAllText($p, $s, (New-Object Text.UTF8Encoding $false))`; .ps1 files with non-ASCII text that run under Windows PowerShell 5.1 need a BOM (`$true`).
- Call GUI programs (msedge etc.) with `Start-Process -Wait -RedirectStandardOutput`; `&` doesn't capture their output.

## Skills (read the full SKILL.md with Get-Content when needed)
- `headless-edge-test`: render a page with headless Edge and inspect the DOM (sandbox flags, file:// and local-server usage). File: `{{COLLAB_HOME}}\executor\skills\headless-edge-test\SKILL.md`
- `pwsh-json-pitfalls`: correct PowerShell 7 patterns for JSON output, number parsing, rounding and encodings, with self-test commands. File: `{{COLLAB_HOME}}\executor\skills\pwsh-json-pitfalls\SKILL.md`
