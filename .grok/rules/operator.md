# Grok operator rules (thin)

1. Load root `AGENTS.md` and `.agents/STATE.md` first.
2. Large work → Codex via `codex-system` / `scripts/delegate-codex.ps1`.
3. Never treat Codex output as done without `verify-job` for write jobs.
4. Keep parent context thin: summaries only (F01).
5. Shared memory is files only (F20).
6. Circuit breaker: same failure twice → stop (F17).
7. Details: `.agents/rules/*` and `.agents/docs/failure-modes.md`.
