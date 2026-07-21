# Changelog

All notable changes to this project are documented in this file.

## [v0.2.0] - 2026-07-21

### Highlights

- establish the verification baseline: Pester test suite (40 tests) + GitHub Actions CI on `windows-latest` ([#9](https://github.com/Sora-bluesky/grok-orchestra/pull/9))
- mechanize the conventions: `scripts/check.ps1` (environment doctor + stale-lock GC) and `scripts/verify-job.ps1` (mechanical done gate) ([#10](https://github.com/Sora-bluesky/grok-orchestra/pull/10))
- add `scripts/install.ps1` — one-command, non-destructive install of the harness into another project tree ([#11](https://github.com/Sora-bluesky/grok-orchestra/pull/11))
- publish a real-transcript end-to-end walkthrough (EN/JA) ([#13](https://github.com/Sora-bluesky/grok-orchestra/pull/13))
- overhaul README (EN/JA) to full template-grade documentation ([#12](https://github.com/Sora-bluesky/grok-orchestra/pull/12))
- the entire release was **dogfooded**: Grok executed advisor plans through this harness's own packet → delegate → review → verify loop ([#8](https://github.com/Sora-bluesky/grok-orchestra/pull/8))

### Release scope

- `tests/` Pester 5 suite covering lease overlap/traversal, Prompt Contract gate, check/verify behavior, and installer idempotency; `-LockDir` parameter for test isolation ([#9](https://github.com/Sora-bluesky/grok-orchestra/pull/9), [#10](https://github.com/Sora-bluesky/grok-orchestra/pull/10), [#11](https://github.com/Sora-bluesky/grok-orchestra/pull/11))
- `.github/workflows/ci.yml`: Pester on push/PR
- `scripts/check.ps1`: tool presence, SSOT layout, PID-based stale write-lock detection (`-Fix` cleans provable-stale locks/leases), gitignore hygiene
- `scripts/verify-job.ps1`: result-log check, diff scope vs `owned_paths` (staged + unstaged + untracked), stub-marker scan, F07 test-weakening detection (deletion, rename-out, skip markers) with explicit `-AcceptTestChanges` override
- `scripts/lib/path-normalize.ps1`: shared segment-based path normalization used by lease-paths and verify-job (fixes leading-dot collapse and `../` bypass)
- `scripts/install.ps1`: `-Target` / `-DryRun` / `-Force`; never overwrites by default, reports every skip, generates a target-specific smoke packet, proposes `AGENTS.grok-orchestra.md` beside an existing contract
- `docs/walkthrough.md` / `docs/walkthrough.ja.md`: captured (never fabricated) transcripts of the full check → packet → delegate → verify cycle
- `plans/`: advisor audit handoff, dogfooding protocol, bounded PR-review-bot protocol, errata and deferred-findings ledger
- record PID in `write-job.lock`; collapse a redundant branch in `delegate-codex.ps1` ([#10](https://github.com/Sora-bluesky/grok-orchestra/pull/10))

### Safety and operations

- bounded review-bot protocol: triage fix / defer / decline with evidence, max 2 fix rounds per PR, escalate on repeats (exercised live on [#10](https://github.com/Sora-bluesky/grok-orchestra/pull/10), [#11](https://github.com/Sora-bluesky/grok-orchestra/pull/11), [#13](https://github.com/Sora-bluesky/grok-orchestra/pull/13))
- verify-job hardening from review: BaseRef option-injection rejection, fail-closed git invocation, full-SHA preservation, untracked-content scanning
- known limitations recorded (not silently shipped): quoted porcelain paths for non-ASCII filenames, adversarial leading-whitespace filenames, unbounded untracked-file scan size, symlinked self-target in installer — see `plans/README.md` Follow-up/deferred

### Validation

- Pester 40/40 passing locally and in CI at release commit
- `check.ps1` exit 0 (FAIL=0 WARN=0 OK=9) on a clean clone
- `verify-job.ps1 -SkipLog` PASS on a clean tree; walkthrough transcripts recaptured from a clean tree
- installer exercised end-to-end: fresh install, second-run idempotency (all skips reported), existing-`AGENTS.md` non-destruction, `-DryRun` zero writes

### Full Changelog

- [v0.1.0...v0.2.0](https://github.com/Sora-bluesky/grok-orchestra/compare/v0.1.0...v0.2.0)

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
