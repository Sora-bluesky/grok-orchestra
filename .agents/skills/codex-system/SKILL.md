---
name: codex-system
description: Delegate design, review, debug, or implement work to Codex CLI via scripts/delegate-codex.ps1. Use when Grok needs Tier-2 sol worker.
---

# codex-system

## Steps

1. Confirm Prompt Contract complete (see `.agents/rules/codex-delegation.md`).
2. Write `.agents/docs/packets/{id}.prompt.txt`.
3. Run:

```powershell
.\scripts\delegate-codex.ps1 -JobId {id} -Type {review|design|investigate|implement|fix} -PromptFile .agents\docs\packets\{id}.prompt.txt
```

4. Read `.agents/logs/codex/{id}.last.txt` (summarize if long — F01).
5. If type is `implement` or `fix`, run **verify-job**.
6. Update `.agents/STATE.md`.

For L1, declare `owned_paths` in the packet and pass `-OwnedPaths` for `implement` or `fix`. The wrapper calls `scripts/lease-paths.ps1` before spawn and releases the lease afterward. Empty `OwnedPaths` keeps L0-only behavior.

## Types → sandbox

| Type | Sandbox |
|------|---------|
| review, design, investigate | read-only |
| implement, fix | workspace-write |

## Forbidden

- danger-full-access by default
- Starting a second write job while one is running (L0)
- Skipping verify-job after writes

## Cost note (F11)

Prefer serial write jobs. Parallel implement only after L1/L2.
