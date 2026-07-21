# grok-orchestra

[English](README.md) | [日本語](README.ja.md)

**Grok = オペレーター · Codex CLI = 専門ワーカー**

マルチエージェント開発ハーネスです。ユーザーが話す相手は **Grok だけ**。**Codex** は設計・レビュー・深いデバッグを既定で担当します。実装の既定は Grok、完了判定（verify）も Grok です。

[Claude Code Orchestra](https://github.com/DeL-TaiseiOzaki/claude-code-orchestra) と [Antigravity Orchestra](https://github.com/Sora-bluesky/antigravity-orchestra) の概念を参照しています（Claude Code をワーカーにはしません）。

## なぜ

- **単一 UI** — 触るのは Grok のみ
- **役割分割** — Grok が実装、Codex が設計/レビュー/デバッグ（Codex 実装は例外）
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

このリポジトリを clone（または template 利用）し、**このツリー内**で作業してください。読む契約は **このリポの** `AGENTS.md` です。

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

### スモーク（Codex read-only）

```powershell
.\scripts\delegate-codex.ps1 -JobId smoke-001 -Type review -PromptFile .agents\docs\packets\smoke-001.prompt.txt
```

`.agents/logs/codex/smoke-001.last.txt` が非空になれば OK（gitignore 対象）。

## 役割

| 役割 | 担当 |
|------|------|
| オーケストレーター、既定の **実装**、軽い調査、**verify** | Grok |
| 設計、デバッグ、**監査・レビュー** | Codex（`read-only`） |
| 実装（例外） | 親コンテキストが膨らむ・長時間バッチ・明示指定のときだけ Codex `workspace-write` |

**目安:** Codex は疑う側、Grok は手を動かす側。非自明な Grok 実装のあとは Codex レビューしてから done。

## 隔離

| 層 | 意味 |
|----|------|
| **L0**（既定） | プロダクトコードの書き手は同時に1人（Grok **または** Codex） |
| **L1** | `scripts/lease-paths.ps1` によるパス所有権 |
| **L2**（任意・後続） | job ごとの git worktree |

## 別プロジェクトに組み込む

1. `.agents/`・`scripts/`・ルート `AGENTS.md`・必要なら `.codex/` / `.grok/` をコピーまたは submodule  
2. 既存のエージェント契約と **慎重にマージ**（優先: ユーザー指示 → active packet → このハーネス契約）  
3. ライブな作業状態を使うならローカル専用に:

| パス | 追跡? | 用途 |
|------|-------|------|
| `AGENTS.md` | する | このハーネスのオペレーター契約 |
| `.agents/STATE.example.md` | する | ローカル状態の雛形 |
| `.agents/STATE.md` | しない | フェーズ / 最終 job |
| `PROGRESS.md` | しない | 任意の日付付きログ |

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

## スキル（入口）

| スキル | 用途 |
|--------|------|
| `context-loader` | 最小コンテキスト読み込み |
| `codex-system` | Codex 委譲（設計/レビュー/デバッグ。実装は例外） |
| `verify-job` | プロダクト書き込み後の完了ゲート |
| `plan` | Codex 計画 → 承認後に実装 |
| `tdd` | red → green → refactor（Grok 実装、Codex レビュー） |
| `simplify` | Codex 監査 → 任意で Grok 修正 |
| `init` / `startproject` / `checkpointing` / `design-tracker` | 立ち上げと継続 |

詳細: [`.agents/INDEX.md`](.agents/INDEX.md)

## ライセンス

MIT
