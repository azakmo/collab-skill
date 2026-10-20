---
name: collab
description: Three-agent collaboration workflow. Claude Code (the controller) only decides, writes task specs and acceptance tests, and does the final review; code goes primarily to Gemini (largest quota), while Codex handles hard debugging, integration and first-pass review. Use ONLY when the user says "collab mode", "please collaborate", 「请协同处理」, or explicitly asks for the three-agent workflow / to dispatch to Gemini or Codex. Otherwise CC does the work itself — never start this workflow on your own.
---

# Three-agent collaboration (framework directory = env var `COLLAB_HOME`)

Read `$env:COLLAB_HOME\README.md` first (script usage, switches, exit codes). Below, `$env:COLLAB_HOME` is the framework directory.

## Core principle: minimise CC's calls
Every CC model call re-reads the whole context, so most of the token cost is the number of CC calls, not the executors'. CC's value is thinking clearly and writing clearly, not typing code. Four hard rules:
1. **Write detailed task specs**: get it right once, so executors don't come back with questions or go astray.
2. **Attach an acceptance test**: the final review is one command, not line-by-line code reading.
3. **Fire and forget**: run in the background and wait for the completion notice; no log peeking or progress checks in between.
4. **Don't delegate small jobs**: anything CC can finish in ≤ 3 tool calls (a few lines, one small file, one command), CC does directly. Writing a spec and reviewing costs more than that.

## Who gets what (by scarcity)
| Executor | Quota | Gets |
|---|---|---|
| Gemini | largest | **Most code**: clearly specified implementations with acceptance tests, bulk edits, scripts, builds, reading material |
| Codex | moderate | Hard debugging, cross-module integration, tasks hard to specify, **first-pass review of Gemini's work**, tasks Gemini failed after two rework rounds |
| CC | scarcest | Splitting tasks, specs and tests, decisions, final review, anything touching real environments |

**Read `$env:COLLAB_HOME\roster.json` first**: choose only enabled executors and ticked models (the dispatcher hard-rejects anything else). The table above is the default split; if the user changed layers in the console, the roster wins.

**Fill in the "Assessment" section** (in the task template): difficulty 1–3, estimated tokens, assignee, rationale, escalation path.
- If the difficulty exceeds every enabled executor's tier, or similar tasks fail after two rework rounds: stop and **tell the user** which kind of task, where the current models fall short, and which model to add or swap in the console.
- If the dispatcher prints `WARNING: task 难度 > tier`, handle it the same way.

Also check `$env:COLLAB_HOME\ledger.csv` for how similar tasks went: prefer the executor with the higher pass rate and fewer tokens; when data exists, data wins.

## Workflow
1. **Split**: first pick out the small jobs (rule 4) and do them yourself; split the rest into non-overlapping tasks (one file belongs to one executor at a time).
2. **Set up**: `& "$env:COLLAB_HOME\bin\init-collab.ps1" -Project <project dir>`, write `collab\brief.md`.
3. **Write tasks**: write `collab\tasks\T00n.md` from `collab\_templates\task.md`, update `board.md`.
   - **Full background**: the executor has never seen any chat history.
   - **Detailed "Spec" section**: interfaces and file layout, input/output examples (one normal, one error), each edge case and how to handle it, and what not to do. This section decides whether the executor gets it right the first time.
   - **An "Acceptance test" section is mandatory**: one `Check` per acceptance criterion; the task is done only when all pass. Tests must run from the project root without network or real environments (CC and the user verify real environments themselves).
   - **Host-only checks use `HostCheck`** (in the template): starting HTTP servers, opening browsers, listening on ports can't run in the executor sandbox (HttpListener fails with "handle is invalid"). `HostCheck` prints `SKIP [host]` in the sandbox and doesn't count as a failure; the pipeline runs it on the host.
   - **Dry-run the test before dispatching**: with the deliverable missing (or a minimal fake), run the acceptance test from the project root and check each failure is "not written yet". If a check fails because of the test itself (wrong command, output not captured, wrong path), fix the test first — otherwise you waste a rework round. To call GUI programs (msedge etc.) in tests use `Start-Process -Wait -RedirectStandardOutput`, not `&`.
   - **Security requirements and "don'ts" need checks too**: whatever grep can verify becomes a `Check` — no external resources, no data concatenated into `innerHTML` (fixed strings only, no `${`, no variables), no `eval`, no hard-coded keys. That lets you skip the Codex review in step 6.
   - Keep the "Executor rules" section unchanged.
