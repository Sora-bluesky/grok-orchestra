---
name: checkpointing
description: Synchronize durable file state at session end and phase gates to prevent context-loss errors.
---

# checkpointing

## When

- At session end
- At a phase gate
- Before context compaction or a worker handoff

## Steps

1. Read the current packet and verified evidence; do not rely on chat memory.
2. Update `.agents/STATE.md` with `last_job_id`, status, active phase, and one next action.
3. Append concise verified progress to `PROGRESS.md`.
4. Update `HANDOFF.md` with decisions, blockers, approval boundaries, and exact resume steps.
5. Link relevant packet, result, or review files under `.agents/`.
6. Use **codex-system** only when reconciliation needs broad investigation; include the Prompt Contract.
7. If reconciliation writes product files, treat it as `implement` or `fix` and run **verify-job**.

## F12 guard

- Files are the SSOT. Never claim state from compacted conversation memory alone.

## Output

- Synchronized `.agents/STATE.md`, `PROGRESS.md`, and `HANDOFF.md`
