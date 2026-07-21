# Agent / skill registry

## Runtimes

| Name | Path / command | Tier |
|------|----------------|------|
| Grok (main) | `grok` | 1 |
| Codex (worker) | `codex exec` via `scripts/delegate-codex.ps1` | 2 |

## Skills

| Skill | Path |
|-------|------|
| context-loader | `.agents/skills/context-loader/SKILL.md` |
| codex-system | `.agents/skills/codex-system/SKILL.md` |
| verify-job | `.agents/skills/verify-job/SKILL.md` |
| init | `.agents/skills/init/SKILL.md` |
| startproject | `.agents/skills/startproject/SKILL.md` |
| plan | `.agents/skills/plan/SKILL.md` |
| tdd | `.agents/skills/tdd/SKILL.md` |
| simplify | `.agents/skills/simplify/SKILL.md` |
| checkpointing | `.agents/skills/checkpointing/SKILL.md` |
| design-tracker | `.agents/skills/design-tracker/SKILL.md` |

## Scripts

| Script | Path |
|--------|------|
| delegate-codex | `scripts/delegate-codex.ps1` |
| lease-paths (L1) | `scripts/lease-paths.ps1` |

## Rules

| Rule | Path |
|------|------|
| tiers | `.agents/rules/tiers.md` |
| role-boundaries | `.agents/rules/role-boundaries.md` |
| codex-delegation | `.agents/rules/codex-delegation.md` |
| isolation | `.agents/rules/isolation.md` |
