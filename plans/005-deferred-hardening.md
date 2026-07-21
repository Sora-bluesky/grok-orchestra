# Plan 005: v0.2 の deferred 4 件をまとめて解消する(hardening)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 9c7c1e2..HEAD -- scripts/ tests/`
> 差分があれば "Current state" の記述と実コードを照合し、不一致は STOP。

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED(verify-job / lease-paths の入力経路を触る)
- **Depends on**: none(v0.2.0 リリース済み main が前提)
- **Category**: bug / security / tech-debt
- **Planned at**: commit `9c7c1e2`, 2026-07-21

## Why this matters

v0.2 のレビューで発見され `plans/README.md` の Follow-up/deferred に記録した 4 件を清算する。
うち 2 件(porcelain クォート・先頭スペースファイル名)は**同じ根本原因** — git のテキスト出力を
パースしていること — を持ち、`-z`(NUL 区切り・生パス)出力への切替で一括解決できる。
残り 2 件(スキャンサイズ上限・installer の symlink 自己 Target)は独立の小修正。

## Current state

- `scripts/verify-job.ps1` — 対象箇所:
  - `Get-ChangedPaths` / untracked 収集: `git status --porcelain -uall` のテキスト出力を行パース。
    非 ASCII ファイル名は `"tests/\303\251.Tests.js"` のように C-style クォートされ、
    クォート除去処理がパスを壊す(deferred P2)。先頭スペースのファイル名も
    Trim ベースの正規化で潰れる(deferred P1、path-normalize 側)。
  - untracked 本文スキャン(スタブ / F07 マーカー): ファイルサイズ無制限で全読み(deferred P2)。
- `scripts/lib/path-normalize.ps1` — `ConvertTo-NormalizedPath` 相当がセグメント分割正規化を行う。
  先頭/末尾スペースのセグメントは Trim で消える(README の既知の制限として文書化済み)。
- `scripts/install.ps1` — `Test-SamePath`(211–214 行付近)が**字面比較**のみ。
  リポジトリ root への junction/symlink を `-Target` に渡すと自己導入を見逃す(deferred P2)。
- `plans/README.md` — 「Follow-up / deferred」表に上記 4 行が記録されている。

## Commands you will need

| Purpose | Command | Expected |
|---------|---------|----------|
| 回帰テスト | `Invoke-Pester -Path tests -PassThru` | `FailedCount = 0` |
| 完了ゲート | `.\scripts\verify-job.ps1 -JobId plan-005 -SkipLog` | PASS |

## Scope

**In scope**: `scripts/verify-job.ps1`, `scripts/lib/path-normalize.ps1`(必要な範囲のみ),
`scripts/install.ps1`(Test-SamePath のみ), `tests/`(該当テスト追加),
`plans/README.md`(deferred 行の解消マーク), `plans/005-deferred-hardening.md`(status)

**Out of scope**: delegate-codex.ps1 / lease-paths.ps1 の挙動変更、worktree(plan 006)、
README 本文(既知の制限の記述解除は 1 行修正まで可)

## Steps

### Step 1: git 出力を `-z` ベースに切替(クォート + 先頭スペースを同時解決)

`verify-job.ps1` のパス収集を NUL 区切りに変更する:

- `git status --porcelain -z -uall`(レコード区切り NUL。rename は 2 フィールド)
- `git diff --name-only -z [...]` / `git diff --name-status -z [...]`

PowerShell 側は NUL(**`[char]0` を使う — `` `u{0} `` は PS 6+ 専用でこのリポジトリの
`#requires -Version 5.1` に反する**)で split する。
`& git ... | Out-String` は改行を足すので、配列 join → split の既存 Invoke-GitChecked を
`-z` 対応に拡張: NUL を含む生文字列を返す `-RawOutput` スイッチを足し、
呼び出し側で `$raw -split [char]0` する(5.1 / 7 両対応をテストで確認)。
これで git 側のクォートが発生せず、先頭スペースも保存される。
path-normalize は「セグメント内の前後スペースを保持する」よう Trim 対象を
セパレータ正規化のみに絞る(重複判定は OrdinalIgnoreCase 比較のまま)。

**Verify**: 一時 git リポジトリで `é.Tests.ps1` と `" spaced.txt"`(先頭スペース)を
作成し、verify-job の scope 判定・スキャンが両方を正しいパスで扱うテストが green。

### Step 2: untracked 本文スキャンにサイズ上限

1 MB 超の untracked ファイルは本文スキャンをスキップし、
`[WARN] scan: skipped <path> (size > 1MB)` を出力(判定は FAIL にしない)。

**Verify**: 2 MB のダミーファイルで WARN が出て PASS が維持されるテスト。

### Step 3: installer の自己 Target 判定を実パス比較に

`Test-SamePath` を `[System.IO.Path]::GetFullPath()` + 可能なら
`(Get-Item).ResolvedTarget`(PS7)/ `.Target` で解決した実パス同士の比較にする。
解決に失敗するパスは従来の字面比較にフォールバック。

**Verify**: `$TestDrive` 内に junction(`New-Item -ItemType Junction`)を作り、
junction 経由の自己 Target が拒否されるテスト。junction 作成不可の環境なら
そのテストは `-Skip` 可(理由をテスト内コメントで明記)。

### Step 4: 台帳の更新

- `plans/README.md` の Follow-up/deferred 4 行に `RESOLVED (plan 005, PR #NN)` を追記
- 注: 当該制限の記述は README には存在しない(plans/README.md・CHANGELOG・release body のみ)。
  CHANGELOG と release body は**歴史的記録なので遡及修正しない**。README の変更は不要。

**Verify**: `Invoke-Pester -Path tests -PassThru` → `FailedCount = 0`(既存 40 + 新規)

## Done criteria

- [ ] Pester 全 green(新規テスト 4 ケース以上を含む)
- [ ] 非 ASCII / 先頭スペースのファイル名が verify-job で正しいパスとして扱われる
- [ ] 1 MB 超 untracked で WARN スキップ
- [ ] junction 自己 Target が拒否される(または環境理由の明示 Skip)
- [ ] deferred 台帳 4 行が RESOLVED(README は対象記述なしのため変更不要)
- [ ] `git status` で in-scope 外の変更なし

## STOP conditions

- `-z` 化で既存テストが 2 回の修正で green に戻らない(パース設計を報告して相談)
- rename レコード(2 フィールド)の扱いが F07 rename 検出と両立しない
- PowerShell 5.1 で NUL 分割が安定しない(5.1 サポートを落とす判断はユーザー承認事項)

## Maintenance notes

- 以後 git 出力を読むコードは必ず `-z` を使う(テキストパースの再導入をレビューで弾く)
- サイズ上限 1 MB は定数化し、変更時はテストも更新
