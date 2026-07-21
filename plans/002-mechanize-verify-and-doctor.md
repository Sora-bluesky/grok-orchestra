# Plan 002: check.ps1(doctor)と verify-job.ps1 で「規約」を「機構」にする

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 8716814..HEAD -- scripts/ .agents/skills/verify-job/ .agents/docs/DESIGN.md`
> Plan 001 による `scripts/lease-paths.ps1` の `-LockDir` 追加と `tests/` の存在は
> 前提(依存)であり drift ではない。それ以外の不一致は STOP。

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED(delegate-codex.ps1 のロック書式変更を含む)
- **Depends on**: plans/001-ci-pester-baseline.md
- **Category**: dx / tech-debt
- **Planned at**: commit `8716814`, 2026-07-21

## Why this matters

このハーネスの中核価値は F06(偽の完了)と F07(テスト弱体化)の防止だが、現状の
verify-job は**手動チェックリスト**(`.agents/skills/verify-job/SKILL.md`)であり、
ステールロックの回収も「Remove only if stale」という人手判断に委ねられている
(`scripts/delegate-codex.ps1:85`)。プロセスがクラッシュするとロックが残留し、
以後の write ジョブが全部詰まる。`check.ps1` は DESIGN.md の open question
(「Phase 3: optional hooks / check.ps1 / worktree helper」)として既に構想されている。
このプランで診断と検証をスクリプト化し、人間の注意力への依存を減らす。

## Current state

- `scripts/delegate-codex.ps1` — 委譲ラッパー。関連箇所:
  - 83–92 行: write ジョブ時、`write-job.lock` の存在チェック → 無ければ作成。
    ロック内容は `job_id= / type= / started=` の 3 行のみで **PID を記録していない**
    → ステール判定が機械的にできない。Step 1 で PID を追加する。
  - 105–111 行: 冗長な if/else(両分岐とも `'exec'` を追加):
    ```powershell
    $argList += $inv.ArgsPrefix
    if ($inv.ArgsPrefix.Count -eq 0) {
      $argList += 'exec'
    } else {
      $argList += 'exec'
    }
    ```
    → Step 1 で `$argList += 'exec'` の 1 行に簡約する(挙動不変)。
- `.agents/skills/verify-job/SKILL.md` — 手動チェックリスト。機械化対象の項目:
  ログ非空・diff の owned_paths 逸脱・スタブ実装(`TODO` / `NotImplementedError` /
  裸の `pass`)・テストファイル削除。
- `.agents/locks/` — `write-job.lock` と `*.lease.json`(status フィールド:
  `running` / `released`)。すべて gitignored。
- `scripts/lease-paths.ps1` — Plan 001 適用後は `-LockDir` パラメータを持つ。
  lease JSON のフィールド: `job_id / owned_paths / status / acquired_at / type(任意)`。
- packet 規約(`.agents/docs/packets/smoke-001.prompt.txt` 参照): `## Acceptance checks`
  見出しの下に検証コマンドが書かれる。

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| 回帰テスト | `Invoke-Pester -Path tests -PassThru` | `FailedCount = 0` |
| smoke(手動確認用) | `.\scripts\delegate-codex.ps1 -JobId smoke-001 -Type review -PromptFile .agents\docs\packets\smoke-001.prompt.txt` | exit 0、非空の `.agents/logs/codex/smoke-001.last.txt` |

## Scope

**In scope**:
- `scripts/delegate-codex.ps1`(PID 記録 + 105–111 行の簡約のみ)
- `scripts/check.ps1`(create)
- `scripts/verify-job.ps1`(create)
- `.agents/skills/verify-job/SKILL.md`(スクリプト参照の追記のみ — チェックリスト自体は残す)
- `tests/check.Tests.ps1`, `tests/verify-job.Tests.ps1`(create)
- `.agents/docs/DESIGN.md`(open question の check.ps1 行を「実装済み」に更新)

**Out of scope**:
- `scripts/lease-paths.ps1`(Plan 001 の変更以外触らない)
- hooks / MCP 化(DESIGN.md の残る open question — 別プラン)
- verify-job.ps1 による「自動マージ」や自動コミット(F10 違反になる。verify は判定のみ)

## Git workflow

- Branch: `feat/002-mechanize-verify-and-doctor`
- 機能追加(check/verify 新設)とリファクタ(105–111 行簡約)は**別コミット**にする
- push / PR 作成はユーザー確認後

## Steps

### Step 1: delegate-codex.ps1 の小改修(2 点、別コミット)

1. ロック内容に PID を追加(87–91 行のヒアストリングに `pid=$PID` 行を追加)。
2. 105–111 行を `$argList += 'exec'` に簡約(直前の `$argList += $inv.ArgsPrefix` は残す)。

**Verify**: `Invoke-Pester -Path tests -PassThru` → `FailedCount = 0`。
smoke コマンド実行 → exit 0(codex ログイン済み環境の場合のみ。未ログインなら
Contract 検査通過をもって可とし、その旨記録)。

### Step 2: scripts/check.ps1 を書く(doctor + ステール GC)

パラメータ: `[switch] $Fix`, `[string] $LockDir = ''`(既定は `.agents/locks`)。
チェック項目(結果を `OK / WARN / FAIL` で列挙し、FAIL があれば exit 1):

1. **ツール存在**: `Get-Command codex` または `%APPDATA%\npm\node_modules\@openai\codex\bin\codex.js`
   (delegate-codex.ps1 の `Resolve-CodexNodeInvocation` と同じ優先順)。無ければ FAIL。
2. **SSOT レイアウト**: `AGENTS.md`, `.agents/INDEX.md`, `.agents/docs/failure-modes.md`,
   `scripts/delegate-codex.ps1`, `scripts/lease-paths.ps1` の存在。欠落は FAIL。
