---
name: init
description: Initialize or verify the grok-orchestra file SSOT in this tree or another app workspace without overwriting existing state blindly.
---

# init

Use when bootstrapping **this** clone, or when placing the harness into **another project tree**.

## Inputs

- Target workspace root (default: current repo)
- Existing `AGENTS.md` / `.gitignore` if any
- Template files from a grok-orchestra source tree

## Steps — this repository

1. Inspect before writing; do not overwrite live `.agents/STATE.md` blindly.
2. Verify root `AGENTS.md` and `.agents/` SSOT (rules, skills, docs, packets, locks, logs).
3. Ensure `.gitignore` excludes logs, locks, and live session files (`STATE.md`, `PROGRESS.md`) while keeping `.gitkeep` placeholders.
4. Optionally seed `.agents/STATE.md` from `STATE.example.md`.
5. Record init notes in local STATE (and optional `PROGRESS.md`).

## Steps — another project (advanced)

First run `scripts/install.ps1 -Target <path>`; use this section for verifying the generated layout and merge decisions.

1. Copy or submodule into the target app as needed:
   - `.agents/` (rules, skills, docs structure)
   - `scripts/delegate-codex.ps1`, `scripts/lease-paths.ps1`
   - root contract pattern (`AGENTS.md`) and, if useful, `.codex/AGENTS.md` / `.grok/rules/`
2. **Merge carefully** with the app’s existing agent contract. Priority (see target `AGENTS.md`):
   1. User explicit instruction  
   2. Active job packet  
   3. Harness / project `AGENTS.md`  
   4. Skills  
   5. Model defaults  
3. Keep live session state **local** (do not publish):
   - `.agents/STATE.md` — phase / last job (seed from `STATE.example.md`)
   - `PROGRESS.md` — optional dated log
4. Adjust paths and smoke packet for the target app; do not assume grok-orchestra fixtures exist.
5. Run a small read-only Codex smoke in the target tree when ready.
6. After any product write, Operator runs **verify-job**.

## Forbidden

- Blind overwrite of the app’s existing `AGENTS.md` or user STATE
- Treating copy/paste as done without a smoke or verify path
- Committing live session files that should stay gitignored

## Output

- Verified SSOT layout in the target workspace
- Local STATE updated without destroying prior user state
