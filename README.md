# collab: a three-agent workflow orchestrated by Claude Code (CC + Gemini + Codex)

[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
![Platform: Windows](https://img.shields.io/badge/platform-Windows-0078D6)
![PowerShell 7+](https://img.shields.io/badge/PowerShell-7%2B-5391FE)
![Claude Code skill](https://img.shields.io/badge/Claude%20Code-skill-D97757)
![Languages: English | 中文](https://img.shields.io/badge/lang-English%20%7C%20%E4%B8%AD%E6%96%87-555)
[![GitHub stars](https://img.shields.io/github/stars/azakmo/collab-skill?style=flat)](https://github.com/azakmo/collab-skill/stargazers)
[![Last commit](https://img.shields.io/github/last-commit/azakmo/collab-skill)](https://github.com/azakmo/collab-skill/commits/main)

**English** | [简体中文](README.zh-CN.md)

Let Claude Code (CC) do only the thinking — planning, writing specs, reviewing — and hand the actual coding, bulk edits and reading to cheaper executors (Gemini / Codex). This saves a large share of your CC quota.

- CC splits the work, writes a spec and an **executable acceptance test** for each task, then dispatches it in the background;
- Executors work inside the Codex CLI sandbox and must pass the acceptance test before handing in;
- A pipeline automatically runs "test → rework on failure → escalate to a stronger executor", and wakes CC only once per batch;
- Every dispatch is logged to a ledger (tokens, time, pass rate), so the next task goes to whoever performs best.

> Platform: Windows + PowerShell 7 (pwsh). Executors run through the [Codex CLI](https://github.com/openai/codex).
>
> **Languages:** English (default) and Simplified Chinese. The skill, task/report templates, executor instructions and generated text all come in both. Choose with `"language": "en" | "zh-CN"` in `roster.json` (or the `COLLAB_LANG` environment variable). Task files written in either language are parsed regardless of the setting.

## Real-world results

Numbers from the author's own ledger (Oct 2026, 5 real projects, 34 dispatched tasks), de-identified. CC's cost is measured from Claude Code transcripts by `cc-usage.ps1` as **equivalent tokens** (input + cache write × 1.25 + cache read × 0.1 + output × 5, i.e. weighted by price); executor tokens are the totals reported by the Codex CLI.

**Same kind of task, CC alone vs. collab** (a short promotional video, built with a code-rendering pipeline):

| | CC alone | With collab | Change |
|---|---:|---:|---:|
| CC model calls | 176 | 31 | −82% |
| CC average context | ~440k | ~104k | −76% |
| CC cost per call (equiv.) | 54.8k | 16.8k | −69% |
| **CC total (equiv. tokens)** | **9.65M** | **0.52M** | **−95%** |
| Executor tokens (Gemini/Codex quota) | — | 1.24M | |

> Two different videos of the same kind, not a controlled experiment. The CC-alone run also happened inside a long session, which inflates its context — that is exactly the cost this workflow is designed to avoid.

**Per project — how much of the token load moved off CC:**

| Project | Dispatches | Executor tokens | CC calls | CC equiv. tokens | Executors' share | CC equiv. per dispatch |
|---|---:|---:|---:|---:|---:|---:|
| A · Android app (several iterations) | 15 | 8.63M | 187 | 6.67M | 56% | 444k |
| B · Android VPN app (first collab project) | 6 | 1.35M | 139 | 3.11M | 30% | 519k |
| C · Framework tooling | 5 | 2.77M | 30 | 0.59M | 82% | 119k |
| D · Short video | 2 | 1.24M | 31 | 0.52M | 70% | 260k |
| E · App | 6 | 5.11M | 37 | 1.37M | 79% | 228k |
| **Total** | **34** | **19.1M** | **424** | **12.3M** | **61%** | **361k** |

**Executors** (all runs, including framework self-tests):

| Executor | Runs | Avg tokens / run | Avg time | Passed final review |
|---|---:|---:|---:|---:|
| Gemini | 38 | 503k | 19.9 min | 76% (25 / 33 reviewed) |
| Codex | 16 | 100k | 10.2 min | 86% (12 / 14 reviewed) |

**What the data taught us (and the rules that came out of it):**
- **Context length is the real cost.** In project A, later iterations ran in an ever-growing session: average context rose from 120k to 371k and CC's cost per call from 18.7k to 71.5k equiv. tokens. Hence the rule "one fresh session per collab project".
- **The earlier projects did most work in CC.** Project B, the first one, ran inside a long session with 139 CC calls, and executors carried only 30% of the tokens. Once tasks came with detailed specs and acceptance tests (C, D, E), executors carried 70–82% of the tokens and CC's cost per dispatch fell to 119k–260k.
- **Gemini is verbose, Codex is lean.** Gemini uses ~5× the tokens per run, but its quota is the largest, so it gets most code; Codex gets debugging, integration and reviews.
- **The executor environment matters.** Injecting a dedicated `AGENTS.md` instead of the user's personal skill list cut executor tokens per run from 189k to 127k (−33%) in an A/B test; the lean Codex config cut Codex's baseline tokens from 5.2k to 4.1k.

![Ledger page: pass rate and tokens per executor, CC vs executor spend per project, token trends](docs/images/ledger-en.png)

*The ledger page of the built-in console (sample data).*

![Console: choose executors and models for each layer, model whitelist](docs/images/console-en.png)

*The roster console: pick executors and whitelist models per layer (sample config).*

## Install

1. Clone anywhere, e.g. `C:\collab`, and point the user environment variable `COLLAB_HOME` at it:
   ```powershell
   git clone https://github.com/azakmo/collab-skill C:\collab
   [Environment]::SetEnvironmentVariable('COLLAB_HOME', 'C:\collab', 'User')
   ```
2. Install the skill into Claude Code (English; use `skill\zh-CN\collab` for Chinese):
   ```powershell
   Copy-Item -Recurse C:\collab\skill\en\collab "$env:USERPROFILE\.claude\skills\"
   ```
3. Install and sign in to the Codex CLI (`codex` on PATH, or the Codex desktop app installed).
4. Configure the roster: on first run `roster.example.json` is copied to `roster.json`. Open the console, click "Probe models" and tick the models you actually have (the model names in the example are placeholders):
   ```powershell
   pwsh -File "$env:COLLAB_HOME\console\console.ps1"
   ```
5. If you use an OpenAI-compatible endpoint (e.g. a local Gemini proxy) as an executor: put the key in a **user environment variable** and write only the variable name in the roster provider (the example uses `AGT_API_KEY`). The endpoint must support the `responses` wire format (required by the Codex harness).

Then tell Claude Code **"collab mode"** / **"please collaborate"** (or 「请协同处理」) to use the workflow; otherwise CC does the work itself.

## Roles

| Layer | Default | Responsibilities |
|---|---|---|
| 1 · Controller | Claude Code (CC), fixed | Split tasks, write specs and acceptance tests, decide, **final review** |
| 2 · Implement / first review | Codex | Hard debugging, integration, tasks that are hard to specify, reviewing layer 3 when tests can't cover it |
| 3 · Labor | Gemini: Codex CLI as harness + OpenAI-compatible proxy | **Most of the code** (clearly specified, with tests), bulk edits, builds, reading material |
| Final sign-off | You | Anything touching real environments (servers / deploys / sending to others): CC reviews, then you approve |

Which executors and models actually sit in layers 2 and 3 is whatever the console saved to `roster.json`.
Review chain: executor self-check (runs the test) → `verify.ps1` → Codex review if needed → CC final review → your approval for real-environment actions.

## Layout

```
$COLLAB_HOME\
  README.md            this file (README.zh-CN.md: Chinese)
  skill\en\collab\     Claude Code skill, English (copy to ~/.claude/skills/)
  skill\zh-CN\collab\  Claude Code skill, Chinese
  templates\en\        task / report / board templates (English)
  templates\zh-CN\     same, Chinese
  bin\
    init-collab.ps1    create collab\ inside a project
    run-executor.ps1   generic dispatcher (roster.json whitelist)
    notify.ps1         desktop notification when a pipeline / batch ends
    handover.ps1       handover check: which accepted files changed since
    visual-review.ps1  visual acceptance: a vision reviewer checks screenshots against a checklist, writes contact.png
    run-codex.ps1      = run-executor -Executor codex
    run-gemini.ps1     = run-executor -Executor gemini
    run-pipeline.ps1   one task: dispatch → verify → rework → escalate
    run-batch.ps1      several pipelines in parallel, one summary
    verify.ps1         run the task's acceptance test
    ask.ps1            delegate reading / log digging / research
    ledger-mark.ps1    record CC's verdict in the ledger
    cc-usage.ps1       measure CC's own token spend
    tools.ps1          shared helpers (codex.exe lookup, whitelist, ledger, toolchains)
  executor\            AGENTS.md (+ AGENTS.zh-CN.md) and on-demand skills injected into executors
  console\             web console (console.ps1 + console.html + live-stats.ps1 + ledger page + i18n.js; open-console.ps1 = desktop shortcut)
  roster.example.json  roster example (roster.json is local, git-ignored)
  ledger.csv           ledger (local, git-ignored)

<project>\collab\
  brief.md             goal, constraints, acceptance criteria (CC)
  board.md             task board: id, executor, status (CC)
  tasks\T001.md        one task (CC)
  reports\T001.md      report (executor)
  logs\                run logs (scripts)
```

## Rules

1. Before dispatching, CC writes the task file: executor, inputs, **files allowed to change**, deliverables, acceptance criteria.
2. One file is owned by one executor at a time. In git repos, use separate worktrees for parallel code changes.
3. Executors touch local files only: **no SSH, no servers, no deploys, no messages, no deleting anything outside `collab\`**. Those actions are CC's, after asking you.
4. Don't delegate small jobs: anything CC can finish in ≤ 3 tool calls, CC does itself.
5. Fire and forget: run in the background and wait for the completion notice; no log peeking or progress checks.
6. Write the "规格" (spec) section in detail — interfaces, examples, edge cases, don'ts — and attach an acceptance test.
7. Reports must state: where the output is, what changed, verification command and result, what's unfinished.
8. CC's final review looks at real output (run it, diff, spot-check), not just the report.
9. At most two rework rounds per task, then re-split or switch executor.

## Usage

```powershell
# 1. Create the collab folder in a project
& "$env:COLLAB_HOME\bin\init-collab.ps1" -Project 'C:\work\my-project'

# 2. CC writes collab\brief.md and collab\tasks\T001.md, updates board.md

# 3. Dispatch (pipeline recommended, run in background)
& "$env:COLLAB_HOME\bin\run-batch.ps1" -Project 'C:\work\my-project' -Tasks T001,T002

# 4. Read collab\reports\T00x.md + the real output, final review
```

### Pipeline: auto-verify, rework, escalate (run-pipeline / run-batch)
- `run-batch.ps1 -Project <dir> -Tasks T001,T002 [-MaxRework 2]`: runs tasks in parallel and prints one summary table at the end (result, who finished it, attempts, tokens, minutes).
- Per task (`run-pipeline.ps1`): dispatch → run the acceptance test → on failure append the failing lines to the task file and send it back to the same executor (up to MaxRework rounds) → still failing: hand it to the next executor in `Escalation` → result in `collab/logs/<task>.pipeline.json`.
- Settings are read from the task file fields: `Executor`, `Timeout`, `Network`, `Toolchain`, `Escalation` (or the Chinese `执行者`, `时限`, `联网`, `工具链`, `升级路径`).
- Results: `PASS`; `NO_TEST` (no acceptance test, CC reviews manually); `NEEDS_CC` (the whole escalation path failed).
- **Interruptions are not rework**: when an executor crashes (exit code other than 0/2/3), stalls (exit 4: the err.log has not grown for 12 minutes, usually a request hanging in the proxy; tune with `COLLAB_STALL_MIN`) or the proxy is unreachable, the pipeline waits for the provider (probing every 30 s, up to `-ProviderWaitMin 15`), then continues the *same* session with `codex exec resume <session id>` — progress is kept and no rework round is used (up to `-MaxResume 2`). The ledger row is marked `中断` (interrupted) and the flags column gets `resume`. Exit 2 (done but no report) gets one resume that only asks for the report. Timeouts (3) are still rework.
  - Manual resume: `run-executor.ps1 ... -Resume <session id> [-ResumePrompt '...']`; the id is on the `session id:` line at the top of that run's err.log.
- **Health probe checks the answer**: before a dispatch (when `-Model` is not pinned) the default model gets a tiny question (17+25). If it does not answer correctly within 20 s, the run uses the first roster `fallback_models` entry (must also be in `enabled_models`) that does, with a WARNING. Checking the *answer* matters: an upstream with no capacity keeps `/models` working while generation queues for minutes, and a retired model may return HTTP 200 instantly with a canned "no longer available" text that makes Codex loop forever.
- **Context window for proxy models**: Codex has no metadata for proxy models (the `Model metadata ... not found` warning) and assumes a small context window, so long runs get compacted (lossy). Roster executor field `context_window` is passed as `-c model_context_window=N` (`run-executor -ContextWindow N` overrides). The warning itself can't be silenced without a `model_catalog_json`, which requires a full base system prompt — so Codex's fallback prompt is kept.
- **Desktop notifications**: when a pipeline ends, a Windows toast reports the result (passed / needs CC / no test, with the reason); clicking it opens the console. Pipelines started by run-batch run with `-Quiet`, and the batch sends one summary at the end; a proxy still down after `ProviderWaitMin` also notifies. `bin\notify.ps1` uses the WinRT toast API of the built-in Windows PowerShell 5.1, nothing to install. Turn off with `COLLAB_NOTIFY=0` or roster `"notify": false`.
- **Handover manifests with hashes**:
  - When a task passes, the pipeline hashes (SHA-256) every file in its allowed list (folders and globs expanded, `collab\` excluded) into `collab\logs\<task>.manifest.json`, and updates the project-wide `collab\handover.json` (each file's hash at its last acceptance, and which task accepted it).
  - `bin\handover.ps1 -Project <dir> [-Task T002]` lists accepted files changed or deleted since. A fresh session runs it before trusting the "Current state" in brief.md. Exit 0 = all match, 1 = something changed, 4 = nothing accepted yet.
  - Task field `Depends on: T002, T003` (or `依赖：`): before starting, the pipeline checks those tasks have passed and their files are unchanged; otherwise NEEDS_CC without calling an executor. A later task that legitimately changes an earlier task's files is fine: when it passes, it becomes the files' latest accepted state.
  - **Scope check**: the project is snapshotted (size + modification time; `.git`, `build`, `.gradle`, `node_modules` etc. skipped, more via `COLLAB_SNAPSHOT_SKIP`) around every executor run. Changes outside the allowed list go into pipeline.json: modified or deleted existing files turn the result into NEEDS_CC (executors may not delete files and don't have the originals, so a rework round could not undo it — CC decides); new stray files are only a `stray_files` warning. A snapshot of a real Android project takes about 0.2 s.
- **Visual acceptance**: if the task has a `## Visual acceptance` (or `## 视觉验收`) section, the pipeline runs `visual-review.ps1` after the tests pass. It builds `collab/logs/<task>.contact.png` (one contact sheet for CC's final review) and asks the vision model, read-only via `codex exec -i` (references first), to check every screenshot against the checklist; the verdict goes to `collab/logs/<task>.visual.md`. A FAIL appends the issue list to the task as a rework round. A reviewer error (proxy down, bad output) does not block the task: pipeline.json records `reviewer error` and CC checks the contact sheet. Exit codes: 0 pass, 1 fail, 4 no section, 5 no screenshots, other = reviewer error.
- Executors run with a lean config (`--ignore-user-config`, no Codex plugins / MCP servers / hooks), measured at 20–30% fewer baseline tokens. Set `clean_config: false` in the roster to opt out; `reasoning` sets reasoning effort.
- **Dedicated executor environment** (on by default, `collab_env: false` to opt out): `-c skills.include_instructions=false` hides your personal Codex skill list, and `-c developer_instructions` injects `executor\AGENTS.md` (with `{{COLLAB_HOME}}` replaced by the real path): sandbox limits, PowerShell pitfalls, working style, and on-demand skills under `executor\skills\*\SKILL.md`. Login and sandbox setup stay in your normal `CODEX_HOME`.
  - `executor\AGENTS.md` must not contain `'''` (it is passed as a TOML literal string).
  - Add recurring generic pitfalls to `executor\AGENTS.md`; longer recipes go into `executor\skills\<name>\SKILL.md`, listed at the end of AGENTS.md. Keep it short.

### CC's own spend (cc-usage.ps1)
- `& "$env:COLLAB_HOME\bin\cc-usage.ps1" -Since '<start time>' [-Record -Project <dir> -Task 'CC(total)']`: reads Claude Code transcripts (`~/.claude/projects/*.jsonl`) and reports calls, average context, token types and a price-weighted equivalent (equiv); `-Record` adds it to the ledger as `executor=cc`.

### Console and roster (roster.json)
- Start: `pwsh -File "$env:COLLAB_HOME\console\console.ps1"` → opens http://localhost:8790/ (localhost only, Ctrl+C to quit). `/ledger` shows ledger statistics. The UI is bilingual: it starts in the configured language, and the English / 中文 button in the top-right switches it (remembered per browser).
- **Live panel** at the top of the console (refreshes every 3 s, read-only): every running executor (task, executor/model, resumed or read-only, run time, time since last output — red when it is past the stall limit — the executor's latest narration and the last 40 log lines), plus a task board per project active in the last 24 hours (running / verifying-rework / passed / needs CC / not started). It reads process command lines and `collab\logs` / `collab\tasks` only. For a desktop shortcut point it at `pwsh -File "$env:COLLAB_HOME\console\open-console.ps1"`: it opens the page if the console is already running, otherwise starts it in that window.
- Choose which executors sit in layer 2 (implement/review) and layer 3 (labor) and which models are enabled; saved to `roster.json` (previous version backed up as `roster.json.bak`).
- Probe models: Codex built-in models come from `models_cache.json`; OpenAI-compatible endpoints from `/models`.
- New provider: enter the URL and the **name of an environment variable** holding the key (the console never accepts or shows keys).
- **The whitelist is enforced**: `run-executor.ps1` only allows enabled executors and ticked models; anything else fails before any call is made.
- Capability tier 1–3: if a task's `Difficulty` exceeds the executor's tier, the dispatcher prints a WARNING.

### Acceptance tests (verify.ps1)
- Every task file needs an `## Acceptance test` (or `## 验收测试`) section: a PowerShell block with one `Check` per criterion, exit code 0 when all pass. Executors must pass it before handing in and may not modify it.
- Host-only checks (starting an HTTP server, opening a browser, listening on ports) use `HostCheck`: inside the executor sandbox they print `SKIP [host]` and don't count as failures; the pipeline runs them on the host. The sandbox is detected by the user name `codexsandbox*`; if detection fails, `HostCheck` behaves like `Check`, so nothing is skipped silently.
- Dry-run the test before dispatching (before the deliverable exists) and make sure every failure is "not written yet", not a broken test. Call GUI programs (msedge etc.) with `Start-Process -Wait -RedirectStandardOutput`, not `&`.
- First step of the final review: `& "$env:COLLAB_HOME\bin\verify.ps1" -Project <dir> -Task T00n -Mark` — prints a few PASS/FAIL lines; `-Mark` records pass/rework in the ledger.

### Delegate reading and research (ask.ps1)
```powershell
& "$env:COLLAB_HOME\bin\ask.ps1" -Project <dir> -Question 'question to answer' [-Files a,b] [-Network] [-Executor gemini|codex] [-MaxWords 400]
```
Creates a research task `collab\tasks\R<timestamp>.md`, sends it to an executor (Gemini by default), and prints only the report: conclusion first, then sources (`file:line` or URL). CC reads only that report and spot-checks one or two sources.

### Ledger (ledger.csv)
- Each dispatch appends a row: time, project, task, type, executor, model, flags, exit code, minutes, tokens, self-reported status (UTF-8 with BOM, opens in Excel).
- Record the verdict after review: `& "$env:COLLAB_HOME\bin\ledger-mark.ps1" -Project <dir> -Task T00n -Review pass|rework|failed|cancelled [-Note 'reason']`.

### Network and toolchains
- `-Network`: allow network access inside the sandbox (dependencies, sources, builds). Off by default; enable per task and list the allowed official sources in the task's `Network` field.
- `-Toolchain android`: sets env vars and PATH for JDK / Android SDK+NDK / Go / Gradle. **The paths in `$Toolchains` in `bin\tools.ps1` are examples — edit them for your machine**; add new toolchains there too.
- `-AddDir <dir>`: extra writable directories (caches outside the project).
- With network on, an executor can technically reach any address; only the task rules restrain it. Never delegate SSH, deploy or login work.

### About the Gemini proxy
- Layer 3 calls Gemini through an OpenAI-compatible (`responses` format) proxy; its URL and key variable are set in the roster provider. If the proxy isn't running, the scripts fail immediately.
- Risk: bulk calls through a third-party proxy may get your account restricted — assess this yourself.
- Proxies occasionally garble the conversation format, so don't skip the Codex review and CC's final review.

Exit codes: 0 = executor finished and wrote a report; 2 = finished without a report; 3 = timed out and killed; 4 = stalled (no log output for 12 min); 5 = looping (the model's last 6 replies are identical, e.g. a retired model answering every turn with the same canned text — the log keeps growing so the stall check never fires; tune with `COLLAB_LOOP_REPEAT`); other = the executor's own error or an interrupted process. The pipeline resumes the same session for 4 and "other" and restarts fresh for 5 (see above). Ledger writes take a machine-wide lock, so parallel pipelines don't overwrite each other's rows.

## License

MIT
