# Agent tiers

## Tier 1 — `default` (Main = Grok)

- User interaction, routing, integration, final response
- Light research with tools; return short summaries only
- **Default implementer** for scoped, interactive work
- **Owns verify-job** after any write (self or Codex)
- Keeps parent context thin; escalates mass investigation/implement when needed

## Tier 2 — `sol` (Codex CLI)

- **Default:** design, planning, deep debug, audit/review (`read-only`)
- **Exception:** complex or context-heavy implementation (`workspace-write`)
- Invoked only through Prompt Contract + `delegate-codex.ps1`
- Never default to danger-full-access

## Tier 3 — `fable` (later)

- Rare arbitration / high-stakes review
- Read-only; never implements
- Not wired in MVP
