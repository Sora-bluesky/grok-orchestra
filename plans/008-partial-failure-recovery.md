# Plan 008: Invoke-New / Invoke-Cleanup の partial-failure リカバリを一括再設計する

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat <merge-commit-of-PR#18>..HEAD -- scripts/worktree-job.ps1 scripts/check.ps1`

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED(L2 の cleanup/new に触れる。F10 ガードには触れない)
- **Depends on**: plans/006-l2-worktree-helper.md(マージ済み)
- **Category**: bug / tech-debt
- **Planned at**: commit `<fill: PR #18 merge SHA>`, 2026-07-23

## Why this matters

plan 006 の Operator 検証中、`Invoke-New` / `Invoke-Cleanup` の **partial-failure リカバリ**が
同一クラスの欠陥を3回連続で出した(concurrency clobber → locked-registration の cleanup
gap → `git worktree add` がフック失敗で作成後に throw)。1ラウンドごとに1経路を塞ぐと別経路が
出る典型で、circuit breaker が「piecemeal に叩かず設計し直せ」と示す状況。plan 006 は
F10・隔離・atomic claim・非破壊 rollback を全て堅牢化してマージしたが、この partial-failure
クラスだけは**一括で再設計**するのが正しい。すべて **非 F10・L2 限定・狭いトリガー**で、
plan 006 マージをブロックしないと判断して defer した(PR #18、ユーザー裁定)。

## 対象欠陥(deferred から統合)

1. **locked cleanup catch path**(PR #18 bot 3633904712): `Invoke-Cleanup` の -Force fallback
   catch(locked live worktree で `remove --force` が失敗 → Remove-Item + prune)には、
   dir-gone else 分岐が fix #7 で得た post-prune 登録再確認が無い。locked registration が
   残ったまま status=removed になりうる。
2. **worktree add fails-after-create**(PR #18 bot 3637721290): `git worktree add` が
   dir+branch+registration を作った後に失敗(例: 非ゼロ `post-checkout` フック)すると、
   `$createdWorktree` は `Get-Git` 戻り後にしか true にならないため、catch が claim metadata を
   解放するのに orphan worktree+branch を残す(doctor 不可視・JobId ブロック)。
   `worktree-job.ps1:411-412` 付近。

いずれも**現行 helper が自力では作らない状態**(手動 lock / 失敗するフック)が前提の
防御的エッジ。

## 設計方針(この plan で確定させる)

**共通原則: git 操作が失敗したら「何が実際に作られたか」を実測で再プローブしてから
リカバリする**(戻り値の boolean フラグに頼らない)。

1. **new の add 失敗後**: `Get-Git worktree add` が throw したら、canonical path の存在と
   `git worktree list --porcelain` 登録・`show-ref wt/<Id>` を再プローブする。実際に
   作られていたら(a)claim を `status=creating` のまま保持して doctor が回収できるようにするか、
   (b)この呼び出しが作った worktree+branch を明示クリーンアップしてから claim を解放する。
   **どちらかに決めてテストで固定**(推奨: 保持 + doctor 回収。破壊を減らす)。
2. **cleanup の両経路統一**: post-prune 登録再確認を **else 分岐と -Force catch 分岐で共通化**
   (ヘルパー関数に切り出す)。locked で登録が残るなら status=removed を書かず throw + unlock 案内。
3. **check.ps1**: `status=creating` の age-gate 回収(既存)が、new の add 失敗で残った
   partial(dir/branch あり)を安全に WARN 報告することを確認・テスト追加。

## Scope

**In scope**: `scripts/worktree-job.ps1`(Invoke-New 失敗経路 / Invoke-Cleanup 両経路の再確認統一),
`scripts/check.ps1`(partial creating claim の報告), `tests/worktree-job.Tests.ps1`,
`plans/README.md` / 本ファイル(status)

**Out of scope**: F10 ガード(Assert-MetaCanonicalFields / Test-IsCanonicalL2Path /
createdWorktree ゲート / no-branch-D)の挙動変更、atomic claim・collect status ordering・
base_sha 検証・delegate parse(すべて検証済み)、install.ps1 の gitignore upgrade(別 deferred)

## Steps(概略 — 実装者は設計方針を Codex design packet でレビューしてから着手)

1. Codex `design` packet で上記「設計方針」をレビュー(F10 非交渉を明記)。
2. 登録再確認をヘルパー関数化し、Invoke-Cleanup の両経路で使用 + テスト(locked を両経路で再現)。
3. Invoke-New の add 失敗後の再プローブ + reconcile を実装 + テスト
   (非ゼロ `post-checkout` フックで add-after-create を再現)。
4. check.ps1 の partial creating 報告を確認・テスト。
5. Codex `review` packet → verify-job → status 更新。

**Verify**: `Invoke-Pester -Path tests -PassThru` → `FailedCount = 0`(pinned Pester 5.7.1、
pwsh 7 と Windows PowerShell 5.1 の両方)

## Done criteria

- [ ] locked worktree が cleanup の**両経路**で status=removed を回避し unlock 案内で throw
- [ ] `git worktree add` の作成後失敗(post-checkout 非ゼロ)で orphan が残らない
      (claim 保持で doctor 回収可、またはクリーンアップ)
- [ ] check.ps1 が partial creating claim を安全に報告
- [ ] Pester 両シェル green、F10 ガード diff なし
- [ ] plans/README.md の PR #18 deferred 2 行を RESOLVED(plan 008)に更新

## STOP conditions

- 設計レビューで F10 ガードの緩和が必要に見えた(却下・報告)
- 同一 partial-failure クラスの修正が 2 回失敗(circuit breaker — 設計を再検討)

## Maintenance notes

- 以後 git 操作の失敗リカバリは「戻り値フラグでなく実測再プローブ」を規範とする。
- plan 006 の検証で「green テスト + 単一レビュー」を通り抜けた欠陥を多視点敵対的検証が
  捕捉した経緯は再現性が高い。008 実装後も同様に fix 前後で敵対的再検証をかけること。
