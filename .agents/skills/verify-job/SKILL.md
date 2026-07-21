---
name: verify-job
description: Operator verification gate after Grok or Codex writes. Required for done (F06/F07/F09). Never trust implementer prose alone.
---

# verify-job

Run after every product write (Grok implement **or** Codex `implement`/`fix`).  
Optional dry-run after a Codex review.

機械化可能な項目は `scripts/verify-job.ps1 -JobId <id>` を先に実行し、その出力をこの checklist の証跡とする。

## Checklist

1. **Status**
   - [ ] If Codex was used: `.agents/logs/codex/{id}.last.txt` exists and is non-empty (or failure explained)
   - [ ] Exit code of delegate script was 0 when Codex ran

2. **Diff**
   - [ ] `git status` / `git diff` inspected
   - [ ] No unapproved mass deletions
   - [ ] No new stub-only implementations if real logic was required (`pass`, `TODO`, `NotImplementedError`)
   - [ ] No edits outside owned_paths (if declared)

3. **Independent review (non-trivial changes)**
   - [ ] Codex `review` packet run when the change is multi-file, behavioral, or security-sensitive
   - [ ] Findings either fixed or explicitly accepted with rationale

4. **Tests (F07)**
   - [ ] Acceptance commands **re-run by Operator**
   - [ ] No test files deleted or skipped solely to pass

5. **Invariants (F09)**
   - [ ] `.agents/docs/DESIGN.md` invariants still hold
   - [ ] High-risk changes flagged for user approval before merge

6. **Decision**
   - [ ] `success` — report summary to user
   - [ ] `needs_rework` — new packet or Grok fix with concrete gaps
   - [ ] `blocked` — ask user

## Never

- Mark done because Grok or Codex said “done”
- Auto-merge to main without user/operator explicit step
