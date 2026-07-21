---
name: tdd
description: Run a short red-green-refactor job chain with independent verification after each write.
---

# tdd

## Inputs

- Expected behavior and acceptance command
- Relevant source and test paths

## Steps

1. **Red:** create a focused packet that adds or proves one failing test.
2. Call **codex-system** for the smallest required `implement` or `fix` job.
3. Operator runs **verify-job** and confirms the expected failure evidence.
4. **Green:** create a new Prompt Contract packet for the minimum behavior change.
5. Run the write job, then Operator runs **verify-job** and the acceptance command.
6. **Refactor:** only when evidence supports it; use a separate bounded packet.
7. Run **verify-job** after the refactor and record results in `.agents/STATE.md` and `PROGRESS.md`.

## Circuit breaker

- If the same operation fails twice, stop, report the evidence, and replan or ask the user.
- Do not delete or weaken tests solely to pass.

## Output

- Short packets under `.agents/docs/packets/`
- Verified red, green, and optional refactor evidence
