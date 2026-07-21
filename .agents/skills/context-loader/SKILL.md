---
name: context-loader
description: Load minimal orchestra context (STATE, DESIGN, active task). Use at session start or before routing. Anti context pollution (F01).
---

# context-loader

## Load only

1. `AGENTS.md` (if not already in system)
2. `.agents/STATE.md`
3. `.agents/docs/DESIGN.md` (skim invariants)
4. Active packet under `.agents/docs/packets/` if a job is in progress

## Do not load into parent

- Full Codex logs
- Entire research dumps
- Unrelated skills

## Output

Short bullet status: main agent, phase, last job, next action.
