---
name: tdd
description: Run a short red-green-refactor chain with Grok writes by default and independent Codex review.
---

# tdd

## Inputs

- Expected behavior and acceptance command
- Relevant source and test paths

## Steps

1. **Red:** Grok adds or proves one failing test (smallest change).
2. Operator runs **verify-job** and confirms the expected failure evidence.
3. **Green:** Grok applies the minimum behavior change.
4. Operator runs **verify-job** and the acceptance command.
5. **Refactor:** only when evidence supports it; Grok applies a bounded refactor.
6. For non-trivial green/refactor: Codex `review` via **codex-system**, then fold findings.
7. Final **verify-job**; record results in local `.agents/STATE.md` and `PROGRESS.md`.

## Exception

- If red/green would bloat Operator context, use Codex `implement` as an exception (Prompt Contract + L0).

## Circuit breaker

- If the same operation fails twice, stop, report the evidence, and replan or ask the user.
- Do not delete or weaken tests solely to pass.

## Output

- Verified red, green, and optional refactor evidence
- Optional review packet under `.agents/docs/packets/` or `.agents/docs/reviews/`
