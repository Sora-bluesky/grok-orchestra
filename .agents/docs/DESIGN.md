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

## Open design questions

- Phase 2: which workflow skills to port first after smoke
- Phase 3: whether MCP `codex mcp-server` adds value over CLI
