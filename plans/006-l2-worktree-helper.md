# Plan 006: L2 worktree ヘルパー — 並列ジョブの隔離を機構化する

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 9c7c1e2..HEAD -- scripts/ tests/ .agents/rules/isolation.md`
> plan 005 による scripts/tests の変更は前提(依存)であり drift ではない。

## Status

- **Priority**: P1(v0.3 の中核)
- **Effort**: L
- **Risk**: HIGH(誤設計は F08/F10 — 二重書き込み・yolo マージ — の入口になる)
- **Depends on**: plans/005-deferred-hardening.md
- **Category**: direction / dx
- **Planned at**: commit `9c7c1e2`, 2026-07-21

## Why this matters

現状の L0 は安全だがスループットの天井: write ジョブは常に直列で、Codex の write ジョブ中は
Grok が同ツリーで作業できない(このドッグフーディング期間中にも Claude/Grok の
同一ツリー競合が 2 回実際に起きた)。L2(ジョブごとの git worktree)は DESIGN.md で
Phase 3 送りになっていた最後の隔離レイヤー。**設計原則: worktree は隔離を提供するが、
マージ判断は絶対に自動化しない**(F10)。collect は「レビュー可能なブランチと diff の提示」
までで止まる。

## 設計(この plan で固定する決定事項)

> **Design review**: Codex `plan-006-design` → REQUEST_CHANGES (P0 nits only).
> F10 auto-merge declined by design. Design section revised below before implement.

1. **ライフサイクル**: `new → (job 実行) → collect → cleanup` の 4 動作を
   `scripts/worktree-job.ps1 -Action <new|collect|cleanup> -JobId <id>` に実装する。
2. **new**: `git worktree add .agents/worktrees/<JobId> -b wt/<JobId> <base>`
   (base 既定 = 現在の HEAD を**コミット SHA へ解決**してから使用)。
   `.agents/worktrees/` は既に gitignored。
   **JobId** は安全な単一パス要素のみ許可(英数字・`-`・`_`、`.` / `..` / パス区切り拒否)。
   大小文字違いの既存 JobId や、cleanup 後にブランチ `wt/<JobId>` が残っている JobId の
   再利用は拒否する。
   作成した worktree の絶対パスと base SHA を **機械処理可能な単一行** stdout と
   `.agents/locks/<JobId>.worktree.json` に記録。スキーマ:
   `schema_version` (1), `job_id`, `path`, `branch`, `base_sha`, `status`
   (`active`|`collected`|`removed`|`stale`), `owned_paths` (string[]),
   `log_required` (bool; Codex `-Worktree` 既定 true、Grok 直接は `-SkipLog` 指定時 false),
   `created_at`, `updated_at` (ISO-8601)。
   worktree 作成と JSON 保存の部分失敗を検出して拒否/ロールバックする。
   `.gitignore` に `.agents/locks/*.worktree.json` を追加する(現行パターン
   `*.lease.json` はこれを覆わず、毎ジョブ untracked 汚染になるため)。
3. **ロック体系との関係**: worktree 内の write ジョブは**メインツリーの
   `write-job.lock` を取らない**(隔離はツリー分離で担保)。加えて **L1 も取得・解放しない**
   (`lease-paths.ps1` を呼ばない)。`OwnedPaths` は L2 メタデータへ保存し、collect 時の
   verify 範囲に使う(メインツリーの `*.lease.json` は作らない — check.ps1 が
   write-job.lock 無しの running リースを orphan と誤判定するため)。
   `<JobId>.worktree.json` を「L2 リース」として扱い、`check.ps1` のステール検出対象に
   加える(worktree ディレクトリ実在 + branch 存在 + `git worktree list` 登録一致で
   liveness 判定。不一致は WARN、`-Fix` で status=stale)。
   同一 JobId の worktree 二重作成は拒否。
4. **delegate 連携**: `delegate-codex.ps1` に `-Worktree` スイッチを追加。
   **制御元**はメインツリーの `RepoRoot`(ヘルパー・L2 メタデータ)、**実行先**は
   worktree 絶対パス(`codex exec -C`・ログ)。指定時は new を呼び、
   `codex exec -C <worktree-path>` で実行し、L0 ロック**および L1 リース**をスキップ
   (worktree 内 implement/fix のみ。read-only ジョブでの `-Worktree` は no-op + 警告)。
5. **collect**: **F10 恒久**: collect が変更してよいのは無視対象の L2 メタデータ
   (`*.worktree.json` の status 等)のみ。メインツリーの HEAD / index / 追跡ファイルを
   変更せず、checkout / reset / stash / commit / merge / rebase / cherry-pick / PR 操作を
   **一切行わない**。
   実行前に Git 登録情報・正規化パス・ブランチ・対象 worktree のシンボリック HEAD を
   照合し、不一致(未登録パス、別ブランチ、detached HEAD、登録先不一致)は拒否。
   worktree 内に未コミット変更が残っている場合も拒否。
   検証: `verify-job.ps1 -RepoRoot <worktree-path> -JobId <JobId> -BaseRef <base_sha>`
   (+ 保存済み `OwnedPaths`; `log_required=false` のときだけ `-SkipLog`)。
   PASS/FAIL と `git diff <base_sha>..wt/<JobId> --stat` を表示。
   出力の最後に Operator 向けの次アクション(`git merge --no-ff wt/<JobId>` または
   PR 作成)を**案内するのみ**。
6. **cleanup**: `git worktree remove` + `worktree.json` を status=removed に更新。
   dirty な worktree は `-Force` なしでは拒否。**ブランチ `wt/<JobId>` は削除しない**
   (マージ判断が終わるまで証跡として残す。削除は Operator の手動操作。`-Force` でも
   ブランチは残す)。
7. **isolation.md 更新**: L2 の節を「manual `codex exec -C`」から本スクリプト運用に書き換える。
   手動 `-C` は正式 L2 運用から外す(ヘルパー経由が正本)。

## Current state

- `.gitignore` に `.agents/worktrees/` あり(v0.1.0 から)。`.agents/worktrees/.gitkeep` 存在。
- `scripts/delegate-codex.ps1` — L0 ロック取得は `$isWrite` 分岐(83–92 行付近)。
  `-RepoRoot` パラメータで `-C` 先を変更可能(worktree 連携の土台に使える)。
- `scripts/check.ps1` — ロック/リースのステール検出を実装済み(plan 002)。
- `.agents/rules/isolation.md` — L2 は「optional later / manual」と記載。
- `scripts/verify-job.ps1` — `-BaseRef` で基点比較が可能(plan 002 + 005 で強化済み)。

## Scope

**In scope**: `scripts/worktree-job.ps1`(create), `scripts/delegate-codex.ps1`(`-Worktree` 追加),
`scripts/check.ps1`(L2 ステール検出追加), `.agents/rules/isolation.md`,
`.gitignore`(`*.worktree.json` の 1 行追加のみ),
`tests/worktree-job.Tests.ps1`(create), `plans/README.md` / 本ファイル(status)

**Out of scope**: 自動マージ・自動 PR 作成(F10 で恒久禁止)、`wt/*` ブランチの自動削除、
複数 worktree 間の依存管理、README への反映(動いてから別 docs PR)

## Steps

1. **設計レビュー(必須)**: 上の「設計」節を Codex `design` packet
   (`plan-006-design.prompt.txt`)にして read-only レビューを取る。指摘があれば
   本ファイルの設計節を改訂してから実装に入る(設計変更はコミットとして残す)。
2. `worktree-job.ps1` の new/cleanup を実装 + テスト(`$TestDrive` 内の一時 git リポジトリで
   add → 二重作成拒否 → dirty cleanup 拒否 → clean cleanup 成功)。
3. collect を実装 + テスト(コミット済み変更ありの worktree で verify 実行と diff 表示、
   未コミット変更ありで拒否、**マージが起きていないこと**をテストで断言:
   collect 後に main の HEAD が不変)。
4. `delegate-codex.ps1 -Worktree` 連携 + L0 スキップの分岐テスト
   (codex 実呼び出しなしで、ロックファイルが作られないことの確認まで)。
5. `check.ps1` に L2 ステール検出(worktree.json あり + ディレクトリ消失 → WARN、
   `-Fix` で status=stale)。
6. `isolation.md` 更新、Codex `review` packet、verify-job、status 更新。

**Verify**(全ステップ共通): `Invoke-Pester -Path tests -PassThru` → `FailedCount = 0`

## Done criteria

- [x] new/collect/cleanup が上記設計どおり動作(テスト 8 ケース以上 — worktree-job.Tests 9 + suite 57)
- [x] **collect 後に main の HEAD が変わらない**ことをテストが断言している
- [x] `-Worktree` write ジョブが `write-job.lock` を作らない
- [x] check.ps1 が L2 ステールを検出する(登録照合込み; `-Fix` → status=stale)
- [x] isolation.md が実運用と一致
- [x] Codex 設計レビュー + 実装後レビューの両 packet がログに存在
  (`plan-006-design` REQUEST_CHANGES→設計改訂; `plan-006-review` REQUEST_CHANGES→3 件 fix 済み)

## STOP conditions

- 設計レビューで Codex が「自動マージが必要」と主張した(却下して進めず、ユーザーへ:
  これは F10 の恒久制約であり交渉不可)
- `git worktree` の挙動が Windows パス(長パス・junction)で不安定
- delegate との統合で L0 スキップ条件が曖昧になった(隔離保証を口頭で補う設計になったら STOP)
- 同一失敗 2 回(サーキットブレーカー)

## Maintenance notes

- `wt/*` ブランチの棚卸し(マージ済み・放置)は将来の check.ps1 拡張候補
- plan 007(アダプタ)が go になった場合、`-Worktree` は runtime 非依存の共通機能として維持
- **Safe trade (post replan)**: `new` failure path never deletes branches; worktree remove only if this process completed `git worktree add`. A crashed partial `new` (`status=creating` + dir/branch) is **not** auto-cleared — `check.ps1` WARNs; Operator cleans manually. Aged empty `creating` claims (≥15m, no dir/branch) may be cleared with `-Fix`.
