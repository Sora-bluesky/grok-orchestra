# Plan 007: ワーカーアダプタ層の設計 spike(実装しない・go/no-go を出す)

> **Executor instructions**: This is a READ-ONLY design spike. The only
> deliverables are documents and packets — **no product code changes**.
> If you find yourself editing `scripts/`, you have left the plan's scope: STOP.
>
> **Drift check (run first)**: `git diff --stat 9c7c1e2..HEAD -- docs/ .agents/`
> plan 005/006 による変更は前提であり drift ではない。

## Status

- **Priority**: P2
- **Effort**: M(調査 + 文書のみ)
- **Risk**: LOW(コード変更なし)
- **Depends on**: none(005/006 と並行可能だが、直列運用なら最後)
- **Category**: direction
- **Planned at**: commit `9c7c1e2`, 2026-07-21

## Why this matters

v0.2 監査で「Codex 固定の bridge を runtime アダプタ化すれば対象ユーザーが
CLI の組み合わせの数だけ増える」と提案されたが、各 CLI の sandbox 意味論の差異吸収が
本体で工数 L、コア価値の希釈リスクもあるため v0.2 では却下された
(`plans/README.md` Findings considered and rejected 参照)。この spike は
**実装せずに** 差異を実測調査し、go/no-go の判断材料を作る。

## 調査項目(成果物 `docs/adapter-design.md` の必須セクション)

1. **候補 runtime の headless 実行と sandbox 対応表**(実測。ドキュメント引用には
   一次情報 URL を付ける):
   - Codex CLI: `codex exec -s read-only|workspace-write`(現行 — 基準)
   - Claude Code CLI: `claude -p` + permission mode / allowed-tools の read-only 相当は何か
   - Gemini CLI(または agy): headless 実行でワークスペース書き込みを禁止できるか
   - 各 runtime: stdin プロンプト受付 / 最終メッセージのファイル出力 or stdout 分離 /
     exit code 意味論 / `-C` 相当の cwd 指定
2. **アダプタ契約案**: `delegate-worker.ps1 -Runtime <name>` が要求する 5 操作
   (resolve invocation / map sandbox / pass prompt / capture result / classify exit)を
   PowerShell インターフェースとして定義。既存 `delegate-codex.ps1` がその
   Codex 実装に自然に載るかを検証。
3. **保証が破れる点の列挙**: read-only を**強制できない** runtime があるか
   (プロンプト指示だけの "read-only" は F14 ロール演劇であり不合格)。
   不合格 runtime の扱い(サポート外と明記 or 制限付きサポート)。
4. **go/no-go 推奨**: go の場合は対象 runtime を最大 2 つに絞った v0.4 実装スコープ案、
   no-go の場合は却下理由の追記文面(plans/README.md 用)。

## Current state

- `scripts/delegate-codex.ps1` — `Resolve-CodexNodeInvocation` / sandbox マッピング /
  ログ規約(`.agents/logs/codex/<id>.{last,stderr,combined}`)がアダプタ化対象の全機能。
- `AGENTS.md` は「Tool-neutral operating contract」を自認しているが、実装は Codex 固定。

## Scope

**In scope**: `docs/adapter-design.md`(create),
`.agents/docs/packets/plan-007-*.prompt.txt`(調査・レビュー用 packet),
`plans/README.md` / 本ファイル(status・go/no-go 結果の記録)

**Out of scope**: `scripts/` への一切の変更、新 runtime の実インストール以外の環境変更、
README への反映

## Steps

1. 調査項目 1 を実測(ローカルに存在する CLI: codex / claude / grok / agy(gemini)。
   未インストールの runtime は公式ドキュメント調査に切り替え、その旨を明記)。
   sandbox 実測は**安全な使い捨てディレクトリ**で行い、書き込み禁止が実際に
   強制されるかをファイル作成の成否で確認する。
2. `docs/adapter-design.md` を執筆(上記 4 セクション)。
3. Codex `design` packet で独立レビューを取り、指摘を反映。
4. go/no-go を `plans/README.md` に 1 行で記録し、ユーザーへ報告(v0.4 スコープの
   最終判断はユーザー)。

## Done criteria

- [x] `docs/adapter-design.md` が 4 必須セクションを持ち、対応表が実測ベース
      (実測できなかった項目は「未実測・文書ベース」と明記)
- [x] read-only を強制できない runtime が明確に不合格扱いされている
- [x] Codex レビュー packet 済み
- [x] `git diff --stat` に `scripts/` が現れない
- [x] go/no-go とその根拠が plans/README.md に記録されている

## Spike result (2026-07-23)

- **CONDITIONAL GO** — v0.4 candidate: `codex` + `claude` (Claude RO candidate until acceptance). Grok LIMITED, agy FAIL.
- Design packet: `.agents/docs/packets/plan-007-design.prompt.txt` → `.agents/logs/codex/plan-007-design.last.txt`
- Review packet: `.agents/docs/packets/plan-007-review.prompt.txt` → `.agents/logs/codex/plan-007-review.last.txt`
- Empirical: `.agents/docs/packets/plan-007-empirical.md`
- Deliverable: `docs/adapter-design.md` (P1 review findings folded in)

## STOP conditions

- 調査の過程で製品コードの変更が「必要」に見えてきた(spike の範囲逸脱 — 記録して STOP)
- 危険な sandbox 実測(danger 系フラグの使用)が必要になった(使用禁止 — 文書調査に切替)

## Maintenance notes

- go の場合、plan 008(実装)は本 spike の文書を Current state として書けるはず
- CLI のバージョンを対応表に必ず記録する(意味論はバージョンで変わる)
