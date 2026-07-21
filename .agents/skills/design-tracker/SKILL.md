---
name: design-tracker
description: Maintain design invariants and open questions with links to review evidence.
---

# design-tracker

## Inputs

- `.agents/docs/DESIGN.md`
- Evidence under `.agents/docs/packets/` and `.agents/docs/reviews/`

## Steps

1. Read current invariants and open questions before proposing a change.
2. For non-obvious design work, create a Prompt Contract packet and call **codex-system** with type `design` or `review`.
3. Save review evidence under `.agents/docs/reviews/` and link it from `DESIGN.md`.
4. Update invariants, decisions, consequences, and open questions minimally.
5. Never claim a design change without file, command, or review evidence.
6. Route approved multi-file implementation through **codex-system** with owned paths.
7. Operator runs **verify-job** after every `implement` or `fix` job.

## Output

- Updated `.agents/docs/DESIGN.md`
- Linked review evidence and explicit remaining questions
