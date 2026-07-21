# エンドツーエンド walkthrough（実サイクル 1 周）

このページは **実際に採取した** packet → `delegate-codex` → Codex レビュー → `verify-job` の 1 サイクルを示します。使う fixture はこのリポジトリ同梱のものです。

以下のトランスクリプトは **2026-07-21**（ブランチ `docs/004-walkthrough-demo`）に採取しました。環境固有の絶対パスは `<repo>` に置換、または省略しています。`.agents/logs/` 配下は **gitignore** のまま — 本文には抜粋のみ載せます。

## 1. 前提（`check.ps1`）

```powershell
.\scripts\check.ps1
```

実出力（パスはスクラブ済み）:

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

終了コード: **0**。

`tool:codex` が **FAIL** のときは `codex login` 等で Codex を使える状態にしてから進めてください。レビュー文面を捏造しないでください。

## 2. Prompt Contract packet を書く

必須 5 見出しを持つ packet を用意します。このリポジトリでは walkthrough 用を同梱しています:

`.agents/docs/packets/walkthrough-001.prompt.txt`

全文:

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

### 5 見出しが必要な理由

`scripts/delegate-codex.ps1` は不完全な packet を **Codex 呼び出し前に** 拒否します。`## Constraints` 欠落時の実エラー（本 walkthrough で採取）:

```text
Prompt Contract incomplete. Missing: ## Constraints
```

これが Prompt Contract ゲートです。不完全なジョブはサンドボックスを起動しません。

## 3. 委譲と結果の読み方

```powershell
.\scripts\delegate-codex.ps1 -JobId walkthrough-001 -Type review -PromptFile .agents\docs\packets\walkthrough-001.prompt.txt
```

実ホスト出力:

```text
delegate-codex: job=walkthrough-001 type=review sandbox=read-only cwd=<repo>
OK: wrote <repo>\.agents\logs\codex\walkthrough-001.last.txt
```

終了コード: **0**。最終メッセージは **gitignore** です。ローカルで:

```powershell
Get-Content .agents\logs\codex\walkthrough-001.last.txt -Encoding utf8
```

Codex 回答の実抜粋（UTF-8 で 554 文字。全文はローカルの `.last.txt`）:

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

## 4. 検証（done の定義）

ワーカーの文章だけでは done ではありません。機械ゲートを回します:

```powershell
.\scripts\verify-job.ps1 -JobId walkthrough-001
```

**クリーンな working tree** 上での実出力（パスはスクラブ済み。2026-07-21 にコミット後に再採取 — 件数は手編集しない）:

```text
[PASS] status:log: non-empty: <repo>\.agents\logs\codex\walkthrough-001.last.txt
[PASS] diff:scope: owned_paths not set; 0 changed path(s) observed
[PASS] stub: no stub markers in added lines
[PASS] f07:tests: no test deletion or skip markers detected
verify-job: PASS
```

終了コード: **0**。

`verify-job.ps1` は必要だが **十分条件ではない**。ルート [AGENTS.md](../AGENTS.md) の **Done means** は、オペレーターが手動で締めくくることを要求します:

- [ ] packet の **Acceptance checks**（`## Acceptance checks` 下のコマンド／条件）を再実行する
- [ ] **diff** を確認する（`git status` / `git diff` — 想定外ファイルやスコープ逸脱がないか）
- [ ] 非自明な変更では Codex の **`review`** packet を通し、指摘を折り込んでから done にする

（`.agents/skills/verify-job/SKILL.md` も参照 — スクリプト出力は checklist の証跡であり、checklist の代替ではない。）

Codex ログ無しの Grok 直接実装では `-SkipLog` を使います。書き込みリース時は `-OwnedPaths` でスコープ逸脱を fail-closed にします。
## 5. 次の一歩: 自分のプロジェクトへ

ハーネスを別アプリに敷く（Plan 003）:

```powershell
.\scripts\install.ps1 -Target C:\path\to\your-app
```

STATE を seed し、生成された smoke packet の TODO を直し、`check.ps1` のあと **自分のパス** でこのサイクルを繰り返します。

## このページの再現

Codex ログイン済みの clone で:

```powershell
.\scripts\check.ps1
.\scripts\delegate-codex.ps1 -JobId walkthrough-001 -Type review -PromptFile .agents\docs\packets\walkthrough-001.prompt.txt
.\scripts\verify-job.ps1 -JobId walkthrough-001
```

各ステップ exit 0 と、非空の gitignored `.last.txt` を期待します。
