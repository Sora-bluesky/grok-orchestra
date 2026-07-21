# Plan 003: install.ps1 で別プロジェクトへの導入をワンコマンドにする

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 8716814..HEAD -- .agents/skills/init/ scripts/ README.md README.ja.md`
> Plan 001/002 による `scripts/` への追加(tests, check.ps1, verify-job.ps1)は前提であり
> drift ではない。`init/SKILL.md` の手順内容が下の抜粋と食い違う場合は STOP。

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED(他人のプロジェクトツリーに書き込むスクリプト — 上書き事故が最悪ケース)
- **Depends on**: plans/001-ci-pester-baseline.md
- **Category**: dx / direction
- **Planned at**: commit `8716814`, 2026-07-21

## Why this matters

このハーネスの本来の用途は「自分のアプリのツリーに敷いて使う」ことだが、その導入手順は
`.agents/skills/init/SKILL.md` の散文(「Copy or submodule into the target app as needed…
Merge carefully…」)で、LLM か人間の慎重な手作業に全面依存している。導入摩擦が最初の
体験を決める。`install.ps1 -Target <path>` 一発で安全に敷けるようにすれば、試す
ユーザーの分母が変わる。

## Current state

- `.agents/skills/init/SKILL.md` — 導入手順の SSOT。「Steps — another project (advanced)」
  が定める内容(installer はこれの機械化であり、逸脱してはならない):
  - コピー対象: `.agents/`(rules, skills, docs 構造)、`scripts/delegate-codex.ps1`、
    `scripts/lease-paths.ps1`、ルート `AGENTS.md` パターン、必要なら `.codex/AGENTS.md` /
    `.grok/rules/`
  - Forbidden(SKILL.md 43–47 行): 既存 `AGENTS.md` やユーザー STATE の盲目上書き /
    smoke も verify も無しに copy=done 扱い / 本来 gitignored なライブセッションファイルの commit
  - ライブ状態はローカル限定: `.agents/STATE.md`(`STATE.example.md` から seed)、`PROGRESS.md`
- `.gitignore` — 導入先にも同等の除外が必要な行(1–27 行):
  `.env` 系 / `PROGRESS.md` / `.agents/STATE.md` / `HANDOFF.md` /
  `.agents/logs/codex/*.{last.txt,stderr.log,combined.log,jsonl}` / `.agents/worktrees/` /
  `.agents/locks/{write-job.lock,*.lease.json,leases.json}` + `.gitkeep` の否定パターン
- `.agents/docs/packets/smoke-001.prompt.txt` — smoke packet の雛形(必須 5 見出しを持つ)。
  導入先ではパス言及を対象アプリ用に書き換える必要がある(SKILL.md Step 4:
  「do not assume grok-orchestra fixtures exist」)。
- コピーしてはいけないもの: `.agents/STATE.md`(存在すれば — gitignored なので通常無い)、
  `.agents/logs/` `.agents/locks/` の中身(`.gitkeep` 以外)、`plans/`、`release/`、
  `fixtures/`、`.git/`。

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| 回帰テスト | `Invoke-Pester -Path tests -PassThru` | `FailedCount = 0` |
| 手動 E2E | `.\scripts\install.ps1 -Target <一時ディレクトリ>` | exit 0、下記レイアウト生成 |

## Scope

**In scope**:
- `scripts/install.ps1`(create)
- `tests/install.Tests.ps1`(create)
- `README.md` / `README.ja.md`(Quick start に installer 節を追記 — 既存節の書き換えはしない)
- `.agents/skills/init/SKILL.md`(「another project」節の冒頭に installer 参照を 1 行追記)

**Out of scope**:
- `irm | iex` のリモートワンライナー配布(署名・供給網の設計が必要 — 将来プラン)
- 導入先の既存 `AGENTS.md` の自動マージ(提案ファイル生成まで。マージ判断は人間/LLM)
- git submodule 方式の自動化(コピー方式のみ)

## Git workflow

- Branch: `feat/003-one-command-installer`
- push / PR 作成はユーザー確認後

## Steps

### Step 1: scripts/install.ps1 を書く

パラメータ: `[string] $Target`(必須。存在するディレクトリであること)、
`[switch] $Force`(既存ファイル上書きの唯一の経路)、`[switch] $DryRun`(書き込まず計画のみ列挙)。

動作(init/SKILL.md の機械化。**既定では既存ファイルを一切上書きしない**):

1. 検証: `$Target` が存在し、このリポジトリ自身(`$PSScriptRoot\..`)と同一パスでないこと。
2. コピー(コピー元はこのリポジトリのツリー):
   - `.agents/` 一式。ただし `STATE.md` と、`logs/` `locks/` 配下の `.gitkeep` 以外は除外
   - `scripts/delegate-codex.ps1`, `scripts/lease-paths.ps1`, `scripts/check.ps1`,
     `scripts/verify-job.ps1`(存在するもののみ)
   - `.codex/AGENTS.md`, `.grok/rules/`
3. `AGENTS.md`: 導入先に無ければコピー。**在れば `AGENTS.grok-orchestra.md` として置き**、
   「既存 AGENTS.md と手動マージせよ(優先順位は init skill 参照)」と stdout で明示。
4. `.gitignore`: 無ければ本リポジトリの Orchestra 関連ブロック(上記 Current state 参照)を
   マーカーコメント付きで生成。在れば同ブロックが未含有の場合のみ**末尾追記**(重複追記しない)。
5. smoke packet: `.agents/docs/packets/smoke-001.prompt.txt` を導入先に生成し、
   `## Relevant files` / `## Acceptance checks` 内の grok-orchestra 固有パス
   (`fixtures/` 等)を「導入先で書き換えよ」と TODO マーカー付きに置換する。
6. `STATE.example.md` はコピーするが `STATE.md` の seed は行わない(stdout で
   `Copy-Item .agents\STATE.example.md .agents\STATE.md` を案内)。
7. 終了時に次アクション(smoke 実行コマンド、check.ps1 があればその実行)を stdout に列挙。
8. すべての skip(既存のため未上書き)を 1 件ずつ stdout に報告する。無音スキップ禁止。

**Verify**: `New-Item -ItemType Directory (Join-Path $env:TEMP 'go-install-test')` した空ディレクトリへ
`-DryRun` → 書き込みゼロで計画列挙。実行 → レイアウト生成、exit 0。

### Step 2: 冪等性と非破壊の確認

同じ Target へ 2 回目の実行 → 全ファイル skip 報告、既存ファイルのタイムスタンプ不変。
導入先に独自 `AGENTS.md`(1 行のダミー)を置いて実行 → 内容不変のまま
`AGENTS.grok-orchestra.md` が生成される。

**Verify**: 上記 2 ケースを手動確認(Step 3 でテスト化)

### Step 3: tests/install.Tests.ps1 を書く

`$TestDrive` を Target にして最低 6 ケース:
空ディレクトリへの導入 / 2 回目の冪等性 / 既存 AGENTS.md 非破壊 /
既存 .gitignore への追記(1 回だけ) / `-DryRun` が書き込みゼロ /
Target がリポジトリ自身のとき拒否。

**Verify**: `Invoke-Pester -Path tests -PassThru` → `FailedCount = 0`

### Step 4: README 2 言語 + init skill に導線を追記

README の Quick start 直後に「Install into your own project」節(コマンド 1 行+
生成物 3 行程度)。README.ja.md にも同等。`init/SKILL.md` の advanced 節冒頭に
「まず `scripts/install.ps1 -Target <path>` を実行し、本節は生成結果の検証と
マージ判断に使う」と 1 行。

**Verify**: `git diff README.md` が追記のみ(既存行の削除ゼロ)であること

## Test plan

Step 3 の 6 ケース。パターンは `tests/lease-paths.Tests.ps1`(Plan 001)に倣う。

## Done criteria

- [ ] `Invoke-Pester -Path tests -PassThru` → `FailedCount = 0`
- [ ] 空ディレクトリへの実行で init/SKILL.md 記載のレイアウトが揃う
- [ ] 既存ファイルは `-Force` 無しでは 1 バイトも変わらない(2 回実行で確認)
- [ ] `git status` で in-scope 外の変更が無い
- [ ] `plans/README.md` の status 更新

## STOP conditions

- init/SKILL.md の手順・Forbidden が Current state の抜粋と一致しない(drift)。
- 「既存ファイルを上書きしないと成立しない」ケースに遭遇した(設計相談に戻す)。
- .gitignore 追記の重複判定が 2 回の修正で安定しない。
- Plan 001 未完了(tests/ が無い)。

## Maintenance notes

- コピー対象リストは install.ps1 内にハードコードされる。**新しいスキルやスクリプトを
  リポジトリに足したら install.ps1 のリストも更新する**こと(レビュー時の確認点)。
  リスト漏れ検出テスト(リポジトリの実ファイル一覧との突合)は follow-up 候補。
- リモート配布(`irm | iex`)を将来やる場合、このスクリプトを「ローカル実行の中核」として
  ラップする設計にする(ロジックの二重化をしない)。
