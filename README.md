# grok-orchestra

[English](README.md) | [日本語](README.ja.md)

**Grok as operator · Codex CLI as the specialist worker.**

A multi-agent development harness: you talk only to **Grok**. **Codex** handles design, review, and deep debug by default. Grok implements by default and always owns verification.

Inspired by [Claude Code Orchestra](https://github.com/DeL-TaiseiOzaki/claude-code-orchestra) and [Antigravity Orchestra](https://github.com/Sora-bluesky/antigravity-orchestra).

## Why

- **Single UI** — talk to Grok only
- **Clear split** — Grok builds; Codex plans/reviews/debugs (Codex implement is the exception)
- **File SSOT** — Grok and Codex do not share a chat session; packets and docs are the shared surface
- **Failure modes designed in** — context rot, dual-write, false done, cost blowup, and more: [`.agents/docs/failure-modes.md`](.agents/docs/failure-modes.md)

## Prerequisites

| Tool | Notes |
|------|--------|
| [Grok Build](https://x.ai) CLI | `grok login` (or `XAI_API_KEY`) |
| [Codex CLI](https://github.com/openai/codex) | `codex login` |
| Windows PowerShell 7+ | Recommended for scripts |

```powershell
codex --version
grok models   # or: grok --version
```

## Quick start

Clone this repo (or use it as a template), then work **inside this tree** so Grok loads **this** contract.

```powershell
git clone https://github.com/Sora-bluesky/grok-orchestra.git
cd grok-orchestra
Copy-Item .agents\STATE.example.md .agents\STATE.md   # optional workspace state
grok
```

Example first message:

```text
You are the operator for this grok-orchestra workspace.
Follow ./AGENTS.md and skills under ./.agents/skills/.
If .agents/STATE.md is missing, seed it from .agents/STATE.example.md.
Summarize topology and the next safe action in under 10 lines.
```

### Smoke test (Codex read-only)

```powershell
.\scripts\delegate-codex.ps1 -JobId smoke-001 -Type review -PromptFile .agents\docs\packets\smoke-001.prompt.txt
```

Expect a non-empty `.agents/logs/codex/smoke-001.last.txt` (gitignored).

## Roles

| Role | Owner |
|------|--------|
| Orchestrator, default **Builder**, light research, **verify** | Grok |
| Designer, Debugger, **Auditor** | Codex (`read-only`) |
| Implementer (exception) | Codex `workspace-write` only if context would bloat, the batch is long/unattended, or you explicitly ask |

**Rule of thumb:** Codex is the skeptic; Grok moves the hands. After non-trivial Grok patches, run a Codex review before calling the work done.

## Isolation

| Layer | Meaning |
|-------|---------|
| **L0** (default) | One writer of product code at a time (Grok **or** Codex, not both) |
| **L1** | Path leases via `scripts/lease-paths.ps1` |
| **L2** (optional later) | Git worktree per job |

## Using this harness in another project

1. Copy (or submodule) `.agents/`, `scripts/`, root `AGENTS.md`, and `.codex/` / `.grok/` as needed.  
2. Merge carefully with the app’s existing agent contract (priority: user instruction → active packet → this harness contract).  
3. Keep live session state local if you use it:

| Path | Tracked? | Purpose |
|------|----------|---------|
| `AGENTS.md` | yes | Operator contract for this harness |
| `.agents/STATE.example.md` | yes | Seed for optional local state |
| `.agents/STATE.md` | no (gitignored) | Live phase / last job |
| `PROGRESS.md` | no (gitignored) | Optional dated log |

## Layout

```text
AGENTS.md                 # Operator contract (always start here)
.agents/                  # Rules, skills, docs, packets, logs
.agents/STATE.example.md  # Optional seed for local STATE.md
.codex/AGENTS.md          # Contract shown to Codex in this tree
.grok/rules/              # Thin Grok operator rules
scripts/delegate-codex.ps1
scripts/lease-paths.ps1
docs/architecture.md
```

## Skills (entry points)

| Skill | Use for |
|-------|---------|
| `context-loader` | Minimal session load |
| `codex-system` | Delegate to Codex (design/review/debug; implement only as exception) |
| `verify-job` | Done gate after any product write |
| `plan` | Codex design/plan, approval before implement |
| `tdd` | Red → green → refactor (Grok writes; Codex reviews) |
| `simplify` | Codex audit, then optional Grok fix |
| `init` / `startproject` / `checkpointing` / `design-tracker` | Bootstrap and continuity |

Details: [`.agents/INDEX.md`](.agents/INDEX.md).

## License

MIT
