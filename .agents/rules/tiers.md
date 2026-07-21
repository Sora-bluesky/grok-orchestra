# Agent tiers

## Tier 1 — `default` (Main = Grok)

- User interaction, routing, integration, final response
- Light research with tools; return short summaries only
- Tiny edits only (≤1 file, obvious)
- **Owns verify-job** after worker tasks

## Tier 2 — `sol` (Codex CLI)

- Design, planning, complex implementation, deep debug, audit
- Invoked only through Prompt Contract + `delegate-codex.ps1`
- Sandbox: `read-only` for design/review/debug; `workspace-write` for implement/fix
- Never default to danger-full-access

## Tier 3 — `fable` (later)

- Rare arbitration / high-stakes review
- Read-only; never implements
- Not wired in MVP
