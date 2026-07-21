# Isolation

## L0 — Sequential single-writer (default, MVP)

- Only one `implement` / `fix` job may be `running`.
- During that job, Operator must not edit product code in the same cwd.
- Operator may still: read files, run tests, edit docs under `.agents/docs/`, update STATE.
- Multiple `read-only` jobs may run (no file writes from workers).

## L1 — File-ownership leases (Phase 2)

- L0 `write-job.lock` remains the single-writer default. L1 adds ownership data for possible later parallel writers; the Operator still uses L0 today.
- Each write job declares `owned_paths` and stores `.agents/locks/{job_id}.lease.json`.
- Schema: `job_id`, `owned_paths` (string array), `status` (`running` or `released`), `acquired_at` (ISO-8601), and optional `type`.
- Normalize paths to repo-relative separators (`/` or `\`) before comparison.
- Overlap means exact match or a path-prefix match at a separator boundary.
- If any lease with `status=running` overlaps a requested path, refuse spawn.
- Use `scripts/lease-paths.ps1 -Action acquire|check|release`; L1 is file ownership, not git worktrees.

## L2 — Git worktree per job (Phase 3, optional)

Use only when:

1. Operator must keep editing main tree, or  
2. Two write jobs must truly run in parallel, or  
3. Discardable failed experiments  

Path: `.agents/worktrees/{job_id}/` (gitignored).  
Invoke: `codex exec -C .agents/worktrees/{job_id}`.  
Merge only after **verify-job**.

## What Claude Code Orchestra does

- Core parallel isolation = **file ownership**, not worktrees.
- `workspace.py` = artifact path SSOT (logs/docs), not code trees.

## Anti-patterns

- Two writers on the same file
- Operator + Codex both implementing in one tree
- Assuming “roles” alone prevent conflicts (need sandbox + paths + locks)
