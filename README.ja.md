# grok-orchestra

[English](README.md) | [日本語](README.ja.md)

**Grok = オペレーター · Codex CLI = 唯一のワーカー**

[Claude Code Orchestra](https://github.com/DeL-TaiseiOzaki/claude-code-orchestra) と [Antigravity Orchestra](https://github.com/Sora-bluesky/antigravity-orchestra) の概念を吸収したマルチエージェント開発ハーネスです（Claude Code はワーカーにしません）。

## なぜ

- ユーザーが触るのは **Grok だけ**
- 深い設計・レビュー・複雑実装は **Codex**（`codex exec`）
- 共有状態は **ファイルのみ**（セッション共有なし）
- 失敗モード（コンテキスト汚染・二重書き込み・偽 done・コスト爆発など）を設計で潰す → `.agents/docs/failure-modes.md`

## 前提

- Grok Build CLI 認証済み
- Codex CLI 認証済み
- Windows PowerShell 7+ 推奨

## クイックスタート

```powershell
cd path\to\grok-orchestra
grok
```

```text
AGENTS.md と .agents/STATE.md を読む（無ければ STATE.example.md から作成）
```

スモーク（Codex read-only レビュー）:

```powershell
.\scripts\delegate-codex.ps1 -JobId smoke-001 -Type review -PromptFile .agents\docs\packets\smoke-001.prompt.txt
```

ローカル専用（gitignore。必要に応じて作成）:

| ファイル | 用途 |
|----------|------|
| `HANDOFF.md` | セッション引き継ぎ |
| `PROGRESS.md` | 日付付き進捗ログ |
| `.agents/STATE.md` | フェーズ / 最終 job（雛形: `.agents/STATE.example.md`） |

## 隔離

| 層 | 意味 |
|----|------|
| **L0**（既定） | 書き手は1人。Codex implement 中は Operator が同ツリーのコード編集を止める |
| **L1** | ファイル所有権リース（`scripts/lease-paths.ps1`） |
| **L2**（後続） | job ごと git worktree（任意。CCO の本線ではない） |

## ライセンス

MIT
