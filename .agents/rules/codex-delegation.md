# Codex delegation

## When to call Codex (default uses)

Call when **any** of:

- Design / architecture decisions
- Independent review after non-trivial implementation
- Root cause unclear (debug / investigate)
- User asks for comparison / trade-off
- Need a step-by-step implementation plan

## When Codex may implement (exception only)

Call `implement` / `fix` with `workspace-write` only when **any** of:

- Change set would pollute Operator context (many files, long logs, mechanical mass edit)
- Unattended long batch is better than interactive Grok turns
- User explicitly requests Codex implement

Otherwise **Grok implements**.

## When not to call

- Scoped implementation Grok can do without context bloat
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

Prefer `review` / `design` / `investigate` for the default Sol role.

## After return

1. Read `.agents/logs/codex/<id>.last.txt` (summary; do not paste full dump into parent if huge)
2. If `implement` or `fix` → run **verify-job**
3. If `review` after Grok implement → fold findings into fix loop or accept, then **verify-job**
4. Update `.agents/STATE.md` last_job_* fields
