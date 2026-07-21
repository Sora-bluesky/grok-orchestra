# Architecture — grok-orchestra

## Intent

- **Grok** = Operator (Tier 1): user UI, default implementer, verify
- **Codex CLI** = Worker (Tier 2 / sol): design, review, debug by default; implement only as exception

## Lineage

| Source | Taken |
|--------|--------|
| [Claude Code Orchestra](https://github.com/DeL-TaiseiOzaki/claude-code-orchestra) | AGENTS contract, `.agents/` SSOT, tiers, Prompt Contract, file-ownership isolation, independent verification |
| [Antigravity Orchestra](https://github.com/Sora-bluesky/antigravity-orchestra) | Single UI, role split, workflow shapes, PS1 bridge (rewritten for native Windows) |

## Default routing

```text
User → Grok (orchestrate)
         ├─ implement (default) → optional Codex review → verify-job
         └─ Codex read-only (design / review / debug)
              └─ Codex workspace-write only as exception → verify-job
```

## Isolation

- **L0:** one product-code writer at a time
- **L1:** path leases (`scripts/lease-paths.ps1`)
- **L2:** optional git worktree per job

## Failure modes

[`.agents/docs/failure-modes.md`](../.agents/docs/failure-modes.md) — F01–F20 required mitigations.

## Runtime loop (Codex job)

1. Operator writes packet (Prompt Contract complete)
2. `scripts/delegate-codex.ps1` runs `codex exec`
3. Result → `.agents/logs/codex/{id}.last.txt`
4. Write jobs or non-trivial Grok patches → review as needed → `verify-job`
5. Update local STATE; report to user
