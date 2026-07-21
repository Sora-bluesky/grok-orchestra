---
name: startproject
description: Kick off a project through six short phases and create the first planning packet.
---

# startproject

## Inputs

- User goal and constraints
- Existing `AGENTS.md` and optional `.agents/STATE.md`

## Six phases

1. **Goal:** write one measurable objective.
2. **Constraints:** record forbidden actions, approval boundaries, and acceptance checks.
3. **Topology:** Operator = Grok (default implement); Codex = design/review/debug; L0 isolation.
4. **Packet scaffold:** create `.agents/docs/packets/{id}.prompt.txt` with the full Prompt Contract when Codex is needed.
5. **Seeds:** add minimal decisions to `.agents/docs/DESIGN.md` and optional progress notes.
6. **First job:** record the job id and next action in `.agents/STATE.md`.

## Routing

- Operator coordinates and **implements by default**.
- Use **codex-system** for design, investigation, and review.
- Codex `implement` only as exception (context bloat / long batch / user request).
- Wait for required user approval before risky implementation.
- After product writes, the Operator runs **verify-job** (and Codex review when non-trivial).

## Output

- Optional `.agents/docs/packets/{id}.prompt.txt`
- Updated `.agents/STATE.md` and `.agents/docs/DESIGN.md`
