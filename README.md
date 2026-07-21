# grok-orchestra

[English](README.md) | [日本語](README.ja.md)

**Grok as operator · Codex CLI as the specialist worker.**

Current release: **[v0.1.0](https://github.com/Sora-bluesky/grok-orchestra/releases/tag/v0.1.0)** · [Changelog](CHANGELOG.md)

A multi-agent development harness: you talk only to **Grok**. **Codex** handles design, independent review, and root-cause investigation by default. **Grok implements** by default and always owns verification.

Inspired by [Claude Code Orchestra](https://github.com/DeL-TaiseiOzaki/claude-code-orchestra) and [Antigravity Orchestra](https://github.com/Sora-bluesky/antigravity-orchestra).

## Why

- **Single UI** — talk to Grok only
- **Clear split** — Grok builds; Codex plans, reviews, and investigates (Codex writing code is the exception)
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

```powershell
git clone https://github.com/Sora-bluesky/grok-orchestra.git
cd grok-orchestra
Copy-Item .agents\STATE.example.md .agents\STATE.md   # optional
grok
```

Example first message:

```text
You are the operator for this grok-orchestra workspace.
Follow ./AGENTS.md and skills under ./.agents/skills/.
If .agents/STATE.md is missing, seed it from .agents/STATE.example.md.
Summarize topology and the next safe action in under 10 lines.
```

### Smoke test

```powershell
.\scripts\delegate-codex.ps1 -JobId smoke-001 -Type review -PromptFile .agents\docs\packets\smoke-001.prompt.txt
```

Expect a non-empty `.agents/logs/codex/smoke-001.last.txt` (gitignored).

## Roles

| Work | Who | Mode |
|------|-----|------|
| Orchestrate, implement (default), verify | **Grok** | interactive |
| Design / plan | **Codex** | `read-only` |
| Root-cause investigation (diagnosis + fix plan) | **Codex** | `read-only` |
| Independent review / audit | **Codex** | `read-only` |
| Apply a fix after diagnosis | **Grok** (default) | write |
| Large / unattended / context-heavy implement | **Codex** (exception) | `workspace-write` |

**Rule of thumb:** Codex is the skeptic and investigator; Grok moves the hands. After non-trivial Grok patches, run a Codex review before calling the work done.

Investigation is **read-only** on purpose: Codex returns diagnosis and a fix plan; applying the patch is a separate write step (usually Grok).

## Isolation

| Layer | Meaning |
|-------|---------|
| **L0** (default) | One writer of product code at a time (Grok **or** Codex, not both) |
| **L1** | Path leases via `scripts/lease-paths.ps1` |
| **L2** (optional) | Git worktree per job |

## Layout

```text
AGENTS.md                 # Operator contract (start here)
.agents/                  # Rules, skills, docs, packets, logs
.agents/STATE.example.md  # Optional seed for local STATE.md
.codex/AGENTS.md          # Contract for Codex in this tree
.grok/rules/              # Thin Grok operator rules
scripts/delegate-codex.ps1
scripts/lease-paths.ps1
docs/architecture.md
```

Live workspace state (optional, gitignored): `.agents/STATE.md`, `PROGRESS.md`.

## Skills

| Skill | Use for |
|-------|---------|
| `context-loader` | Minimal session load |
| `codex-system` | Delegate to Codex |
| `verify-job` | Done gate after any product write |
| `plan` | Codex design/plan before implement |
| `tdd` | Red → green → refactor |
| `simplify` | Audit, then optional fix |
| `init` | Bootstrap this harness into a workspace (including another app tree) |
| `startproject` / `checkpointing` / `design-tracker` | Kickoff and continuity |

Details: [`.agents/INDEX.md`](.agents/INDEX.md).

## License

MIT