4. **Dispatch through the pipeline — one wake-up per batch**
   - **Preferred**: `& "$env:COLLAB_HOME\bin\run-batch.ps1" -Project <dir> -Tasks T001,T002,... [-MaxRework 2]` in the background (`run_in_background`). Each task runs "dispatch → acceptance test → on failure append the failures to the task file and rework (up to MaxRework rounds) → still failing: next executor on the escalation path"; at the end one summary table is printed and CC wakes up once.
   - Executor, timeout, network, toolchain and escalation path are read from the task file's fields, so fill them in correctly (Executor = an id from the roster).
   - Results: `PASS` → spot-check the key outputs; `NO_TEST` → the task had no acceptance test, CC reviews it; `NEEDS_CC` → the whole escalation path failed: read `collab/logs/<task>.pipeline.json` and the report, then re-split, do it yourself, or tell the user to change models.
   - A single task: `run-pipeline.ps1 -Project <dir> -Task T00n`.
   - Only for manual control, call the one-shot dispatchers:
     - Generic: `& "$env:COLLAB_HOME\bin\run-executor.ps1" -Executor <roster id> -Project <dir> -Task T00n [-Model m] [...]`
     - Gemini: `& "$env:COLLAB_HOME\bin\run-gemini.ps1" -Project <dir> -Task T00n [-TimeoutMin 20] [-Network] [-Toolchain android]`
     - Codex: `& "$env:COLLAB_HOME\bin\run-codex.ps1" -Project <dir> -Task T00n [-TimeoutMin 30] [-Network] [-Toolchain android]`
   - After dispatching, end the turn and wait for the notice. **No polling, no log reading, no mid-run checks.**
   - Tasks needing network and build tools (dependencies, Gradle, npm) are delegated too: add `-Network` and `-Toolchain` and allow 30–60 minutes.
5. **After a one-shot dispatch finishes, run the test first** (the pipeline does this automatically): `& "$env:COLLAB_HOME\bin\verify.ps1" -Project <dir> -Task T00n -Mark`
   - All PASS: read the report's "Unfinished / questions" section, spot-check one or two key outputs (run it, check a hash or output), and accept. No line-by-line code reading.
   - Any FAIL: write a rework note (paste the failing lines) and send it back to the same executor. After two failed rework rounds, escalate: Gemini → Codex → CC.
   - Non-zero exit or no report: read the last lines of the report or log for the cause — not the whole file.
6. **First-pass review**: if the acceptance test can't cover something in Gemini's work (security, architecture), dispatch a review task to Codex. If tests cover it, skip the review to save Codex quota.
7. **Real environments** (servers, routers, production deploys, sending things to others): executors never touch them. CC reviews, gives the user the conclusion and evidence, and only acts after the user confirms; ask before anything that may cut network access.
8. **Wrap-up**:
   - Record verdicts with `ledger-mark.ps1` (the pipeline and `verify -Mark` already do this).
   - **Record CC's own spend too**: `& "$env:COLLAB_HOME\bin\cc-usage.ps1" -Since '<collab start time>' -Record -Project <dir> -Task 'CC(total)'`. Note the time when the collaboration starts.
   - Report to the user: who completed each task, test results, how much executors and CC spent (from the ledger), and what is still unverified.

## One fresh session per collab project
The cost of each CC call grows with context length, so collaborating inside a long session is the most expensive option.
- When the user asks for collab mode and the current session is already long (context above ~150k tokens) or was about something unrelated: suggest a fresh session with the requirement, constraints and project path written down, and do the collaboration there.
- In the new session, read the README, roster and ledger first; don't re-read earlier chats.
- Follow-up rework and new features for the same project stay in that session; don't open another.

## Don't read big material yourself
- Large files (a few hundred lines or more), build logs, unfamiliar codebases, web research: use `& "$env:COLLAB_HOME\bin\ask.ps1" -Project <dir> -Question '...' [-Files ...] [-Network]` to hand it to Gemini, and read only the returned summary. Spot-check one or two cited sources for key conclusions.
- Reading only. Don't delegate small files you can read in a few dozen lines.

## Dedicated executor environment (`$env:COLLAB_HOME\executor`)
- Executors start without the user's personal skill list; instead `executor\AGENTS.md` (sandbox limits, PowerShell pitfalls, working style) and two on-demand skills (`headless-edge-test`, `pwsh-json-pitfalls`) are injected. See the README.
- If during final review you see an executor repeatedly stumbling on a **generic** problem (unrelated to the task, will happen again next task), add it to `executor\AGENTS.md` or a skill during wrap-up. Only recurring things; keep it short.
- Don't repeat those generic pitfalls in task specs; write only what is specific to the task.

## Notes
- Script exit codes: 0 finished with a report; 2 no new report; 3 timed out and killed. Logs are in `collab\logs\`; don't read them normally.
- Gemini runs by default through the Codex harness + an OpenAI-compatible (`responses` format) proxy; URL and key variable name live in the roster provider. If the proxy isn't running the script fails: ask the user to start it, or reassign the task to Codex.
- With network on, an executor can technically reach any address; only the rules restrain it. Never delegate SSH, deploy or login work.
- Language: templates and generated text follow `"language"` in roster.json (or `$env:COLLAB_LANG`): `en` (default) or `zh-CN`. Task files in either language are parsed.
