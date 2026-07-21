# Architecture — grok-orchestra

## Intent

Grok = Operator (Tier 1). Codex CLI = Worker (Tier 2). No Claude Code worker.

## Lineage

| Source | Taken |
|--------|--------|
| [Claude Code Orchestra](https://github.com/DeL-TaiseiOzaki/claude-code-orchestra) | AGENTS contract, `.agents/` SSOT, tiers, Prompt Contract, file-ownership isolation, independent verification |
| [Antigravity Orchestra](https://github.com/Sora-bluesky/antigravity-orchestra) | Single UI, role split, workflow shapes, PS1 bridge (rewritten for native Windows) |

## Isolation

- **CCO:** file ownership for parallel writers; not git worktree core
- **This repo:** L0 single-writer → L1 leases → L2 worktree optional

## Failure modes

`.agents/docs/failure-modes.md` — F01–F20 required mitigations.

## Runtime loop

1. Operator writes packet (Prompt Contract complete)
2. `scripts/delegate-codex.ps1` runs `codex exec`
3. Result → `.agents/logs/codex/{id}.last.txt`
4. Write jobs → `verify-job`
5. Update STATE; report to user
