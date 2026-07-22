# DESIGN

## Purpose

grok-orchestra is a template harness: Grok operates and **implements by default**; Codex (sol) designs, reviews, and debugs by default.

## Invariants

1. User-facing interface is Grok only.
2. Grok and Codex share state only via files under `.agents/` (and repo docs).
3. Write jobs are single-writer (L0) unless L1/L2 explicitly engaged — writer may be Grok or Codex, not both.
4. danger-full-access is never the default sandbox.
5. “Done” requires Operator verification for write jobs.
6. Codex implement is an **exception** (context bloat / long batch / explicit user request), not the default.
7. Codex “debug/investigate” is diagnosis + plan (`read-only`); applying the fix is a separate write step.

## Architecture (macro)

See `docs/architecture.md` and root `AGENTS.md`.

## Routing (locked)

| Default | Owner |
|---------|--------|
| Implement | Grok |
| Design / plan / investigate / review | Codex `read-only` |
| Apply fix / default implement | Grok |
| Verify | Grok (`verify-job`) |

## Isolation

| Level | Status | Mechanism |
|-------|--------|-----------|
| L0 | Default | `write-job.lock` via `delegate-codex.ps1` |
| L1 | Foundation (Phase 2) | `.agents/locks/{job_id}.lease.json` + `scripts/lease-paths.ps1` |
| L2 | Phase 3 (plan 006) | `scripts/worktree-job.ps1` + `delegate-codex.ps1 -Worktree` (collect never merges) |

**Implemented (doctor / verify):** `scripts/check.ps1` (tool/SSOT/stale lock-lease/gitignore) and `scripts/verify-job.ps1` (log, owned_paths scope, stub WARN, F07 test weakening) — judgment only, never auto-merge.

## Workflow skills (Phase 2)

`init` → `startproject` → `plan` → (`tdd` / implement) → `simplify` → `checkpointing`; design decisions tracked by `design-tracker`.

## Open design questions

- Phase 3: whether MCP `codex mcp-server` adds value over CLI
- Phase 3: optional hooks (worktree helper landed in plan 006)
