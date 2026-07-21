---
name: startproject
description: Kick off a project through six short phases and create the first Codex packet.
---

# startproject

## Inputs

- User goal and constraints
- Existing `AGENTS.md` and `.agents/STATE.md`

## Six phases

1. **Goal:** write one measurable objective.
2. **Constraints:** record forbidden actions, approval boundaries, and acceptance checks.
3. **Topology:** choose Operator, worker, sandbox, and L0/L1 isolation.
4. **Packet scaffold:** create `.agents/docs/packets/{id}.prompt.txt` with the full Prompt Contract.
5. **Seeds:** add minimal decisions to `.agents/docs/DESIGN.md` and progress to `PROGRESS.md`.
6. **First job:** record the job id and next action in `.agents/STATE.md`.

## Routing

- Operator handles facts, small seeds, and coordination.
- Use **codex-system** for design, investigation, or multi-file implementation.
- Wait for required user approval before an implementation job.
- After `implement` or `fix`, the Operator runs **verify-job**.

## Output

- `.agents/docs/packets/{id}.prompt.txt`
- Updated `.agents/STATE.md`, `.agents/docs/DESIGN.md`, and `PROGRESS.md`