3. **ステールロック**: `write-job.lock` が存在し、`pid=` 行の PID が
   `Get-Process -Id <pid>` で見つからない → WARN(`-Fix` 時は削除して報告)。
   PID 行が無い旧書式ロック → WARN(`-Fix` でも削除しない。手動確認を促す)。
4. **ステールリース**: `status = running` の lease で、`write-job.lock` が無い、
   または lock の job_id と不一致 → WARN(`-Fix` 時は `status: stale` に更新)。
5. **gitignore 整合**: `.gitignore` に `.agents/locks/*.lease.json` と
   `.agents/logs/codex/*.last.txt` の行があること。無ければ WARN。

**Verify**: クリーンな状態で `.\scripts\check.ps1` → 全項目 OK/WARN のみ、exit 0。
偽のロックファイル(存在しない PID)を置いて `-Fix` → 削除され、再実行で OK。

### Step 3: scripts/verify-job.ps1 を書く(判定のみ、修正はしない)

パラメータ: `[string] $JobId`(必須), `[string[]] $OwnedPaths = @()`,
`[string] $BaseRef = ''`(比較基点。省略時は working tree の `git status`/`git diff` を対象)。
判定項目(SKILL.md チェックリストの機械化可能部分):

1. **Status**: `.agents/logs/codex/{JobId}.last.txt` が存在し非空(Codex ジョブの場合)。
   Grok 直接実装の検証では `-SkipLog` スイッチで飛ばせるようにする。
2. **Diff scope**: `git diff --name-only`(+ `git status --porcelain` の未追跡分)を取り、
   `-OwnedPaths` 指定時は全変更ファイルがいずれかの owned path 配下であること。
   逸脱ファイルは列挙して FAIL。
3. **スタブ検出**: 変更ファイルの追加行に `NotImplementedError` / `TODO:` /
   `throw new Error('not implemented')` を検出したら WARN(FAIL ではない — 文脈判断は
   Operator に残す)。
4. **テスト弱体化(F07)**: 削除されたファイル名が `test|spec|Tests` にマッチ、または
   追加行に `Skip = $true` / `it.skip` / `describe.skip` / `@pytest.mark.skip` を検出
   したら FAIL(理由付きで `-AcceptTestChanges` スイッチによる明示上書きのみ許す)。
5. 出力: 項目ごとの PASS/WARN/FAIL 一覧と最終判定(`verify-job: PASS` / `FAIL`)。
   FAIL 時 exit 1。**このスクリプトはコミット・マージ・修正を一切行わない。**

**Verify**: 変更ゼロの working tree で `.\scripts\verify-job.ps1 -JobId smoke-001 -SkipLog`
→ PASS、exit 0。ダミーのテストファイル削除を staged にして実行 → FAIL、exit 1
(確認後 `git restore` で戻す)。

### Step 4: テストと文書更新

- `tests/check.Tests.ps1`: `$TestDrive` の LockDir に偽ステールロック/リースを置き、
  検出と `-Fix` の挙動を検証(4 ケース以上)。
- `tests/verify-job.Tests.ps1`: 一時 git リポジトリ(`git init` in `$TestDrive`)で
  scope 逸脱と test 削除検出を検証(3 ケース以上)。
- `.agents/skills/verify-job/SKILL.md` の Checklist 冒頭に 1 行追記:
  「機械化可能な項目は `scripts/verify-job.ps1 -JobId <id>` を先に実行し、その出力を
  この checklist の証跡とする」。
- `.agents/docs/DESIGN.md` の open questions から check.ps1 を除き、Isolation 表の下等に
  実装済みメカニズムとして 1 行追記。

**Verify**: `Invoke-Pester -Path tests -PassThru` → `FailedCount = 0`(Plan 001 分含む)

## Test plan

Step 4 の 2 ファイル。パターンは Plan 001 の `tests/lease-paths.Tests.ps1` に倣う
(`$TestDrive` 隔離、実 codex 呼び出しなし)。

## Done criteria

- [ ] `Invoke-Pester -Path tests -PassThru` → `FailedCount = 0`
- [ ] `.\scripts\check.ps1` がクリーン環境で exit 0
- [ ] `.\scripts\verify-job.ps1 -JobId x -SkipLog` が変更ゼロ tree で PASS
- [ ] delegate-codex.ps1 の diff が「pid 追加」と「if/else 簡約」の 2 点のみ
- [ ] `git status` で in-scope 外の変更が無い
- [ ] `plans/README.md` の status 更新

## STOP conditions

- delegate-codex.ps1 の 83–92 行 / 105–111 行が抜粋と一致しない(drift)。
- Plan 001 が未完了(`tests/` が無い、`-LockDir` が無い)→ 先に 001 を実行。
- verify-job.ps1 の判定に git 履歴の書き換えや自動修正が必要に見えてきた
  (設計逸脱 — F10。判定のみに戻すか報告)。
- ステール判定で「実行中の正当なジョブ」を誤検出するケースを 2 回作ってしまった。

## Maintenance notes

- ロック書式に `pid=` が入ったため、旧書式ロックが残る環境では check.ps1 が
  WARN を出し続ける(意図通り — 手動確認を促す)。
- 今後 delegate-codex.ps1 を変更する際は、ロック作成とステール判定(check.ps1)の
  両方を同時に見ること(書式は 2 箇所で共有される暗黙の契約)。
- レビュー重点: verify-job.ps1 が「判定のみ」に留まっているか(F10 予防)。
- 見送り: Acceptance checks コマンドの packet からの自動抽出・自動実行。コマンド
  インジェクション面の設計が必要なため、まず判定系を安定させてから別プランで扱う。
