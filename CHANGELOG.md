# Changelog

All notable changes to this project are documented in this file.

## [v0.1.0] - 2026-07-21

### Highlights

- ship the initial Grok-operator + Codex-worker harness template
- lock routing B: Grok implements by default; Codex designs, reviews, and investigates by default ([#3](https://github.com/Sora-bluesky/grok-orchestra/pull/3), [#6](https://github.com/Sora-bluesky/grok-orchestra/pull/6))
- add Prompt Contract hard gate and `scripts/delegate-codex.ps1` for Codex CLI jobs
- add L0 single-writer lock and L1 path-lease foundation (`scripts/lease-paths.ps1`)
- publish operator skills for plan, tdd, simplify, init, verify, and related workflows
- publish failure-mode catalog F01–F20 as design requirements

### Release scope

- bootstrap Phase 0–1 scaffold: `AGENTS.md`, `.agents/` SSOT, rules, smoke packet
- add Phase 2 workflow skills: `init`, `startproject`, `plan`, `tdd`, `simplify`, `checkpointing`, `design-tracker`
- keep live session files local-only (`STATE.md`, `PROGRESS.md`) via gitignore ([#1](https://github.com/Sora-bluesky/grok-orchestra/pull/1))
- rewrite public README for template users; move embed-into-another-project guidance into `init` ([#2](https://github.com/Sora-bluesky/grok-orchestra/pull/2), [#6](https://github.com/Sora-bluesky/grok-orchestra/pull/6))
- clarify investigate = read-only diagnosis; fix application = Grok by default ([#6](https://github.com/Sora-bluesky/grok-orchestra/pull/6))
- drop public “what this is not” disclaimers that added noise ([#5](https://github.com/Sora-bluesky/grok-orchestra/pull/5))
- remove internal session implement packet from the public tree ([#4](https://github.com/Sora-bluesky/grok-orchestra/pull/4))
- add `docs/architecture.md`, `.codex/AGENTS.md`, and thin `.grok/rules/operator.md`

### Safety and operations

- Prompt Contract incomplete → refuse `codex exec`
- default sandbox ladder: review/design/investigate = `read-only`; implement/fix = `workspace-write` (exception path only)
- danger-full-access / yolo is not a default
- done means Operator `verify-job`, never worker prose alone
- circuit breaker: same failure twice → stop
- main branch requires pull requests; force-push and branch delete are blocked
- secret-like patterns are blocked by global git-guard pre-commit / pre-push hooks
- live session and runtime logs stay out of the published tree (gitignore)

### Distribution

- source-only GitHub Release (no compiled binaries)
- install by cloning or using the repository as a template
- entrypoints: root `AGENTS.md`, `scripts/delegate-codex.ps1`, `scripts/lease-paths.ps1`
- bilingual README: [README.md](README.md) / [README.ja.md](README.ja.md)

### Validation

- Codex read-only smoke packet: `smoke-001` via `scripts/delegate-codex.ps1`
- L1 lease acquire / overlap-refuse / release path exercised for `lease-paths.ps1`
- release materials avoid secret-like values and local private path dumps
- GitHub Release body matches this changelog section for `v0.1.0`

### Full Changelog

- [Initial commit history through v0.1.0](https://github.com/Sora-bluesky/grok-orchestra/commits/v0.1.0)
