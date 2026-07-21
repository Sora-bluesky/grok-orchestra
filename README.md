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

```powershell
cd path\to\grok-orchestra
grok
```

Then:

```text
Read AGENTS.md and .agents/STATE.md (create from STATE.example.md if missing).
```

Smoke (Codex read-only review):

```powershell
.\scripts\delegate-codex.ps1 -JobId smoke-001 -Type review -PromptFile .agents\docs\packets\smoke-001.prompt.txt
```

Local-only session files (gitignored; create as needed):

| File | Purpose |
|------|---------|
| `HANDOFF.md` | Operator continuity across sessions |
| `PROGRESS.md` | Dated progress log |
| `.agents/STATE.md` | Active phase / last job (seed: `.agents/STATE.example.md`) |

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
AGENTS.md                      # Always-loaded contract
.agents/                       # SSOT: rules, skills, docs, logs
.agents/STATE.example.md       # Seed for local STATE.md
.grok/rules/                   # Grok-native thin rules
.codex/AGENTS.md               # Worker-facing contract
scripts/delegate-codex.ps1
scripts/lease-paths.ps1
# Local only (gitignored): HANDOFF.md, PROGRESS.md, .agents/STATE.md
```

## License

MIT
