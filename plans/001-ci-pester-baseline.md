# Plan 001: Pester テストと GitHub Actions CI で検証ベースラインを確立する

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 8716814..HEAD -- scripts/ .github/ tests/`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S–M
- **Risk**: LOW
- **Depends on**: none
- **Category**: tests / dx
- **Planned at**: commit `8716814`, 2026-07-21

## Why this matters

grok-orchestra は「検証ゲート(verify-job)を通らない完了は偽の完了」を中核思想とする
ハーネスだが、ハーネス自身に自動テストも CI も存在しない(CHANGELOG.md の Validation 節は
手動確認の記録のみ、`.github/` ディレクトリ自体が無い)。lease の重複判定や Prompt Contract
ゲートはロジックが壊れても誰も気づけない。このプランで最小の回帰テストと CI を敷き、
以降のプラン(002/003)の変更を安全にする。

## Current state

- `scripts/lease-paths.ps1` — L1 パスリース管理。テスト対象の中核ロジック:
  - `ConvertTo-OwnedPath`(17–26 行): repo 相対パスへの正規化。絶対パスと `..` 脱出を throw で拒否。
  - `Test-PathOverlap`(28–33 行): 完全一致またはセパレータ境界の接頭辞一致で重複判定。
  - ロックディレクトリはスクリプト位置から固定導出(13–14 行):
    ```powershell
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $lockDir = Join-Path $repoRoot '.agents\locks'
    ```
    → テストから隔離できないため、Step 1 で `-LockDir` パラメータを追加する。
- `scripts/delegate-codex.ps1` — Codex 委譲ラッパー。テスト対象:
  - `Test-PromptContract`(42–50 行): 必須 5 見出し
    `'## Objective', '## Constraints', '## Relevant files', '## Acceptance checks', '## Output format'`
    の欠落を検査。欠落時は `codex exec` に到達する**前に** `Write-Error` で停止(70–73 行)。
    → codex CLI 未インストール環境でも「不完全 packet が拒否されること」は安全にテスト可能。
- テストディレクトリ・CI 設定: 存在しない(新規作成)。
- 想定シェル: PowerShell 5.1+(スクリプト先頭 `#requires -Version 5.1`)。CI は pwsh 7 で実行。
- コミットメッセージ規約(git log より): 英語、`docs: ...` / `chore(release): ...` 形式。

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Pester 導入(ローカル初回のみ) | `Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser -Force` | exit 0 |
| テスト実行 | `Invoke-Pester -Path tests -Output Detailed` | 全テスト Pass、exit 0 |
| 静的解析(任意) | `Invoke-ScriptAnalyzer -Path scripts -Recurse` | Error レベル 0 件 |

## Scope

**In scope** (the only files you should modify):
- `scripts/lease-paths.ps1`(`-LockDir` パラメータ追加のみ)
- `tests/lease-paths.Tests.ps1`(create)
- `tests/delegate-codex.Tests.ps1`(create)
- `.github/workflows/ci.yml`(create)

**Out of scope** (do NOT touch, even though they look related):
- `scripts/delegate-codex.ps1` の動作変更(105–111 行の冗長 if/else 含む — Plan 002 で扱う)
- `.agents/` 配下のドキュメント・スキル
- codex CLI の実呼び出しを伴うテスト(CI に認証情報を持ち込まない)

## Git workflow

- Branch: `feat/001-ci-pester-baseline`
- コミットは Step 単位、メッセージは英語(例: `test: add Pester coverage for lease overlap logic`)
- push / PR 作成はユーザー確認後(main は PR 必須運用)

## Steps

### Step 1: lease-paths.ps1 に -LockDir パラメータを追加する

param ブロックに `[string] $LockDir = ''` を追加し、13–15 行を次の形に変更する:

```powershell
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($LockDir)) { $LockDir = Join-Path $repoRoot '.agents\locks' }
$lockDir = $LockDir
New-Item -ItemType Directory -Force -Path $lockDir | Out-Null
```

既定動作(引数省略時)は完全に従来通りであること。

**Verify**: `.\scripts\lease-paths.ps1 -Action check -OwnedPaths src` → `lease check: free`、exit 0

