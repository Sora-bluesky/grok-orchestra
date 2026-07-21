---
name: simplify
description: Codex audits for bounded deletion or simplification; Grok applies an optional verified fix.
---

# simplify

## Inputs

- Target paths and behavior that must remain unchanged
- Current `.agents/docs/DESIGN.md` invariants

## Steps

1. Define a narrow target and explicit non-goals.
2. Create a complete Prompt Contract packet under `.agents/docs/packets/`.
3. Call **codex-system** with read-only type `review` or `investigate`.
4. Rank deletion and simplification opportunities by evidence, impact, and risk.
5. Do not perform drive-by refactors or unrelated formatting.
6. If the user approves a change, **Grok applies** the bounded fix (Codex `fix` only as exception).
7. Operator runs **verify-job** and checks behavior remains unchanged; Codex re-review if non-trivial.

## Output

- Read-only audit result under `.agents/docs/reviews/` or a packet plan
- Optional, separately verified fix
