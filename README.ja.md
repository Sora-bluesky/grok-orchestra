# grok-orchestra

[English](README.md) | [日本語](README.ja.md)

**Grok = オペレーター · Codex CLI = 専門ワーカー**

現行リリース: **[v0.1.0](https://github.com/Sora-bluesky/grok-orchestra/releases/tag/v0.1.0)** · [Changelog](CHANGELOG.md)

マルチエージェント開発ハーネスです。話す相手は **Grok だけ**。**Codex** は設計・独立レビュー・原因調査を既定で担当します。**実装の既定は Grok**、完了判定（verify）も Grok です。

[Claude Code Orchestra](https://github.com/DeL-TaiseiOzaki/claude-code-orchestra) と [Antigravity Orchestra](https://github.com/Sora-bluesky/antigravity-orchestra) の概念を参照しています。

## なぜ

- **単一 UI** — 触るのは Grok のみ
- **役割分割** — Grok が実装、Codex が計画・レビュー・原因調査（Codex がコードを書くのは例外）
- **ファイル SSOT** — セッション共有なし。packet と docs が共有面
- **失敗モードを設計で潰す** — コンテキスト汚染・二重書き込み・偽 done・コスト爆発など → [`.agents/docs/failure-modes.md`](.agents/docs/failure-modes.md)

## 前提

| ツール | メモ |
|--------|------|
| [Grok Build](https://x.ai) CLI | `grok login`（または `XAI_API_KEY`） |
| [Codex CLI](https://github.com/openai/codex) | `codex login` |
| Windows PowerShell 7+ | スクリプト実行に推奨 |

```powershell
codex --version
grok models   # または grok --version
```

## クイックスタート

```powershell
git clone https://github.com/Sora-bluesky/grok-orchestra.git
cd grok-orchestra
Copy-Item .agents\STATE.example.md .agents\STATE.md   # 任意
grok
```

最初のメッセージ例:

```text
あなたはこの grok-orchestra ワークスペースのオペレーターです。
./AGENTS.md と ./.agents/skills/ の契約に従ってください。
.agents/STATE.md が無ければ .agents/STATE.example.md から作ってください。
トポロジと次の安全な一手を10行以内で要約してください。
```

### スモーク

```powershell
.\scripts\delegate-codex.ps1 -JobId smoke-001 -Type review -PromptFile .agents\docs\packets\smoke-001.prompt.txt
```

`.agents/logs/codex/smoke-001.last.txt` が非空になれば OK（gitignore 対象）。

## 役割

| 作業 | 担当 | モード |
|------|------|--------|
| オーケストレーション、実装（既定）、verify | **Grok** | 対話 |
| 設計 / 計画 | **Codex** | `read-only` |
| 原因調査（診断 + 修正方針） | **Codex** | `read-only` |
| 独立レビュー / 監査 | **Codex** | `read-only` |
| 診断後の修正適用 | **Grok**（既定） | write |
| 大規模 / 長時間 / コンテキスト膨張の実装 | **Codex**（例外） | `workspace-write` |

**目安:** Codex は疑う側・調査側、Grok は手を動かす側。非自明な Grok 実装のあとは Codex レビューしてから done。

原因調査が **read-only** なのは意図的です。Codex は診断と修正方針を返し、パッチ適用は別ステップ（通常 Grok）にします。

## 隔離

| 層 | 意味 |
|----|------|
| **L0**（既定） | プロダクトコードの書き手は同時に1人（Grok **または** Codex） |
| **L1** | `scripts/lease-paths.ps1` によるパス所有権 |
| **L2**（任意） | job ごとの git worktree |

## レイアウト

```text
AGENTS.md                 # オペレーター契約（まずここ）
.agents/                  # rules / skills / docs / packets / logs
.agents/STATE.example.md  # 任意の STATE 雛形
.codex/AGENTS.md          # このツリーで Codex に見せる契約
.grok/rules/              # Grok 向け薄いルール
scripts/delegate-codex.ps1
scripts/lease-paths.ps1
docs/architecture.md
```

任意の作業状態（gitignore）: `.agents/STATE.md`, `PROGRESS.md`。

## スキル

| スキル | 用途 |
|--------|------|
| `context-loader` | 最小コンテキスト読み込み |
| `codex-system` | Codex 委譲 |
| `verify-job` | プロダクト書き込み後の完了ゲート |
| `plan` | Codex 計画 → 実装 |
| `tdd` | red → green → refactor |
| `simplify` | 監査 → 任意で修正 |
| `init` | このハーネスをワークスペースへ載せる（別アプリツリー含む） |
| `startproject` / `checkpointing` / `design-tracker` | 立ち上げと継続 |

詳細: [`.agents/INDEX.md`](.agents/INDEX.md)

## ライセンス

MIT
