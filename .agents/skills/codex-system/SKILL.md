---
name: codex-system
description: Delegate design, review, debug, or exceptional implement work to Codex CLI via scripts/delegate-codex.ps1. Default Sol roles are design/review/debug.
---

# codex-system

## Default vs exception

| Type | When |
|------|------|
| `design`, `investigate`, `review` | **Default** Sol work |
| `implement`, `fix` | **Exception** only (context bloat / long batch / user request). Prefer Grok implement. |

## Steps

1. Confirm Prompt Contract complete (see `.agents/rules/codex-delegation.md`).
2. Write `.agents/docs/packets/{id}.prompt.txt`.
3. Run:

```powershell
.\scripts\delegate-codex.ps1 -JobId {id} -Type {review|design|investigate|implement|fix} -PromptFile .agents\docs\packets\{id}.prompt.txt
```

4. Read `.agents/logs/codex/{id}.last.txt` (summarize if long — F01).
5. If type is `implement` or `fix`, run **verify-job**.
6. If type is `review` after a Grok patch, fold findings then **verify-job** before done.
7. Update `.agents/STATE.md`.

For L1 on exceptional write jobs, declare `owned_paths` and pass `-OwnedPaths`. Empty `OwnedPaths` keeps L0-only behavior.

## Types → sandbox

| Type | Sandbox |
|------|---------|
| review, design, investigate | read-only |
| implement, fix | workspace-write |

## Forbidden

- danger-full-access by default
- Starting a second write job while one is running (L0) — includes Grok already writing product code
- Skipping verify-job after writes
- Using Codex implement as the default path for interactive scoped work

## Cost note (F11)

Prefer serial jobs. Prefer read-only Sol calls. Parallel write only after L1/L2.
