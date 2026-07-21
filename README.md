# grok-orchestra

[English](README.md) | [日本語](README.ja.md)

**Grok as operator · Codex CLI as the only worker.**

A multi-agent development harness inspired by [Claude Code Orchestra](https://github.com/DeL-TaiseiOzaki/claude-code-orchestra) and [Antigravity Orchestra](https://github.com/Sora-bluesky/antigravity-orchestra) (concept only; no Claude Code worker path).

## Why

- Single user interface: talk to **Grok** only
- Deep design / review / complex implementation: **Codex** (`codex exec`)
- Shared state lives in **files** (Grok and Codex do not share a session)
- Failure modes (context rot, dual-write, false done, cost blowup, …) are designed out — see `.agents/docs/failure-modes.md`

## Prerequisites

- [Grok Build](https://x.ai) CLI authenticated (`grok login` or `XAI_API_KEY`)
- [Codex CLI](https://github.com/openai/codex) authenticated (`codex login`)
- Windows PowerShell 7+ recommended

```powershell
codex --version
grok models   # or grok --version
```

## Quick start

This repository is a **harness template**. Use the contract files **in this tree** — not a `HANDOFF.md` from another project, and not another repo’s `AGENTS.md`.

```powershell
cd path\to\grok-orchestra
# optional local state for this workspace only:
Copy-Item .agents\STATE.example.md .agents\STATE.md
grok
```

First message to Grok (example):

```text
You are the operator for this grok-orchestra workspace.
Follow the contract in ./AGENTS.md and skills under ./.agents/skills/.
Do not look for HANDOFF.md (local/optional; not part of the public template).
If .agents/STATE.md is missing, seed it from .agents/STATE.example.md.
Summarize topology and next safe action in under 10 lines.
```

Smoke (Codex read-only review from this repo):

```powershell
.\scripts\delegate-codex.ps1 -JobId smoke-001 -Type review -PromptFile .agents\docs\packets\smoke-001.prompt.txt
```

### Using this harness inside another project

1. Copy or submodule the `.agents/`, `scripts/`, and root contract pattern into the target app.  
2. **Merge carefully** with that app’s existing `AGENTS.md` (priority: user instruction → active packet → this harness contract).  
3. Keep session continuity files **local-only** if you use them:

| File | Public? | Purpose |
|------|---------|---------|
| `AGENTS.md` (this repo) | Tracked | Tool-neutral operator contract for *this* harness |
| `.agents/STATE.example.md` | Tracked | Seed for local state |
| `.agents/STATE.md` | gitignored | Live phase / last job (optional) |
| `PROGRESS.md` | gitignored | Dated log (optional) |
| `HANDOFF.md` | gitignored | Operator continuity (optional; maintainers only) |

## Roles

| Role | Owner |
|------|--------|
| Orchestrator / light research / tiny edits / verify | Grok |
| Designer / Debugger / Auditor / complex implement | Codex |

## Isolation

| Layer | Meaning |
|-------|---------|
| **L0** (default) | One writer; Operator freezes code edits during Codex implement |
| **L1** | File-ownership leases via `scripts/lease-paths.ps1` |
| **L2** (later) | Git worktree per job — optional, not CCO default |

## Layout

```text
AGENTS.md                      # Public harness contract (this repo)
.agents/                       # SSOT: rules, skills, docs, logs
.agents/STATE.example.md       # Seed for optional local STATE.md
.grok/rules/                   # Grok-native thin rules
.codex/AGENTS.md               # Worker-facing contract for Codex in this tree
scripts/delegate-codex.ps1
scripts/lease-paths.ps1
# Optional local only (gitignored): HANDOFF.md, PROGRESS.md, .agents/STATE.md
```

## License

MIT
