# Role boundaries

Inspired by Antigravity Orchestra role table; host = Grok.

## Default split (locked)

| Concern | Owner |
|---------|--------|
| Implement (default) | **Grok** |
| Design / plan / trade-offs | **Codex** `read-only` |
| Review / audit / QA | **Codex** `read-only` |
| Debug (unknown root cause) | **Codex** `read-only` |
| Final verify / user dialogue | **Grok** |

## Grok owns

| Role | Tasks |
|------|--------|
| Orchestrator | User dialogue, task board, workflow control, final answer |
| Researcher | Light docs/web/repo research (summarize; no dump) |
| Builder (default) | Implementation and fixes within a clear plan; keep parent context manageable |
| Verifier | Acceptance re-run + diff gate (`verify-job`) |

## Codex owns

| Role | Tasks |
|------|--------|
| Designer | Architecture, implementation plan, trade-offs |
| Debugger | Unknown root cause, complex bugs (returns diagnosis / plan) |
| Auditor | Code review, TDD design critique, quality challenge |
| Implementer (exception) | Only when Operator context would bloat, batch is unattended, or user forces it |

## Grok must not

- Design full architecture alone when trade-offs matter → Codex Designer
- Self-review as the only quality gate after non-trivial changes → Codex Auditor
- Dump broad investigation logs into the parent context → Codex investigate + short summary
- Run a Codex `workspace-write` job while also editing product code (F08)

## Codex must not

- Be treated as “session complete” without Operator verify
- Use danger-full-access by default
- Own user dialogue (async; Operator integrates)
- Be the default implementer for interactive, scoped work

## Quick rule

Need judgment, design depth, or objective review? → **Codex**.  
Need code changed under a clear plan? → **Grok**, then Codex review when non-trivial.
