# Isolation

## L0 — Sequential single-writer (default)

- Only one **product-code writer** at a time: Grok **or** a Codex write job — not both.
- While a Codex `implement` / `fix` job is running, Operator must not edit product code in the same cwd.
- While Grok is implementing product code, do not start a Codex write job on the same tree.
- Operator may always: read files, run tests, edit docs under `.agents/docs/`, update local STATE.
- Multiple Codex `read-only` jobs may run (no product file writes from those workers).
- Mechanism: `scripts/delegate-codex.ps1` acquires `.agents/locks/write-job.lock` for implement/fix on the main tree.

## L1 — File-ownership leases

- L0 remains the single-writer default. L1 records `owned_paths` for write jobs.
- Each write job may store `.agents/locks/{job_id}.lease.json`.
- Schema: `job_id`, `owned_paths` (string array), `status` (`running` or `released`), `acquired_at` (ISO-8601), optional `type`.
- Normalize paths to repo-relative separators before comparison.
- Overlap = exact match or path-prefix match at a separator boundary → refuse spawn.
- Use `scripts/lease-paths.ps1 -Action acquire|check|release`.
- L1 is file ownership, **not** git worktrees.
- L1 applies only to main-tree write jobs (not L2).

## L2 — Git worktree per job (scripted)

Use when:

1. Operator must keep editing the main tree while a worker writes, or  
2. Two write jobs must truly run in parallel, or  
3. Discardable failed experiments  

### Canonical API

```powershell
# create
.\scripts\worktree-job.ps1 -Action new -JobId <id> [-BaseRef <sha>] [-OwnedPaths @('src')] [-SkipLog]

# after worker commits in the worktree
.\scripts\worktree-job.ps1 -Action collect -JobId <id> [-AcceptTestChanges]
# → runs verify-job -RepoRoot <worktree> -BaseRef <base_sha>; prints diff --stat
# → -AcceptTestChanges forwards the F07 override to verify-job after Operator review
# → NEVER merges / rebases / cherry-picks (F10). Operator merges or opens a PR.

# remove worktree dir only (branch wt/<id> retained as evidence)
.\scripts\worktree-job.ps1 -Action cleanup -JobId <id> [-Force]
```

Or via delegate:

```powershell
.\scripts\delegate-codex.ps1 -JobId <id> -Type implement -PromptFile ... -Worktree [-OwnedPaths @('src')]
```

### Rules

- Path: `.agents/worktrees/{job_id}/` (gitignored). Branch: `wt/{job_id}`.
- Metadata: `.agents/locks/{job_id}.worktree.json` (gitignored) — L2 lease / exclusive claim.
- **`new` claims the JobId first** (`status=creating` via exclusive file create), then `git worktree add`, then flips to `status=active`.
- **Failure path is non-destructive for branches:** rollback never runs `git branch -D`. Branches are retained as evidence; Operator deletes manually.
- **Worktree dir removal in rollback only if this process completed `git worktree add`.** Pre-existing dirs/branches are never removed by a losing or early-failing `new`.
- L2 write jobs **do not** take main-tree `write-job.lock` and **do not** acquire L1 leases.
- `OwnedPaths` (if any) are stored in worktree.json and applied at collect-time verify.
- `collect -AcceptTestChanges` forwards `-AcceptTestChanges` to verify-job (legitimate test delete/rename/skip after Operator review). Without it, F07 failures leave status=`active`.
- Isolation is tree separation; still one writer **per worktree**.
- Manual `codex exec -C .agents/worktrees/...` is **not** the formal L2 path — use the helper so metadata, collect, and doctor stay consistent.
- Merge only after **verify-job** (via collect) and **Operator judgment** (F10).

### Doctor

`scripts/check.ps1` warns on active/collected worktree.json when the directory or branch is missing; `-Fix` marks `status=stale`.

`status=creating` claims:
- **Recent** empty claim (no dir, no branch, `created_at` younger than 15 minutes): WARN only — never auto-clear (live owner may be mid-`new`).
- **Aged** empty claim (≥15 minutes, no dir, no branch): WARN; `-Fix` may remove the claim file.
- **Partial** (dir and/or branch present, still `creating`): WARN only — **not auto-cleared**. Operator cleans manually. Deliberate safe trade: no auto-deletion of worktrees/branches that may hold work.

## Anti-patterns

- Two writers on the same file
- Grok and Codex both implementing in one tree
- Assuming “roles” alone prevent conflicts (need sandbox + paths + locks)
- Auto-merge / auto-PR from collect (F10 — permanent ban)
- L2 job that still takes main-tree L0/L1 (defeats parallel isolation and confuses check.ps1)
