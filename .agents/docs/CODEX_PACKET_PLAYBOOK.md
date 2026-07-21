# Codex handoff playbook

## Packet locations

| Kind | Path |
|------|------|
| Prompt body | `.agents/docs/packets/{id}.prompt.txt` |
| Last message | `.agents/logs/codex/{id}.last.txt` |
| Stderr log | `.agents/logs/codex/{id}.stderr.log` |

## Template — review

```markdown
## Objective
Review fixtures/sample.txt for clarity for a new contributor.

## Constraints
- read-only; do not modify files
- Japanese response
- Be concise (≤40 lines)

## Relevant files
- fixtures/sample.txt

## Acceptance checks
- Output includes TL;DR and at least one concrete improvement

## Output format
## TL;DR
## Analysis
## Plan
## Patch Strategy
## Validation
## Risks

## Assumptions
- Audience is intermediate developers

## Unverified
- None
```

## Template — implement

```markdown
## Objective
{one sentence change}

## Constraints
- Only edit owned paths listed below
- Do not weaken or delete tests to pass
- Forbidden: secrets, force push, danger flags

## Relevant files
- …

## Owned paths
- …

## Acceptance checks
- {exact commands}

## Output format
## TL;DR
## Analysis
## Plan
## Patch Strategy
## Validation
## Risks

## Assumptions
- …

## Unverified
- …
```

## After implement

Run verify-job skill checklist before telling the user the task is done.
