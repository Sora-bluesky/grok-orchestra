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

1. **ライフサイクル**: `new → (job 実行) → collect → cleanup` の 4 動作を
   `scripts/worktree-job.ps1 -Action <new|collect|cleanup> -JobId <id>` に実装する。
2. **new**: `git worktree add .agents/worktrees/<JobId> -b wt/<JobId> <base>`
   (base 既定 = 現在の HEAD SHA)。`.agents/worktrees/` は既に gitignored。
   作成した worktree の絶対パスと base SHA を stdout と
   `.agents/locks/<JobId>.worktree.json`(job_id / path / branch / base_sha / status)に記録。
   `.gitignore` に `.agents/locks/*.worktree.json` を追加する(現行パターン
   `*.lease.json` はこれを覆わず、毎ジョブ untracked 汚染になるため)。
3. **ロック体系との関係**: worktree 内の write ジョブは**メインツリーの
   `write-job.lock` を取らない**(隔離はツリー分離で担保)。ただし
   `<JobId>.worktree.json` を「L2 リース」として扱い、`check.ps1` のステール検出対象に
   加える(worktree ディレクトリ実在 + branch 存在で liveness 判定)。
   同一 JobId の worktree 二重作成は拒否。
4. **delegate 連携**: `delegate-codex.ps1` に `-Worktree` スイッチを追加。
   指定時は new を呼び、`codex exec -C <worktree-path>` で実行し、
   L0 ロック取得をスキップする(worktree 内 implement/fix のみ。read-only ジョブでの
   `-Worktree` は no-op + 警告)。
5. **collect**: worktree 内で `verify-job.ps1 -JobId <JobId> -BaseRef <base_sha>` を実行し
   (ログ規約: delegate `-Worktree` 経由のジョブは **worktree 側**の
   `.agents/logs/codex/<JobId>.last.txt` に結果が書かれるので、collect の status:log 判定は
   worktree ルート基準で行う。Grok 直接編集の worktree では `-SkipLog`)、
   PASS/FAIL と `git diff <base_sha>..wt/<JobId> --stat` を表示。
   **マージ・rebase・cherry-pick は一切行わない。** 出力の最後に Operator 向けの
   次アクション(`git merge --no-ff wt/<JobId>` または PR 作成)を案内するのみ。
   worktree 内に未コミット変更が残っている場合は collect を拒否
   (ワーカーにコミットさせるか、Operator が判断)。
6. **cleanup**: `git worktree remove` + `worktree.json` を status=removed に更新。
   dirty な worktree は `-Force` なしでは拒否。**ブランチ `wt/<JobId>` は削除しない**
   (マージ判断が終わるまで証跡として残す。削除は Operator の手動操作)。
7. **isolation.md 更新**: L2 の節を「manual `codex exec -C`」から本スクリプト運用に書き換える。

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

- [ ] new/collect/cleanup が上記設計どおり動作(テスト 8 ケース以上)
- [ ] **collect 後に main の HEAD が変わらない**ことをテストが断言している
- [ ] `-Worktree` write ジョブが `write-job.lock` を作らない
- [ ] check.ps1 が L2 ステールを検出する
- [ ] isolation.md が実運用と一致
- [ ] Codex 設計レビュー + 実装後レビューの両 packet がログに存在

## STOP conditions

- 設計レビューで Codex が「自動マージが必要」と主張した(却下して進めず、ユーザーへ:
  これは F10 の恒久制約であり交渉不可)
- `git worktree` の挙動が Windows パス(長パス・junction)で不安定
- delegate との統合で L0 スキップ条件が曖昧になった(隔離保証を口頭で補う設計になったら STOP)
- 同一失敗 2 回(サーキットブレーカー)

## Maintenance notes

- `wt/*` ブランチの棚卸し(マージ済み・放置)は将来の check.ps1 拡張候補
- plan 007(アダプタ)が go になった場合、`-Worktree` は runtime 非依存の共通機能として維持
