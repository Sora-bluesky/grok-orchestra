---
name: init
description: Initialize or verify the grok-orchestra file SSOT without overwriting existing project state.
---

# init

## Inputs

- Existing `AGENTS.md`, `.agents/STATE.md`, and `.gitignore`
- Template files under `.agents/`

## Steps

1. Inspect before writing; do not overwrite user `STATE.md` or project rules blindly.
2. Place or verify root `AGENTS.md` and the `.agents/` SSOT directories.
3. Verify `.agents/STATE.md`, `.agents/INDEX.md`, rules, skills, docs, packets, locks, and logs paths.
4. Ensure `.gitignore` excludes generated logs and transient locks while preserving required `.gitkeep` files.
5. Record initialization facts in `.agents/STATE.md` and `PROGRESS.md`.
6. For multi-file or non-obvious repair, create a Prompt Contract packet and call **codex-system**.
7. After any `implement` or `fix` job, the Operator runs **verify-job**.

## Output

- Verified project contract and `.agents/` SSOT
- Updated `.agents/STATE.md` without destroying prior user state
