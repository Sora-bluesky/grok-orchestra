# STATE (example seed)

Copy to `.agents/STATE.md` (gitignored) and edit for your workspace.

| Key | Value |
|-----|--------|
| active_main | grok |
| worker | codex |
| phase | ready |
| isolation_default | L0 (+ L1 lease foundation) |
| last_job_id | — |
| last_job_status | — |
| notes | Grok implements by default; Codex designs/reviews/debugs by default |

## Working focus

- Keep Operator context thin.
- Prefer file packets over chat memory.
- One product-code writer at a time (Grok or Codex, not both).
- Use `scripts/lease-paths.ps1` when declaring `owned_paths` for write leases.
