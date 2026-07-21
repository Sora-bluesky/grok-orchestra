# Plan 004: エンドツーエンド walkthrough(実トランスクリプト付き)を公開する

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 8716814..HEAD -- docs/ README.md README.ja.md fixtures/ .agents/docs/packets/`
> Plan 001–003 による追加は前提であり drift ではない。README の Quick start /
> Smoke test 節が下の想定と大きく変わっていたら STOP。

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW(ドキュメントとログ採取のみ。製品コード変更なし)
- **Depends on**: plans/002-mechanize-verify-and-doctor.md
- **Category**: docs / direction
- **Planned at**: commit `8716814`, 2026-07-21

## Why this matters

現状、リポジトリには「動いている姿」が存在しない。fixtures は `sample.txt` 1 個、
packet は smoke 1 個で、README は思想の説明に留まる。OSS の採用判断は「実際に動く
ところを 3 分で見られるか」で決まる。packet 作成 → delegate → レビュー結果 →
verify-job までの 1 サイクルを、**実際に採取した出力**付きで `docs/walkthrough.md` に
まとめ、README から誘導する。

## Current state

- `README.md` — Quick start(clone → `grok`)と Smoke test 節あり:
  ```powershell
  .\scripts\delegate-codex.ps1 -JobId smoke-001 -Type review -PromptFile .agents\docs\packets\smoke-001.prompt.txt
  ```
  期待結果は「非空の `.agents/logs/codex/smoke-001.last.txt`(gitignored)」。
- `fixtures/sample.txt` — smoke レビュー用ダミー。
- `.agents/docs/packets/smoke-001.prompt.txt` — 必須 5 見出し
  (`## Objective / ## Constraints / ## Relevant files / ## Acceptance checks / ## Output format`)
  を持つ唯一の packet 実例。
- `docs/` — `architecture.md` のみ。walkthrough は存在しない。
- Plan 002 適用後は `scripts/check.ps1` と `scripts/verify-job.ps1` が存在する(実行例に含める)。
- ログは gitignored(`.gitignore`: `.agents/logs/codex/*.last.txt` 等)なので、
  walkthrough には**抜粋を本文に貼り込む**(ログファイル自体はコミットしない)。

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| 前提確認 | `.\scripts\check.ps1` | exit 0 |
| smoke 実行 | README 記載の delegate コマンド(上記) | exit 0、非空 `.last.txt` |
| verify | `.\scripts\verify-job.ps1 -JobId walkthrough-001 -SkipLog` 等 | PASS |

## Scope

**In scope**:
- `docs/walkthrough.md`(create)
- `docs/walkthrough.ja.md`(create — 日本語版。リポジトリの README 英日併記慣行に合わせる)
- `.agents/docs/packets/walkthrough-001.prompt.txt`(create — fixtures/sample.txt への
  review packet。smoke-001 を雛形に、Objective を「walkthrough 用の実例」に変える)
- `README.md` / `README.ja.md`(Smoke test 節の直後に walkthrough への 2 行リンク追記)
- `plans/README.md`(本プランの status 行のみ)
- `plans/004-walkthrough-demo.md`(Done criteria チェック反映のみ)

**Out of scope**:
- `fixtures/` の拡張(サンプルアプリ追加は不要 — 既存 sample.txt で成立させる)
- スクリーンキャスト・GIF(テキストトランスクリプトのみ)
- `.agents/logs/` 配下のコミット(gitignore を変えない)

## Git workflow

- Branch: `docs/004-walkthrough-demo`
- push / PR 作成はユーザー確認後

## Steps

### Step 1: walkthrough packet を作り、実際に 1 サイクル回す

`walkthrough-001.prompt.txt` を smoke-001 雛形から作成(必須 5 見出し維持)。
`.\scripts\delegate-codex.ps1 -JobId walkthrough-001 -Type review -PromptFile .agents\docs\packets\walkthrough-001.prompt.txt`
を実行し、`.agents/logs/codex/walkthrough-001.last.txt` の実出力を得る。
続けて `.\scripts\check.ps1` と verify-job(スクリプトまたはスキルの checklist)を実行し、
それぞれの実出力を控える。

**Verify**: delegate が exit 0、`.last.txt` 非空

### Step 2: docs/walkthrough.md を書く

構成(コードブロックはすべて Step 1 の**実出力の抜粋**。捏造禁止。長い出力は
`(...snip...)` で要約し、その旨明記):

1. 前提(check.ps1 の実行結果)
2. packet の書き方(walkthrough-001 全文と、5 見出しがゲートで強制される説明 —
   欠落時に delegate が拒否する実エラーメッセージも 1 例載せる)
3. delegate 実行と結果の読み方(`.last.txt` 抜粋)
4. verify-job(実行結果と、これが「done の定義」である説明)
5. 次の一歩(install.ps1 で自分のプロジェクトへ — Plan 003 の成果物へのリンク)

**Verify**: 本文中の全コマンドをコピペ再実行して全て成功すること(再現性チェック)

### Step 3: 日本語版と README 導線

`walkthrough.ja.md` は翻訳(トランスクリプト抜粋は共通で可)。両 README の Smoke test 節
直後に「See the full cycle: docs/walkthrough.md」相当の 2 行を追記。

**Verify**: `git diff README.md README.ja.md` が追記のみであること

## Test plan

自動テスト対象なし(ドキュメント)。再現性チェック(Step 2 の Verify)が実質のテスト。

## Done criteria

- [ ] `docs/walkthrough.md` / `docs/walkthrough.ja.md` が存在し、本文中の全コマンドが
      クリーン環境で再現可能
- [ ] トランスクリプト抜粋がすべて実採取(Step 1 のログと突合できる)
- [ ] `git status` に `.agents/logs/` 配下のファイルが現れない(gitignore 維持)
- [ ] README 両言語に導線あり、既存行の削除ゼロ
- [ ] `plans/README.md` の status 更新

## STOP conditions

- Codex CLI が未ログイン/利用不可で実トランスクリプトが採取できない
  (**捏造した出力で埋めない** — 報告して環境を整えてもらう)。
- Plan 002 が未完了で check.ps1 / verify-job.ps1 が無い(walkthrough の構成が
  変わるため、依存を先に完了させるか、スキル checklist ベースに縮退して良いか
  ユーザーに確認)。
- delegate 実行が 2 回連続で失敗する。

## Maintenance notes

- スクリプトの出力形式を変えるプランは walkthrough の抜粋を陳腐化させる。
  以後 `scripts/` 変更時は walkthrough の再現性チェックを verify 項目に足すこと。
- 抜粋に環境固有情報(ユーザー名入りの絶対パス等)が写り込んでいないか、
  コミット前に必ず確認する(レビュー重点)。
