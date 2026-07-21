# Grok operator rules (thin)

1. Load root `AGENTS.md` first; seed `.agents/STATE.md` from `STATE.example.md` if missing.
2. **Default:** Grok implements; Codex designs/reviews/debugs via `codex-system`.
3. After non-trivial Grok patches → Codex `review` packet, then **verify-job**.
4. Codex `implement` only as exception (context bloat / long batch / user request).
5. Never treat Codex prose as done without verify-job for write jobs.
6. Keep parent context thin: summaries only (F01).
7. Shared memory is files only (F20).
8. Circuit breaker: same failure twice → stop (F17).
9. Details: `.agents/rules/*` and `.agents/docs/failure-modes.md`.
