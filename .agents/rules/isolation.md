# Isolation

## L0 — Sequential single-writer (default)

- Only one **product-code writer** at a time: Grok **or** a Codex write job — not both.
- While a Codex `implement` / `fix` job is running, Operator must not edit product code in the same cwd.
- While Grok is implementing product code, do not start a Codex write job on the same tree.
- Operator may always: read files, run tests, edit docs under `.agents/docs/`, update local STATE.
- Multiple Codex `read-only` jobs may run (no product file writes from those workers).

## L1 — File-ownership leases

- L0 remains the single-writer default. L1 records `owned_paths` for write jobs.
- Each write job may store `.agents/locks/{job_id}.lease.json`.
- Schema: `job_id`, `owned_paths` (string array), `status` (`running` or `released`), `acquired_at` (ISO-8601), optional `type`.
- Normalize paths to repo-relative separators before comparison.
- Overlap = exact match or path-prefix match at a separator boundary → refuse spawn.
- Use `scripts/lease-paths.ps1 -Action acquire|check|release`.
- L1 is file ownership, **not** git worktrees.

## L2 — Git worktree per job (optional later)

Use only when:

1. Operator must keep editing the main tree while a worker writes, or  
2. Two write jobs must truly run in parallel, or  
3. Discardable failed experiments  

Path: `.agents/worktrees/{job_id}/` (gitignored).  
Invoke: `codex exec -C .agents/worktrees/{job_id}`.  
Merge only after **verify-job**.

## Anti-patterns

- Two writers on the same file
- Grok and Codex both implementing in one tree
- Assuming “roles” alone prevent conflicts (need sandbox + paths + locks)
