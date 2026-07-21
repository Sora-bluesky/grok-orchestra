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

このリポジトリは **ハーネス用テンプレート** です。読むのは **このツリー内の契約** です。別プロジェクトの `HANDOFF.md` や、別リポの `AGENTS.md` を前提にしないでください。

```powershell
cd path\to\grok-orchestra
# 任意: このワークスペース用のローカル状態
Copy-Item .agents\STATE.example.md .agents\STATE.md
grok
```

Grok への最初のメッセージ例:

```text
あなたはこの grok-orchestra ワークスペースのオペレーターです。
./AGENTS.md と ./.agents/skills/ の契約に従ってください。
HANDOFF.md は探さないでください（ローカル任意。公開テンプレの一部ではありません）。
.agents/STATE.md が無ければ .agents/STATE.example.md から作ってください。
トポロジと次の安全な一手を10行以内で要約してください。
```

スモーク（このリポ上での Codex read-only レビュー）:

```powershell
.\scripts\delegate-codex.ps1 -JobId smoke-001 -Type review -PromptFile .agents\docs\packets\smoke-001.prompt.txt
```

### 別プロジェクトに組み込む場合

1. `.agents/`・`scripts/`・ルート契約の型を対象アプリへコピーまたは submodule する  
2. 既にある `AGENTS.md` とは **慎重にマージ**する（優先順位: ユーザー指示 → active packet → このハーネス契約）  
3. セッション継続用ファイルを使うなら **ローカル専用** にする:

| ファイル | 公開? | 用途 |
|----------|-------|------|
| このリポの `AGENTS.md` | 追跡 | *この* ハーネスのオペレーター契約 |
| `.agents/STATE.example.md` | 追跡 | ローカル状態の雛形 |
| `.agents/STATE.md` | gitignore | フェーズ / 最終 job（任意） |
| `PROGRESS.md` | gitignore | 日付付きログ（任意） |
| `HANDOFF.md` | gitignore | 引き継ぎ（任意・メンテ用） |

## 隔離

| 層 | 意味 |
|----|------|
| **L0**（既定） | 書き手は1人。Codex implement 中は Operator が同ツリーのコード編集を止める |
| **L1** | ファイル所有権リース（`scripts/lease-paths.ps1`） |
| **L2**（後続） | job ごと git worktree（任意。CCO の本線ではない） |

## ライセンス

MIT
