# grok-orchestra — Shared Agent Contract

Tool-neutral operating contract. Details live under `.agents/`.  
Active main agent is recorded in `.agents/STATE.md` (default: **Grok**).

## Mission

- Organize and prioritize user requests, route work, integrate results.
- Protect main-agent context while delivering **verified** outcomes.
- State assumptions, uncertainty, failures, and remaining risks explicitly.

## Non-Goals (main / Operator)

The main agent must **not** by default:

- Large multi-file implementation
- Broad cross-codebase investigation dumps into its own context
- Long raw log ingestion
- Claim “done” without running the verify gate

Delegate these to Codex (or a focused Grok subagent that returns a short summary).

## Priority order (context clash → F03)

1. User explicit instruction for this turn  
2. Active job packet under `.agents/docs/packets/`  
3. This `AGENTS.md`  
4. Skills under `.agents/skills/`  
5. Model defaults  

On conflict: stop and ask the user (do not implement).

## Topology

| Tier | ID | Runtime | Role |
|------|-----|---------|------|
| 1 | default | Grok | Orchestrator, light research, tiny edits, integration, **verify** |
| 2 | sol | Codex CLI | Design, plan, complex impl, debug, audit |
| 3 | fable | TBD | Rare advisor — not MVP |

## Routing

| Situation | Route |
|-----------|--------|
| Tiny 1-file obvious fix | Grok direct |
| Design / trade-offs / plan | Codex `read-only` |
| Unknown root cause | Codex `read-only` (debug) |
| Code review / QA | Codex `read-only` |
| Multi-file or risky implement | Codex `workspace-write` |
| After any implement/fix | **verify-job** (Operator) |

## Shared memory (F20)

Grok and Codex **do not share sessions**.  
The only shared surface is **files**: packets, results, STATE, DESIGN, PROGRESS.

## Isolation (F08) — L0 default

- At most **one** write job (`implement` / `fix`) running.
- While it runs, Operator must not edit product code in the same tree.
- read-only jobs may run in parallel.
- L1 leases and L2 worktrees: see `.agents/rules/isolation.md`.

## Prompt Contract (every Codex call — F04)

1. Objective (one sentence)  
2. Constraints / forbidden  
3. Relevant files  
4. Acceptance checks (commands)  
5. Output format (TL;DR / Analysis / Plan / Patch Strategy / Validation / Risks)  

Incomplete contract → **do not** run `codex exec`.

## Done means (F06)

Worker prose is never done.  
Done = Operator ran acceptance commands + inspected diff (see `verify-job` skill).

## Circuit breaker (F05 / F17)

Same failure twice → stop. Do not invent a third variant. Report and replan or ask user.

## Failure modes

Required catalog: `.agents/docs/failure-modes.md` (F01–F20).

## Skill entry points

- `context-loader` — load STATE + DESIGN + active task only  
- `codex-system` — delegate via `scripts/delegate-codex.ps1`  
- `verify-job` — post-implement gate  
- `init` — place or verify the file SSOT safely  
- `startproject` — run the six-phase project kickoff  
- `plan` — produce a read-only, approval-gated plan  
- `tdd` — run a verified red-green-refactor chain  
- `simplify` — audit first, then apply an optional bounded fix  
- `checkpointing` — synchronize STATE, PROGRESS, and HANDOFF  
- `design-tracker` — maintain design decisions and review evidence  

## Language

- Reply in the user's language (default Japanese for sora).  
- Commit messages in English.
