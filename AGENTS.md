# grok-orchestra — Shared Agent Contract

Tool-neutral operating contract. Details live under `.agents/`.  
Active main agent is recorded in `.agents/STATE.md` (default: **Grok**).

## Mission

- Organize and prioritize user requests, route work, integrate results.
- Protect main-agent context while delivering **verified** outcomes.
- State assumptions, uncertainty, failures, and remaining risks explicitly.

## Non-Goals (main / Operator)

The main agent must **not** by default:

- Broad cross-codebase investigation dumps into its own context
- Long raw log ingestion
- Own design/trade-off decisions when judgment matters (route to Codex)
- Claim “done” without the verify gate
- Treat self-review as the only quality gate after non-trivial changes

Prefer **Grok for implementation** and **Codex for design / review / root-cause investigation**.  
Investigation is usually **read-only** (diagnosis + fix plan); applying the fix is a separate write (usually Grok).  
Escalate implementation away from the parent only when it would pollute context (see Routing).

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
| 1 | default | Grok | Orchestrator, default **Builder**, light research, integration, **verify** |
| 2 | sol | Codex CLI | Designer, Investigator, **Auditor** (default); Implementer only as exception |
| 3 | fable | TBD | Rare advisor — not MVP |

**One-line rule:** Sol is the skeptic (design / review / investigate). Grok moves the hands (implement + final verify).

## Routing

| Situation | Route |
|-----------|--------|
| Design / trade-offs / plan | Codex `read-only` |
| Unknown root cause | Codex `read-only` **investigate** → diagnosis + fix plan (not the patch itself) |
| Code review / QA / audit | Codex `read-only` |
| Apply fix after diagnosis | **Grok** (default write) |
| Implement (default): clear scope, iterative | **Grok** |
| After non-trivial Grok implement | Codex `read-only` review → then **verify-job** |
| Tiny 1-file obvious fix | Grok direct → verify-job (Codex review optional) |
| Large / long-running / context-heavy implement | Codex `workspace-write` **or** Grok subagent/worktree (exception) |
| After any Codex implement/fix | **verify-job** (Operator) |

### When Codex may still implement (exception)

Use Codex `workspace-write` only if **any** of:

1. Change set would bloat Operator context (many files, long logs, mechanical mass edit)  
2. Long unattended batch is preferable to interactive Grok turns  
3. User explicitly requests Codex implement  

Otherwise Grok implements.

## Shared memory (F20)

Grok and Codex **do not share sessions**.  
The only shared surface is **files**: packets, results, local STATE / PROGRESS (gitignored), DESIGN.

## Isolation (F08) — L0 default

- At most **one** writer of product code at a time (Grok **or** Codex, not both).
- While a Codex write job runs, Operator must not edit product code in the same tree.
- While Grok implements, do not start a Codex write job on the same tree.
- read-only Codex jobs may run in parallel with Operator reads (not with conflicting writes).
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
After non-trivial Grok patches, also land a Codex review packet before calling done.

## Circuit breaker (F05 / F17)

Same failure twice → stop. Do not invent a third variant. Report and replan or ask user.

## Failure modes

Required catalog: `.agents/docs/failure-modes.md` (F01–F20).

## Skill entry points

- `context-loader` — load STATE + DESIGN + active task only  
- `codex-system` — delegate design/review/investigate (and exceptional implement) via `scripts/delegate-codex.ps1`  
- `verify-job` — post-implement gate (after Grok or Codex writes)  
- `init` — place or verify the file SSOT (this tree or another app)  
- `startproject` — run the six-phase project kickoff  
- `plan` — produce a read-only, approval-gated plan (Codex)  
- `tdd` — red-green-refactor; Grok writes by default; Codex reviews  
- `simplify` — Codex audit first, then optional Grok fix  
- `checkpointing` — synchronize local STATE / PROGRESS  
- `design-tracker` — maintain design decisions and review evidence  

## Language

- Reply in the user's language.  
- Commit messages in English.
