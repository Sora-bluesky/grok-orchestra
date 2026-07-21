# Agent / skill registry

## Runtimes

| Name | Path / command | Tier |
|------|----------------|------|
| Grok (main) | `grok` | 1 |
| Codex (worker) | `codex exec` via `scripts/delegate-codex.ps1` | 2 |

## Skills (MVP)

| Skill | Path |
|-------|------|
| context-loader | `.agents/skills/context-loader/SKILL.md` |
| codex-system | `.agents/skills/codex-system/SKILL.md` |
| verify-job | `.agents/skills/verify-job/SKILL.md` |

## Rules

| Rule | Path |
|------|------|
| tiers | `.agents/rules/tiers.md` |
| role-boundaries | `.agents/rules/role-boundaries.md` |
| codex-delegation | `.agents/rules/codex-delegation.md` |
| isolation | `.agents/rules/isolation.md` |
