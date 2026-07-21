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
Read HANDOFF.md and AGENTS.md. Follow Phase checklist.
```

Smoke (Codex read-only review):

```powershell
.\scripts\delegate-codex.ps1 -JobId smoke-001 -Type review -PromptFile .agents\docs\packets\smoke-001.prompt.txt
```

## Roles

| Role | Owner |
|------|--------|
| Orchestrator / light research / tiny edits / verify | Grok |
| Designer / Debugger / Auditor / complex implement | Codex |

## Isolation

| Layer | Meaning |
|-------|---------|
| **L0** (default) | One writer; Operator freezes code edits during Codex implement |
| **L1** (later) | File-ownership leases (CCO-style) |
| **L2** (later) | Git worktree per job — optional, not CCO default |

## Layout

```text
AGENTS.md                 # Always-loaded contract
HANDOFF.md                # Session continuity
.agents/                  # SSOT: STATE, rules, skills, docs, logs
.grok/rules/              # Grok-native thin rules
.codex/AGENTS.md          # Worker-facing contract
scripts/delegate-codex.ps1
```

## License

MIT
