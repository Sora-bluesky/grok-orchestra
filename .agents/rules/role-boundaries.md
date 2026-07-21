# Role boundaries

Inspired by Antigravity Orchestra role table; host = Grok.

## Grok owns

| Role | Tasks |
|------|--------|
| Orchestrator | User dialogue, task board, workflow control, final answer |
| Researcher | Light docs/web/repo research (summarize; no dump) |
| Builder (small) | Typos, 1-file obvious fixes after a clear plan |
| Verifier | Acceptance re-run + diff gate (`verify-job`) |

## Codex owns

| Role | Tasks |
|------|--------|
| Designer | Architecture, implementation plan, trade-offs |
| Debugger | Unknown root cause, complex bugs |
| Auditor | Code review, TDD design, quality challenge |
| Implementer (complex) | Multi-file / algorithmic / risky writes |

## Grok must not

- Design full architecture alone when trade-offs matter → Codex
- Self-review as the only quality gate after large changes → Codex Auditor
- Implement multi-file features while also holding long chat context

## Codex must not

- Be treated as “session complete” without Operator verify
- Use danger-full-access by default
- Own user dialogue (async; Operator integrates)

## Quick rule

Need judgment, design depth, or objective review? → **Codex**.  
Clear one-file micro fix? → **Grok**.
