---
name: plan
description: Produce an evidence-backed implementation plan through a read-only Codex job.
---

# plan

## Inputs

- Goal, constraints, relevant files, and acceptance checks
- Current `.agents/STATE.md` and `.agents/docs/DESIGN.md`

## Steps

1. Create `.agents/docs/packets/{id}.prompt.txt` with the complete Prompt Contract.
2. Call **codex-system** with type `design` or `investigate`; both are read-only.
3. Save the reviewed plan to `.agents/docs/packets/{id}.plan.md` or the project `docs/` directory.
4. Separate facts, assumptions, risks, rollback, and unresolved questions.
5. Update `.agents/STATE.md` with the plan job and approval boundary.
6. Wait for user approval before starting `implement` or `fix`.
7. If implementation is later approved, use a new packet and run **verify-job** afterward.

## Output

- A reviewable plan file
- No product-code changes from the planning job
