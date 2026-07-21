# 🎻 grok-orchestra

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Windows-blue.svg)](#-前提条件)
[![CI](https://github.com/Sora-bluesky/grok-orchestra/actions/workflows/ci.yml/badge.svg)](https://github.com/Sora-bluesky/grok-orchestra/actions/workflows/ci.yml)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/Sora-bluesky/grok-orchestra/issues)

**🌐 Language: [English](README.md) | 日本語**

---

**grok-orchestra** は [Grok Build](https://x.ai)(xAI)と [OpenAI Codex CLI](https://github.com/openai/codex) を協調させるマルチエージェント開発ハーネスです。**Grok がオペレーター兼デフォルト実装者、Codex が懐疑役** — 設計者・独立レビュアー・原因調査役を務めます。

現行リリース: **[v0.1.0](https://github.com/Sora-bluesky/grok-orchestra/releases/tag/v0.1.0)** · [Changelog](CHANGELOG.md) · `main` は v0.2.0 開発版(テスト・CI・doctor/verify ツール・インストーラー)を含みます。

[Claude Code Orchestra](https://github.com/DeL-TaiseiOzaki/claude-code-orchestra)(@mkj / 松尾研究所)と [Antigravity Orchestra](https://github.com/Sora-bluesky/antigravity-orchestra) にインスパイアされています。

---

## ✨ これは何?

```
┌──────────────────────────────────────────────────────────────┐
│                        ユーザー                              │
│                            │                                 │
│                            ▼                                 │
│  ┌────────────────────────────────────────────────────────┐  │
│  │   Grok Build(オペレーター / Tier 1)                  │  │
│  │   → 唯一の UI、デフォルト Builder、verify の所有者     │  │
│  │                                                        │  │
│  │      packet ──▶ scripts/delegate-codex.ps1 ──▶         │  │
│  │        ┌──────────────────────────────────────────┐    │  │
│  │        │  Codex CLI(ワーカー "sol" / Tier 2)     │    │  │
│  │        │  → 設計・レビュー・原因調査              │    │  │
│  │        │    (既定は read-only)                   │    │  │
│  │        └──────────────────────────────────────────┘    │  │
│  │                       │                                │  │
│  │      結果ファイル ◀───┘  .agents/logs/codex/*.txt      │  │
│  │        │                                               │  │
│  │        ▼                                               │  │
│  │   verify-job ゲート → done(または差し戻し)           │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

**インターフェースは Grok ひとつだけ。** ユーザーは Grok CLI と話し、Grok は *Prompt Contract packet* をファイルに書き、ガード付き PowerShell ブリッジ経由で委譲し、Codex の回答をファイルから読み戻します。Grok と Codex はチャットセッションを共有しません — **共有メモリはファイルのみ**です(設計意図: [F20](.agents/docs/failure-modes.md))。

このハーネスの特徴は 3 つ:

1. **失敗モードを設計に織り込み済み** — コンテキスト腐敗・偽の完了・二重書き込み・コスト暴発など、マルチエージェント特有の失敗 20 種と対策のカタログ: [`.agents/docs/failure-modes.md`](.agents/docs/failure-modes.md)
2. **規律は散文でなくスクリプトで強制** — 不完全な packet は実行拒否、write ジョブはシングルライターロック、done には機械的 verify ゲートが必須
3. **ハーネス自身がテスト済み** — ツール群に Pester スイート(40 テスト)があり、[CI](.github/workflows/ci.yml)(`windows-latest`)で回っています

---

## 🎯 こんな人向け

- Grok Build を常用しているが、**別モデル系統による独立した設計・レビュー品質**が欲しい
- オーケストレーターが「自分で自分をレビュー」して偽の完了を出すマルチエージェント構成に懲りた
- 自分のアプリのツリーにも同じ規律を敷きたい — **ワンコマンドインストーラー**付き

---

## 🎭 役割分担

| 役割 | エージェント | モード | タスク |
|------|------|------|------|
| **オペレーター** | Grok | 対話 | ユーザー対応、ルーティング、統合 |
| **Builder(既定)** | Grok | write | 実装、診断後の修正適用 |
| **Verifier** | Grok | — | 完了ゲート: 全プロダクト書き込み後の `verify-job` |
| **Designer** | Codex CLI | `read-only` | アーキテクチャ、実装計画、トレードオフ分析 |
| **Investigator** | Codex CLI | `read-only` | 根本原因分析 → 診断 + 修正計画(パッチ自体は書かない) |
| **Auditor** | Codex CLI | `read-only` | 非自明な Grok パッチ後の独立レビュー |
| **Implementer(例外)** | Codex CLI | `workspace-write` | コンテキスト過大 / 長時間バッチのみ |

**一行ルール:** Codex は懐疑役、手を動かすのは Grok。原因調査が read-only なのは*意図的* — パッチ適用は検証付きの別 write ステップです。

---

## 📋 前提条件

| 要件 | 確認方法 | 備考 |
|------|------|------|
| Git | `git --version` | 未導入なら [git-scm.com](https://git-scm.com) |
| PowerShell 5.1+ | `$PSVersionTable.PSVersion` | Windows 標準。PowerShell 7(`pwsh`)推奨 |
| スクリプト実行許可 | `Get-ExecutionPolicy` | `Restricted` なら `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |
| Grok Build CLI | `grok models`(または `grok --version`) | [x.ai](https://x.ai) — `grok login` または `XAI_API_KEY` |
| Codex CLI | `codex --version` | [公式インストーラー](https://learn.chatgpt.com/docs/codex/cli)。npm 経由(`npm i -g @openai/codex`)も可 |
| Codex 認証 | `codex login` | 対応 ChatGPT プランまたは API キー |
| Pester 5+(任意) | `Invoke-Pester -?` | ハーネス自身のテストを回す場合のみ |

環境をまとめて診断するには doctor を実行:

```powershell
.\scripts\check.ps1        # ツール、SSOT レイアウト、ステールロック、gitignore 整合
.\scripts\check.ps1 -Fix   # 加えて、ステールと証明できたロック/リースを掃除
```

---

## 🚀 クイックスタート

### Step 1: クローン

```powershell
cd C:\Users\YOUR_USERNAME\Documents\Projects
git clone https://github.com/Sora-bluesky/grok-orchestra.git
cd grok-orchestra
Copy-Item .agents\STATE.example.md .agents\STATE.md   # 任意: ライブ状態の seed(gitignored)
```

### Step 2: Codex ブリッジのスモークテスト

```powershell
.\scripts\delegate-codex.ps1 -JobId smoke-001 -Type review -PromptFile .agents\docs\packets\smoke-001.prompt.txt
```

exit 0 と、非空の `.agents/logs/codex/smoke-001.last.txt`(gitignored)が期待値です。packet に必須見出しが欠けていると、スクリプトは **Codex の実行自体を拒否**します — それが Prompt Contract ゲートです。

> 💡 実トランスクリプト付きの一連の流れ: [docs/walkthrough.ja.md](docs/walkthrough.ja.md) · [English](docs/walkthrough.md)

### Step 3: オペレーターとして Grok を起動

```powershell
grok
```

最初のメッセージ例:

```text
You are the operator for this grok-orchestra workspace.
Follow ./AGENTS.md and skills under ./.agents/skills/.
If .agents/STATE.md is missing, seed it from .agents/STATE.example.md.
Summarize topology and the next safe action in under 10 lines.
```

### Step 4(任意): 自分のプロジェクトへ導入

```powershell
.\scripts\install.ps1 -Target C:\path\to\your-app          # 既存ファイルは一切上書きしない
.\scripts\install.ps1 -Target C:\path\to\your-app -DryRun  # プレビューのみ
```

インストーラーはハーネス一式(契約・スキル・ルール・スクリプト)をコピーし、導入先専用のスモーク packet を生成、gitignore ブロックを追記します。導入先に既存の `AGENTS.md` があれば、それには触れず `AGENTS.grok-orchestra.md` としてマージ提案を置きます。スキップは全件報告 — 無音の動作はありません。

---

## 📁 ディレクトリ構成

```
grok-orchestra/
├── AGENTS.md                 # 共有オペレーター契約(まずここ)
├── .agents/
│   ├── INDEX.md              # レジストリ: ランタイム・スキル・スクリプト・ルール
│   ├── STATE.example.md      # ローカル STATE.md の seed(ライブ状態は gitignored)
│   ├── docs/
│   │   ├── DESIGN.md             # 不変条件・ルーティング・隔離の決定事項
│   │   ├── failure-modes.md      # F01–F20 カタログと対策
│   │   ├── CODEX_PACKET_PLAYBOOK.md
│   │   └── packets/              # Prompt Contract packet(ジョブ入力)
│   ├── rules/                # codex-delegation, isolation, role-boundaries, tiers
│   ├── skills/               # 10 スキル(下記)
│   ├── locks/                # write-job.lock + パスリース(gitignored)
│   └── logs/codex/           # ジョブ結果 *.last.txt(gitignored)
├── .codex/AGENTS.md          # このツリー内で Codex が読む契約
├── .grok/rules/operator.md   # 薄い Grok オペレータールール
├── scripts/
│   ├── delegate-codex.ps1    # ガード付きブリッジ: 契約ゲート → ロック → codex exec → ログ
│   ├── verify-job.ps1        # 機械的完了ゲート(diff scope、スタブ/テスト弱体化検出)
│   ├── check.ps1             # 環境 doctor + ステールロック GC
│   ├── install.ps1           # 別プロジェクトへのワンコマンド導入
│   ├── lease-paths.ps1       # L1 パスリース
│   └── lib/path-normalize.ps1
├── tests/                    # ハーネス自身の Pester スイート(40 テスト)
├── .github/workflows/ci.yml  # push/PR で windows-latest の Pester 実行
├── plans/                    # v0.2.0 ドッグフーディング計画(advisor handoff)
└── docs/architecture.md
```

---

## 🛡️ ガードレール

### Prompt Contract(F04)

すべての Codex ジョブは、必須 5 セクション — `## Objective` / `## Constraints` / `## Relevant files` / `## Acceptance checks` / `## Output format` — を持つファイルです。ブリッジは不完全な packet の**実行を拒否**するため、「伝言ゲーム」型の委譲事故が黙って起きることはありません。

### 隔離ラダー(F08)

| レイヤー | 既定? | 機構 |
|------|------|------|
| **L0** | ✅ | プロダクトコードの writer は同時に 1 人 — `write-job.lock`(ステール判定用 PID 入り) |
| **L1** | オプトイン | パスリース: `scripts/lease-paths.ps1` が `owned_paths` の重複を拒否 |
| **L2** | 将来 | ジョブごとの git worktree(v0.3 予定) |

### 完了ゲート(F06/F07)

ワーカーの散文は *done* ではありません。done とはオペレーターが次を実行したこと:

```powershell
.\scripts\verify-job.ps1 -JobId <id> [-OwnedPaths src] [-BaseRef <sha>]
```

機械的にチェックする内容: 結果ログの存在、**diff が owned paths 内に収まっているか**(staged + unstaged + untracked)、追加行のスタブマーカー、そして**テストの削除・tests 外への rename・skip 付与によるすり抜け**。上書き(`-AcceptTestChanges`)は常に明示 — 暗黙には通りません。

### サンドボックスラダー(F18)

`review` / `design` / `investigate` は `read-only`、`implement` / `fix` は `workspace-write`。`danger-full-access` が既定になることはありません。

---

## 🧰 スキル

| スキル | 用途 |
|------|------|
| `context-loader` | 最小セッションロード: STATE + DESIGN + アクティブ packet のみ(F01) |
| `codex-system` | ガード付きブリッジ経由で設計/レビュー/調査を委譲 |
| `verify-job` | 全プロダクト書き込み後の完了ゲート(`verify-job.ps1` が裏付け) |
| `plan` | Codex が承認ゲート付き計画を作成、実装は Grok |
| `tdd` | Red → Green → Refactor。Grok が書き、Codex がレビュー |
| `simplify` | Codex が削除・簡素化を監査、承認分を Grok が適用 |
| `init` | このツリーまたは別アプリへの SSOT 配置/検証(`install.ps1` が裏付け) |
| `startproject` | 6 フェーズのプロジェクトキックオフ |
| `checkpointing` | セッション境界で STATE / PROGRESS を永続化(F12) |
| `design-tracker` | レビュー証跡付きで設計判断を維持 |

詳細: [`.agents/INDEX.md`](.agents/INDEX.md)

---

## 💬 基本的な使用例

### 例 1: 設計相談(read-only Codex)

Grok に「認証モジュールの構成はどうすべき? セカンドオピニオンが欲しい」と依頼。
Grok が `design` packet を作成 → Codex が TL;DR / 分析 / 計画 / リスクを返す → Grok が統合して実装。

### 例 2: 原因調査

「CI でだけテストが落ちる。理由がわからない」
Grok が `investigate` ジョブを委譲。Codex は**診断 + 修正計画のみ**を返し(read-only)、修正の適用は Grok → `verify-job`。

### 例 3: done 前の独立レビュー

非自明な Grok パッチの後は:

```powershell
.\scripts\delegate-codex.ps1 -JobId review-042 -Type review -PromptFile .agents\docs\packets\review-042.prompt.txt
.\scripts\verify-job.ps1 -JobId review-042
```

### 例 4: 例外的な Codex 実装(リース付き)

```powershell
.\scripts\delegate-codex.ps1 -JobId impl-007 -Type implement -PromptFile .agents\docs\packets\impl-007.prompt.txt -OwnedPaths src\parser
```

L0 の write ロックに**加えて** `src/parser` の L1 リースを取得。同じパスに触る 2 本目のジョブは拒否されます。

---

## ❓ FAQ

<details>
<summary><strong>Q: Codex CLI なしでも使えますか?</strong></summary>

このハーネスの核心 — 独立した懐疑役 — が失われます。Grok が実装*と*レビューを兼ねることになり、それはまさにこの設計が防ごうとしている失敗モード(F06、自己レビューバイアス)です。ファイルレイアウト自体は動きますが、Codex の導入(または別 CLI へのブリッジ改造)を推奨します。

</details>

<details>
<summary><strong>Q: なぜ Grok と Codex はセッションではなくファイルだけを共有するのですか?</strong></summary>

別々の CLI ツール間の「共有メモリ」は幻想だからです(F20)— 各自のコンテキストは静かに乖離していきます。ファイル(入力は packet、出力は結果ファイル、SSOT は STATE/DESIGN)なら、すべての引き継ぎが明示的で、監査可能で、再現可能になります。

</details>

<details>
<summary><strong>Q: なぜ調査は read-only? Codex がバグを見つけたなら直させればいいのに</strong></summary>

診断とパッチ適用を分けることで writer を常に 1 人に保ち(F08)、修正をオペレーター所有の verify ゲートに必ず通します。実際のところ難しいのは診断であり、適用は安価で、Grok の手で行うほうが安全です。

</details>

<details>
<summary><strong>Q: macOS / Linux で動きますか?</strong></summary>

契約とスキルはツール中立な Markdown ですが、ブリッジスクリプトは Windows 向けの PowerShell です。PowerShell 7 はクロスプラットフォームなので、移植の大半はパスとロックの配管作業です — コントリビューション歓迎。

</details>

<details>
<summary><strong>Q: Grok と Codex のサブスクリプションはどの程度必要?</strong></summary>

Grok Build は Grok/xAI アカウント(`grok login`)か `XAI_API_KEY`。Codex CLI は対応 ChatGPT プラン(Plus で十分)か API キーで動きます。ハーネス自体は課金サービスを追加しません — 「既定は直列実装」のルーティング(F11)は、まさにトークンコストを正気に保つためにあります。

</details>

<details>
<summary><strong>Q: write ジョブがクラッシュして、以後ずっと「別のジョブが実行中」と言われます</strong></summary>

`.\scripts\check.ps1` を実行してください — 記録された PID が生存していないロックを検出し、`-Fix` でステールと証明できたロックの削除と孤児リースのマークを行います。確認なしに `write-job.lock` を手で消さないでください。

</details>

---

## 🔧 トラブルシューティング

| 症状 | 対処 |
|------|------|
| `running scripts is disabled on this system` | `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` して再実行 |
| `Prompt Contract incomplete. Missing: …` | 列挙された `##` 見出しを packet に追加 — このゲートは仕様であってバグではありません |
| `L0 single-writer: another write job is running` | write ジョブ実行中 — 待つか、クラッシュ後なら `.\scripts\check.ps1 -Fix` |
| `lease overlap; refuse acquire` | 実行中ジョブがそのパスを所有中 — 重複しない `-OwnedPaths` を選ぶか待つ |
| `codex exec … empty last message` | `codex login` を確認し、`.agents/logs/codex/<id>.combined.log` を確認 |
| `verify-job: FAIL`(`f07:tests`) | テストを削除/skip しています。本当に意図的なら `-AcceptTestChanges` で再実行し、理由を PR に明記 |
| Grok が契約を無視する | リポジトリ内で `grok` を起動し、最初のメッセージで `./AGENTS.md` を指しているか確認 |

---

## ⚠️ 注意事項

- **Grok Build と Codex CLI はどちらも活発に開発中です。** フラグや挙動は変わりえます。アップグレード後はまず `check.ps1`。
- **このテンプレートは Windows ファースト**(PowerShell 5.1+/7)。移植については FAQ 参照。
- `.agents/` 配下のログとロックは意図的に gitignored です — 結果ファイルはコードを引用しうるため、コミット厳禁(F19)。

---

## 🤝 フィードバック

バグ報告や提案は [Issue](https://github.com/Sora-bluesky/grok-orchestra/issues) へお願いします。

---

## 🔗 関連リンク

### 参考

| リソース | 作者 | 内容 |
|------|------|------|
| [Claude Code Orchestra](https://zenn.dev/mkj/articles/claude-code-orchestra_20260120) | @mkj(松尾研究所) | マルチエージェント協調のコンセプト |
| [GitHub: claude-code-orchestra](https://github.com/DeL-TaiseiOzaki/claude-code-orchestra) | DeL-TaiseiOzaki | 実装例 |
| [Antigravity Orchestra](https://github.com/Sora-bluesky/antigravity-orchestra) | Sora-bluesky | 兄弟ハーネス(Antigravity + Codex) |

### ツール

- [Grok Build(xAI)](https://x.ai)
- [OpenAI Codex CLI](https://github.com/openai/codex)

---

## 📜 ライセンス

MIT License — 詳細は [LICENSE](LICENSE) を参照。

---

## 🙏 謝辞

本プロジェクトは、[@mkj](https://zenn.dev/mkj)(松尾研究所)による **Claude Code Orchestra** のマルチエージェント協調コンセプトと、**Antigravity Orchestra** の単一 UI ロール分割を Grok Build + Codex CLI ペアに適用し、失敗モードカタログとスクリプト強制ゲートを独自に発展させたものです。

---

📅 **最終更新**: 2026年7月21日
