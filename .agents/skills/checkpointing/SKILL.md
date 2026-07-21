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
3. Optionally append concise verified progress to `PROGRESS.md` (gitignored).
4. Link relevant packet, result, or review files under `.agents/`.
5. Use **codex-system** only when reconciliation needs broad investigation; include the Prompt Contract.
6. If reconciliation writes product files, treat it as a write and run **verify-job**.

## F12 guard

- Files are the SSOT. Never claim state from compacted conversation memory alone.

## Output

- Synchronized `.agents/STATE.md` (and optional `PROGRESS.md`)
