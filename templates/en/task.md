# {{ID}}: {{Title}}

- Executor: {{gemini | codex}}
- Type: {{bulk | implement | debug | review}}
- Timeout: {{minutes}} minutes
- Network: {{no | yes: only for downloading dependencies/sources, limited to {{official sources}}}}
- Toolchain: {{none | android (Go/gomobile/JDK17/SDK/NDK/Gradle env vars preset)}}
- Depends on: {{none | T001, T002 (these tasks must have passed, with their files unchanged since; otherwise the pipeline will not start)}}

## Assessment (filled in by the controller; executors can ignore)
- Difficulty: {{1 mechanical/bulk | 2 clearly specified implementation | 3 hard debugging / cross-module / hard to specify}}
- Estimated tokens: {{based on similar tasks in ledger.csv, e.g. "about 150k"}}
- Assigned to: {{executor id + model; must be enabled in roster.json}}
- Rationale: {{why not a cheaper layer / why not do it yourself; cite pass rate and tokens of similar tasks if any}}
- Escalation: {{who takes over after two failed rework rounds, e.g. gemini → codex → CC}}

## Background
{{Context the executor needs. Do not assume it has seen any chat history.}}

## Spec (be detailed — an executor that follows it should not go astray)
- Interfaces / file layout: {{function signatures, API routes, config fields, where files go}}
- Input/output examples: {{at least one normal and one error case}}
- Edge cases: {{empty values, oversize, invalid format, duplicates, concurrency, offline… say how each is handled}}
- Don'ts: {{dependencies not to add, behaviour not to change, files not to touch}}

## Inputs
- {{files to read, paths relative to the project root}}

## Files allowed to change
- {{whitelist; any file not listed here must not be changed}}
- collab/reports/{{ID}}.md (report)

## Steps
1. {{concrete steps}}

## Deliverables
- {{files / scripts / results and where they go}}

## Acceptance criteria
- [ ] {{checkable conditions, ideally verifiable by a command}}

## Visual acceptance (required when the task produces UI, images or video frames; otherwise delete this section)
After the acceptance test passes, the pipeline hands the screenshots below to a vision reviewer that checks each one against this list and sends the task back for rework on any problem. The executor must generate the screenshots itself (Android: Roborazzi/Robolectric; web: headless Edge; video: extract frames) and the acceptance test must check their count.
- Screenshot dir: {{e.g. docs/screenshots/T00n}}
- Reference images: {{e.g. docs/mockups/xxx.png; or "none"}}
- Per-image checklist:
  - {{file.png}}: {{what must be visible: concrete numbers, proportions, text, colors, layout; state facts that can be checked against the sample data, e.g. "the ring chart is about 80% full"}}
- General: no empty or truncated text, no leftover `$` / `{}` / stray symbols; nothing overflows the screen or card; text readable in light and dark mode; layout matches the reference

## Acceptance test
The controller runs the script below with `verify.ps1` in the project root: exit code 0 when everything passes, non-zero if any check fails. The executor must run it and pass before handing in, and **must not modify this script**. If you believe the test itself is wrong, say so in the report — do not change the test.

```powershell
$fail = 0
function Check([string]$Name, [scriptblock]$Test) { try { if (& $Test) { "PASS $Name" } else { "FAIL $Name"; $script:fail++ } } catch { "FAIL $Name : $($_.Exception.Message)"; $script:fail++ } }
# Host-only checks (HTTP server, browser, ...) use HostCheck: inside the executor sandbox they print SKIP and don't count as failures; the pipeline runs them on the host
function HostCheck([string]$Name, [scriptblock]$Test) { if ($env:USERNAME -like 'codexsandbox*') { "SKIP [host] $Name (skipped in sandbox, verified on the host by the pipeline)" } else { Check "[host] $Name" $Test } }
# Check 'output is correct' { (& pwsh -NoProfile -File data/stats.ps1) -join ',' -eq 'total=18,max=date' }
{{one Check per acceptance criterion}}
exit $fail
```

## Executor rules (do not modify this section)
- Only change files listed in "Files allowed to change". If you need to change another file, stop and explain in the report.
- Do not connect over SSH, do not access routers, VPSes or any remote server, do not deploy, publish or send messages.
- When network is allowed, download dependencies or sources only from the official sources listed in the task (e.g. proxy.golang.org, official github.com repos, Maven Central, Google Maven, the official npm registry); do not upload anything, do not log in to any service, do not download programs of unknown origin.
- If the build fails, investigate and retry yourself; if the same error persists after 3 attempts, stop and describe the symptoms and what you tried in the report.
- Do not delete files; to replace one, overwrite a whitelisted file.
- Prefer scripts for bulk, mechanical changes, and include the script in the deliverables.
- Windows: .ps1 files containing non-ASCII text that will run under Windows PowerShell 5.1 must be saved as UTF-8 with BOM; sh, JSON and YAML use UTF-8 without BOM + LF. Do not write .bat/.cmd files.
- Before handing in, run the "Acceptance test" script in the project root and paste every PASS/FAIL/SKIP line into the report. You may not report "done" unless everything passes; `SKIP [host]` items cannot run in the sandbox and are verified by the controller on the host, so they do not count as failures.
- When finished (or failed or stuck), write the report to collab/reports/{{ID}}.md following the collab/_templates/report.md template. Be honest: mark anything you did not verify as not verified.
