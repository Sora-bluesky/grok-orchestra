# Orchestra failure modes (F01–F20)

Design requirements, not soft tips. Full research notes in playground plan §3.4.

| ID | Mode | Mitigation in this repo |
|----|------|-------------------------|
| F01 | Context pollution / rot | Worker clean context; parent takes summaries; context-loader diet |
| F02 | Context poisoning | assumptions/unverified in packets; evidence-backed facts |
| F03 | Context clash | Priority order in AGENTS.md |
| F04 | Telephone / handoff loss | Prompt Contract hard gate |
| F05 | Compounding error chain | Short jobs + gate; circuit breaker |
| F06 | False done | verify-job; worker prose ≠ done |
| F07 | Tests weakened | Diff blocks skip/delete tests |
| F08 | Dual write / race | L0/L1/L2 isolation.md |
| F09 | Silent invariant break | DESIGN invariants; user gate on risk |
| F10 | Over-autonomy / yolo merge | No auto-merge; no danger default |
| F11 | Cost blowup | Serial implement default; thin parent context |
| F12 | Compaction amnesia | File SSOT (STATE, packets, results) |
| F13 | Orchestrator implements | Non-goals in AGENTS |
| F14 | Role theater | Enforce sandbox + paths + packet |
| F15 | Stale flags / scripts | Native `codex exec`; check.ps1 later |
| F16 | State drift | `.agents/` SSOT |
| F17 | Infinite debug loop | 2-strike circuit breaker |
| F18 | Approval fatigue → danger | Sandbox ladder |
| F19 | Secret in logs | gitignore logs; no tokens in results |
| F20 | Shared-memory myth | Document: packets only |

## Sources (type)

- Anthropic context engineering / multi-agent guidance
- HumanLayer ACE (subagents = context control)
- CCO team-execute + CLI guardrails
- X/forums: cost of re-read context, compaction loss, parallel agents breaking invariants
- sora harness / operator-judgment rules
