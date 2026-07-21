# STATE

| Key | Value |
|-----|--------|
| active_main | grok |
| worker | codex |
| phase | 2-workflows |
| isolation_default | L0 (+ L1 lease foundation) |
| last_job_id | phase2-001 |
| last_job_status | success (Operator verified; Codex hung after file writes — Operator completed INDEX/HANDOFF/PROGRESS/DESIGN) |
| notes | Phase 2 skills + L1 lease helper in tree; next Phase 3 or public polish |

## Working focus

- Keep Operator context thin.
- Prefer file packets over chat memory.
- L0 single-writer default; use `scripts/lease-paths.ps1` when declaring `owned_paths`.