### Step 2: tests/lease-paths.Tests.ps1 を書く

Pester 5 形式。各テストで `-LockDir (Join-Path $TestDrive 'locks')` を渡し、リポジトリの
`.agents/locks` を汚さない。最低限のケース:

1. acquire → `{job}.lease.json` が生成され `status: running`
2. 同一パスの二重 acquire → throw(メッセージに `lease overlap` を含む)
3. 接頭辞重複(`src` 取得中に `src/lib` を check)→ exit 1
4. 境界非重複(`src` 取得中に `src2` を check)→ exit 0(`src2`.StartsWith(`src/`) は偽)
5. release → `status: released` になり、以後同パスの acquire が成功する
6. 絶対パス指定 → throw(`must be repo-relative`)
7. `../escape` 指定 → throw(`must stay inside the repository`)

**Verify**: `Invoke-Pester -Path tests/lease-paths.Tests.ps1 -Output Detailed` → 7 件以上 Pass

### Step 3: tests/delegate-codex.Tests.ps1 を書く

codex を実行しない範囲のみテストする:

1. 必須見出しが 1 つ欠けた prompt ファイル → エラーで停止し、メッセージに
   `Prompt Contract incomplete` と欠落見出し名を含む
2. 存在しない PromptFile → エラーで停止(`Prompt file not found`)
3. 完全な packet(`.agents/docs/packets/smoke-001.prompt.txt` をコピーして使用)は
   Contract 検査を通過する — codex 実呼び出しに入る手前までで検証したいが、
   スクリプトは検査通過後に実行へ進む構造のため、このケースは
   `Test-PromptContract` 相当の検査を「欠落ゼロ」で通ることの間接確認
   (エラーメッセージが Contract 起因でないこと)に留めてよい。困難なら
   ケース 1–2 のみで完了とし、その旨を plans/README.md に記録する。

**Verify**: `Invoke-Pester -Path tests/delegate-codex.Tests.ps1 -Output Detailed` → 全 Pass

### Step 4: .github/workflows/ci.yml を書く

```yaml
name: ci
on:
  push:
    branches: [main]
  pull_request:
jobs:
  test:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install Pester
        shell: pwsh
        run: Install-Module Pester -MinimumVersion 5.5 -Force -SkipPublisherCheck
      - name: Run tests
        shell: pwsh
        run: |
          $r = Invoke-Pester -Path tests -PassThru -Output Detailed
          if ($r.FailedCount -gt 0) { exit 1 }
```

**Verify**: ローカルで `Invoke-Pester -Path tests -PassThru` の `FailedCount` が 0。
(Actions 上の実走確認は PR 作成後 — push 前にユーザー確認が必要な点に注意)

## Test plan

Step 2–3 がテストそのもの。構造は Pester 5 の `Describe/It` + `$TestDrive` を使い、
新規作成のためリポジトリ内に倣う既存パターンは無い(このファイル群が以後の模範になる)。

## Done criteria

- [ ] `Invoke-Pester -Path tests -PassThru` → `FailedCount = 0`、合計 9 件以上
- [ ] `.\scripts\lease-paths.ps1 -Action check -OwnedPaths src` が従来通り動く(既定 LockDir)
- [ ] `git status` で in-scope 外の変更が無い
- [ ] リポジトリの `.agents/locks/` にテスト残骸(`*.lease.json`)が無い
- [ ] `plans/README.md` の status 更新

## STOP conditions

- "Current state" の抜粋と実コードが一致しない(drift)。
- Step 1 の後、引数省略時の挙動が変わってしまい 2 回の修正で直らない。
- Pester 5 がインストールできない環境である(Pester 3.x しか無い等)→ 報告して指示を仰ぐ。
- テストが codex CLI の実行を要求してしまう構造になった(設計が誤り — 報告)。

## Maintenance notes

- 以後 `scripts/` を変更するプラン(002/003)は必ずこのテストを回してから DONE 宣言する。
- レビューでは Step 1 の後方互換(既定 LockDir が従来と同一パスか)を重点確認。
- PSScriptAnalyzer の CI 組み込みは意図的に見送り(ノイズ調整が必要)。必要になったら別プラン。
