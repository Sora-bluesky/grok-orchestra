# Codex delegation

## When to call Codex

Call when **any** of:

- Design / architecture decisions
- Change spans 2+ files with behavior impact
- Root cause unclear
- User asks for comparison / trade-off
- Need a step-by-step implementation plan
- Need independent review after implementation

## When not to call

- Obvious one-file typo / rename
- Pure git commit / push ceremony (Operator)
- Running tests only (Operator can run)
- Missing Prompt Contract fields

## Prompt Contract (required)

```markdown
## Objective
{one sentence}

## Constraints
- {limits}
- Forbidden: {…}

## Relevant files
- path/a
- path/b

## Acceptance checks
- {command that exits 0 when done}

## Output format
## TL;DR
## Analysis
## Plan
## Patch Strategy
## Validation
## Risks

## Assumptions
- {explicit}

## Unverified
- {items needing evidence}
```

## How to invoke

```powershell
.\scripts\delegate-codex.ps1 `
  -JobId <id> `
  -Type review|design|investigate|implement|fix `
  -PromptFile .agents\docs\packets\<id>.prompt.txt
```

Sandbox mapping is automatic in the script:

| Type | Sandbox |
|------|---------|
| review, design, investigate | read-only |
| implement, fix | workspace-write |

## After return

1. Read `.agents/logs/codex/<id>.last.txt` (summary; do not paste full dump into parent if huge)
2. If `implement` or `fix` → run **verify-job**
3. Update `.agents/STATE.md` last_job_* fields
