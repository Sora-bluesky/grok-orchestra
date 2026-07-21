# HANDOFF — grok-orchestra

**Updated:** 2026-07-21  
**From:** Grok operator session  
**Repo:** `grok-orchestra` (local clone of this tree)  
**State:** Phase 0–2 complete (workflow skills + L1 lease foundation)

## Mission

Build a **Grok-operator + Codex-worker** orchestration template.

- User talks **only to Grok** (single interface).
- **Codex CLI** is the only external worker (Tier 2).
- **Do not** use Claude Code as a worker.

## Concept lineage (must preserve spirit)

### Claude Code Orchestra

https://github.com/DeL-TaiseiOzaki/claude-code-orchestra

Absorb:

- Root `AGENTS.md` as tool-neutral always-loaded contract
- `.agents/` SSOT (`STATE.md`, rules, skills, docs, logs)
- Tier model: Tier1 default / Tier2 `sol` (Codex) / Tier3 advisor (later)
- Context conservation: main does not own large impl / broad investigation
- **Prompt Contract** for every Codex call
- Quality gates + **independent verification** of Codex output
- Skill catalog ideas: context-loader, codex-system, init, plan, tdd, simplify, checkpointing, design-tracker
- Docs ownership: DESIGN / research / libraries / reviews
- Parallel writers via **file ownership** (not git worktree as core)

### Antigravity Orchestra (sora; **OLD** — retune elsewhere)

https://github.com/Sora-bluesky/antigravity-orchestra

Absorb concepts only (do **not** copy stale WSL scripts as-is):

- Single UI orchestrator
- Role split: host = Orchestrator/Researcher/Builder(small); Codex = Designer/Debugger/Auditor
- Workflow shapes: startproject (6 phases), plan, tdd, simplify, checkpoint, init
- PowerShell delegation bridge (modernize to native Windows `codex` on PATH)
- Rules: role-boundaries + delegation-triggers

**Note:** antigravity-orchestra will be retuned to current specs in a **separate session**. This repo must not block on that work.

## Locked decisions

1. Main agent = **Grok** (record in `.agents/STATE.md`)
2. Worker = **Codex only** (`codex exec`; MCP optional later)
3. CLI-first; `codex mcp-server` is Phase 3
4. Sandbox ladder: review/design/audit/investigate → `read-only`; implement/fix → `workspace-write`
5. Never default danger-full-access / `--dangerously-bypass-approvals-and-sandbox`
6. **Isolation:** L0 single-writer default; L1 file leases (Phase 2); L2 git worktree optional only (Phase 3)
7. Prompt Contract always; incomplete → refuse exec
8. Windows PowerShell native (no WSL path hardcode)
9. **Failure-mode design** (F01–F20 in `.agents/docs/failure-modes.md`) is required, not tips
10. **Done = Operator verify gate**, never Worker prose
11. **Shared memory = files only** (Grok and Codex do not share sessions)
12. Circuit breaker: same failure twice → stop

## Topology

| Tier | ID | Runtime | Role |
|------|-----|---------|------|
| 1 | default | Grok | Orchestrator, light research, tiny edits, integration, verification |
| 2 | sol | Codex CLI | Design, plan, complex impl, debug, audit |
| 3 | fable | TBD later | Rare advisor only — not MVP |

## Role boundaries

| Role | Owner |
|------|--------|
| Orchestrator | Grok |
| Researcher | Grok |
| Builder (≤1 file obvious) | Grok |
| Designer / Debugger / Auditor / complex Implementer | Codex |

Quick rule: need judgment, design depth, or objective review? → Codex.

## Isolation vs Claude Code Orchestra

| | CCO | grok-orchestra |
|--|-----|----------------|
| Parallel writers | Agent Teams + **file ownership** | L1 same idea (Phase 2) |
| git worktree | **Not used as core** | L2 optional only (Phase 3) |
| Artifact paths | `workspace.py` slug SSOT | Same spirit under `.agents/logs` / docs |
| Codex concurrent with main edits | Lead does not implement + ownership | L0 Operator freeze; or L2 worktree |

## Pre-baked failure controls (MVP)

- Parent context diet (F01/F11)
- Prompt Contract hard gate (F04)
- Single writer L0 (F08)
- verify-job after implement (F06/F07/F09)
- File SSOT + no shared session myth (F12/F16/F20)
- Circuit breaker (F05/F17)
- No yolo merge / no danger default (F10/F18)

Full catalog: `.agents/docs/failure-modes.md`

## Codex invoke (current)

```powershell
# Prefer the wrapper:
.\scripts\delegate-codex.ps1 -JobId smoke-001 -Type review -PromptFile .agents\docs\packets\smoke-001.prompt.txt

# Equivalent raw:
Get-Content .agents\docs\packets\{id}.prompt.txt -Raw |
  codex exec -C (Get-Location) -s read-only -o .agents\logs\codex\{id}.last.txt
```

Implement: `-Sandbox workspace-write` (or `-s workspace-write`). L2: `-C .agents\worktrees\{id}`.

## Phase checklist

### Phase 0
- [x] HANDOFF.md at repo root
- [x] git init, .gitignore, README.md, README.ja.md, LICENSE
- [x] Skeleton dirs

### Phase 1 MVP
- [x] AGENTS.md + STATE + core rules
- [x] codex-system skill + delegate-codex.ps1
- [x] context-loader + verify-job + playbook + failure-modes
- [x] Smoke read-only review (`smoke-001`, exit 0, last.txt written)

### Phase 2
- [x] startproject, plan, tdd, simplify, checkpointing, init, design-tracker
- [x] L1 owned_paths leases (`scripts/lease-paths.ps1` + isolation schema)

### Phase 3
- [ ] optional MCP, hooks, check.ps1, worktree helper

## Out of scope

- Claude Code worker
- Full CCO file dump
- Copying AO WSL-hardcoded ask_codex.ps1
- Depending on antigravity-orchestra retune session

## Next actions

1. Use workflow skills as needed (`init` / `startproject` / `plan` / …).
2. For write jobs with path ownership: `.\scripts\lease-paths.ps1` or `delegate-codex.ps1 -OwnedPaths …`.
3. Phase 3 optional: MCP, hooks, `check.ps1`, L2 worktree helper.

## Session start prompt

```text
cwd: <path-to-grok-orchestra>
Read HANDOFF.md and AGENTS.md. Continue from Phase 2 / Phase 3 checklist.
Grok=operator; Codex=only worker. No Claude Code worker.
Failure modes F01-F20 are requirements. Done = verify-job, not worker prose.
```
