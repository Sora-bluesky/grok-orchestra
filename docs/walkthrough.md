# End-to-end walkthrough (one real cycle)

This page shows a **real** packet → `delegate-codex` → Codex review → `verify-job` cycle on a clean tree, using only fixtures that ship with this repository.

All command transcripts below were captured on **2026-07-21** (branch `docs/004-walkthrough-demo`). Long host-specific absolute paths were replaced with `<repo>` or omitted so the excerpts stay portable. Log files under `.agents/logs/` stay **gitignored** — only excerpts are pasted here.

## 1. Prerequisites (`check.ps1`)

```powershell
.\scripts\check.ps1
```

Actual output (paths scrubbed):

```text
[OK] tool:codex: codex on PATH: <codex.exe>
[OK] ssot:AGENTS.md: present
[OK] ssot:.agents/INDEX.md: present
[OK] ssot:.agents/docs/failure-modes.md: present
[OK] ssot:scripts/delegate-codex.ps1: present
[OK] ssot:scripts/lease-paths.ps1: present
[OK] lock:write-job: absent
[OK] gitignore: has .agents/locks/*.lease.json
[OK] gitignore: has .agents/logs/codex/*.last.txt
check.ps1 summary: FAIL=0 WARN=0 OK=9
```

Exit code: **0**.

If `tool:codex` is **FAIL**, log in (`codex login`) or install Codex CLI before continuing. Do **not** invent review text.

## 2. Write a Prompt Contract packet

Create a packet with the five required headings. This repository ships a walkthrough packet:

`.agents/docs/packets/walkthrough-001.prompt.txt`

Full contents:

```text
## Objective
Walkthrough demo: review fixtures/sample.txt for clarity for a new contributor to grok-orchestra. Keep the answer short and concrete.

## Constraints
- read-only; do not modify any files
- Respond in Japanese
- Keep the whole answer under 40 lines
- Do not run network tools

## Relevant files
- fixtures/sample.txt
- AGENTS.md (optional skim)

## Acceptance checks
- Answer includes ## TL;DR
- Answer includes at least one concrete improvement suggestion with a sample rewrite line

## Output format
## TL;DR
## Analysis
## Plan
## Patch Strategy
## Validation
## Risks

## Assumptions
- Reader is an intermediate developer new to this repo

## Unverified
- None
```

### Why the five headings matter

`scripts/delegate-codex.ps1` refuses incomplete packets **before** calling Codex. Missing `## Constraints` fails immediately (captured for this walkthrough):

```text
Prompt Contract incomplete. Missing: ## Constraints
```

That gate is the Prompt Contract: incomplete jobs never waste a sandbox run.

## 3. Delegate and read the result

```powershell
.\scripts\delegate-codex.ps1 -JobId walkthrough-001 -Type review -PromptFile .agents\docs\packets\walkthrough-001.prompt.txt
```

Actual host lines:

```text
delegate-codex: job=walkthrough-001 type=review sandbox=read-only cwd=<repo>
OK: wrote <repo>\.agents\logs\codex\walkthrough-001.last.txt
```

Exit code: **0**. The last message file is **gitignored**; open it locally:

```powershell
Get-Content .agents\logs\codex\walkthrough-001.last.txt -Encoding utf8
```

Excerpt of the real Codex answer (554 UTF-8 characters; full file on disk):

```text
## TL;DR

`fixtures/sample.txt`は用途の方向性は分かりますが、対象読者と成功条件が曖昧です。

## Analysis

- 「smoke review」と「it」が何を指すか明確ではありません。
- 読み取り専用レビューで何を確認できれば成功なのか不足しています。
- 改善案だけでなく、期待する記述例があると新規参加者が理解しやすくなります。

## Plan

目的、対象読者、具体例の順に説明する構成を推奨します。

## Patch Strategy

今回は変更しません。書き換え例：

`Purpose: Verify that Codex can review a Prompt Contract without modifying product code.`

追加例：

`Audience: Contributors testing the grok-orchestra read-only review workflow.`

## Validation

`fixtures/sample.txt`の現内容を読み取り、ファイル変更は行っていません。

## Risks

文言をテストが完全一致で参照している場合、変更前に関連テストの確認が必要です。
```

## 4. Verify (definition of done)

Worker prose is never done by itself. Run the mechanical gate:

```powershell
.\scripts\verify-job.ps1 -JobId walkthrough-001
```

Actual output from a **clean working tree** (paths scrubbed; recaptured 2026-07-21 after commit — do not hand-edit counts):

```text
[PASS] status:log: non-empty: <repo>\.agents\logs\codex\walkthrough-001.last.txt
[PASS] diff:scope: owned_paths not set; 0 changed path(s) observed
[PASS] stub: no stub markers in added lines
[PASS] f07:tests: no test deletion or skip markers detected
verify-job: PASS
```

Exit code: **0**.

`verify-job.ps1` is necessary but **not sufficient**. Root [AGENTS.md](../AGENTS.md) **Done means** still requires the Operator to finish the job by hand:

- [ ] Re-run the packet’s **Acceptance checks** (commands or assertions under `## Acceptance checks`)
- [ ] Inspect the **diff** (`git status` / `git diff`) for unexpected files or scope escape
- [ ] For non-trivial changes, land a Codex **`review`** packet and fold findings before calling done

(See also `.agents/skills/verify-job/SKILL.md` — script output is evidence for the checklist, not a replacement for it.)

For Grok-direct edits without a Codex log, use `-SkipLog`. For write leases, pass `-OwnedPaths` so scope escapes fail closed.

## 5. Next step: your own project

Install the harness into another app tree (Plan 003). `-Target` must already exist:

```powershell
$app = Join-Path $env:TEMP 'grok-orchestra-install-demo'
New-Item -ItemType Directory -Force -Path $app | Out-Null
.\scripts\install.ps1 -Target $app
```

Then in that directory seed local state, edit the generated smoke packet TODOs, run `check.ps1`, and repeat this cycle with **your** paths.

## Reproduce this page

From a clone with Codex logged in:

```powershell
.\scripts\check.ps1
.\scripts\delegate-codex.ps1 -JobId walkthrough-001 -Type review -PromptFile .agents\docs\packets\walkthrough-001.prompt.txt
.\scripts\verify-job.ps1 -JobId walkthrough-001
```

Expect exit 0 on each step and a non-empty gitignored `.last.txt`.
