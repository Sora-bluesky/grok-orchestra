# DESIGN

## Purpose

grok-orchestra is a template harness: Grok operates; Codex executes specialized work.

## Invariants

1. User-facing interface is Grok only (no Claude Code worker path).
2. Grok and Codex share state only via files under `.agents/` (and repo docs).
3. Write jobs are single-writer (L0) unless L1/L2 explicitly engaged.
4. danger-full-access is never the default sandbox.
5. “Done” requires Operator verification for write jobs.

## Architecture (macro)

See `docs/architecture.md` and root `AGENTS.md`.

## Isolation

| Level | Status | Mechanism |
|-------|--------|-----------|
| L0 | Default | `write-job.lock` via `delegate-codex.ps1` |
| L1 | Foundation (Phase 2) | `.agents/locks/{job_id}.lease.json` + `scripts/lease-paths.ps1` |
| L2 | Later (Phase 3) | Optional git worktree per job |

## Workflow skills (Phase 2)

`init` → `startproject` → `plan` → (`tdd` / implement) → `simplify` → `checkpointing`; design decisions tracked by `design-tracker`.

## Open design questions

- Phase 3: whether MCP `codex mcp-server` adds value over CLI
- Phase 3: optional hooks / `check.ps1` / worktree helper
