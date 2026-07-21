---
name: verify-job
description: Operator verification gate after Codex implement/fix. Required for done (F06/F07/F09). Never trust worker prose alone.
---

# verify-job

Run after every `implement` or `fix` job. Optional dry-run after review.

## Checklist

1. **Status**
   - [ ] `.agents/logs/codex/{id}.last.txt` exists and is non-empty
   - [ ] Exit code of delegate script was 0 (or failure explained)

2. **Diff**
   - [ ] `git status` / `git diff` inspected
   - [ ] No unapproved mass deletions
   - [ ] No new stub-only implementations if real logic was required (`pass`, `TODO`, `NotImplementedError`)
   - [ ] No edits outside owned_paths (if declared)

3. **Tests (F07)**
   - [ ] Acceptance commands from the packet **re-run by Operator**
   - [ ] No test files deleted or skipped solely to pass

4. **Invariants (F09)**
   - [ ] `.agents/docs/DESIGN.md` invariants still hold
   - [ ] High-risk changes flagged for user approval before merge

5. **Decision**
   - [ ] `success` — report summary to user
   - [ ] `needs_rework` — new packet with concrete gaps
   - [ ] `blocked` — ask user

## Never

- Mark done because Codex said “done”
- Auto-merge to main without user/operator explicit step
