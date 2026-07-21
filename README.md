# 🎻 grok-orchestra

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Windows-blue.svg)](#-prerequisites)
[![CI](https://github.com/Sora-bluesky/grok-orchestra/actions/workflows/ci.yml/badge.svg)](https://github.com/Sora-bluesky/grok-orchestra/actions/workflows/ci.yml)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/Sora-bluesky/grok-orchestra/issues)

**🌐 Language: English | [日本語](README.ja.md)**

---

**grok-orchestra** is a multi-agent development harness that orchestrates [Grok Build](https://x.ai) (xAI) and [OpenAI Codex CLI](https://github.com/openai/codex): **Grok is the operator and default implementer, Codex is the skeptic** — designer, independent reviewer, and root-cause investigator.

Current release: **[v0.1.0](https://github.com/Sora-bluesky/grok-orchestra/releases/tag/v0.1.0)** · [Changelog](CHANGELOG.md) · `main` carries v0.2.0 development (tests, CI, doctor/verify tooling, installer).

Inspired by [Claude Code Orchestra](https://github.com/DeL-TaiseiOzaki/claude-code-orchestra) by @mkj (Matsuo Institute) and [Antigravity Orchestra](https://github.com/Sora-bluesky/antigravity-orchestra).

---

## ✨ What is This?

```
┌──────────────────────────────────────────────────────────────┐
│                          User                                │
│                            │                                 │
│                            ▼                                 │
│  ┌────────────────────────────────────────────────────────┐  │
│  │   Grok Build (Operator / Tier 1)                       │  │
│  │   → single UI, default Builder, owns verification      │  │
│  │                                                        │  │
│  │      packet ──▶ scripts/delegate-codex.ps1 ──▶         │  │
│  │        ┌──────────────────────────────────────────┐    │  │
│  │        │  Codex CLI (Worker "sol" / Tier 2)       │    │  │
│  │        │  → design, review, investigate           │    │  │
│  │        │    (read-only by default)                │    │  │
│  │        └──────────────────────────────────────────┘    │  │
│  │                       │                                │  │
│  │      result file ◀────┘   .agents/logs/codex/*.txt     │  │
│  │        │                                               │  │
│  │        ▼                                               │  │
│  │   verify-job gate  →  done (or rework)                 │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

**Single interface — Grok only.** You talk to the Grok CLI; it writes a *Prompt Contract packet* to a file, delegates through a guarded PowerShell bridge, and reads Codex's answer back from a file. Grok and Codex never share a chat session — **files are the only shared memory** (by design, see [F20](.agents/docs/failure-modes.md)).

Three things set this harness apart:

1. **Failure modes designed in** — a catalog of 20 multi-agent failure modes (context rot, false done, dual-write, cost blowup…) with a mitigation for each: [`.agents/docs/failure-modes.md`](.agents/docs/failure-modes.md)
2. **Discipline enforced by scripts, not prose** — incomplete packets are rejected, write jobs take a single-writer lock, done requires a mechanical verify gate
3. **Tested harness** — the tooling itself has a Pester suite (40 tests) running in [CI](.github/workflows/ci.yml) on `windows-latest`

---

## 🎯 Who is This For?

- You use Grok Build as your daily driver but want **independent design and review quality** from a second model family
- You've been burned by multi-agent setups where the orchestrator "reviewed itself" and shipped a false *done*
- You want your own app tree to adopt the same discipline — with a **one-command installer**

---

## 🎭 Role Distribution

| Role | Agent | Mode | Tasks |
|------|-------|------|-------|
| **Operator** | Grok | interactive | User interaction, routing, integration |
| **Builder (default)** | Grok | write | Implementation, applying fixes after diagnosis |
| **Verifier** | Grok | — | The done gate: `verify-job` after every product write |
| **Designer** | Codex CLI | `read-only` | Architecture, implementation planning, trade-offs |
| **Investigator** | Codex CLI | `read-only` | Root cause analysis → diagnosis + fix plan (not the patch) |
| **Auditor** | Codex CLI | `read-only` | Independent review after non-trivial Grok patches |
| **Implementer (exception)** | Codex CLI | `workspace-write` | Only for context-heavy / long unattended batches |

**One-line rule:** Codex is the skeptic; Grok moves the hands. Investigation is read-only *on purpose* — applying the patch is a separate, verified write step.

---

## 📋 Prerequisites

| Requirement | How to Check | Notes |
|-------------|--------------|-------|
| Git | `git --version` | [git-scm.com](https://git-scm.com) if missing |
| PowerShell 5.1+ | `$PSVersionTable.PSVersion` | Ships with Windows; PowerShell 7 (`pwsh`) recommended |
| Script execution allowed | `Get-ExecutionPolicy` | If `Restricted`: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |
| Grok Build CLI | `grok models` (or `grok --version`) | [x.ai](https://x.ai) — `grok login` or `XAI_API_KEY` |
| Codex CLI | `codex --version` | [Official installer](https://learn.chatgpt.com/docs/codex/cli); npm route (`npm i -g @openai/codex`) also works |
| Codex auth | `codex login` | A supported ChatGPT plan or API key |
| Pester 5+ (optional) | `Invoke-Pester -?` | Only needed to run the harness's own test suite |

To diagnose the harness environment (Codex CLI presence, SSOT layout, stale locks, gitignore hygiene — Git/Grok/Pester are checked per the table above), run the doctor:

```powershell
.\scripts\check.ps1        # codex, SSOT layout, stale locks, gitignore hygiene
.\scripts\check.ps1 -Fix   # additionally clean provable-stale locks/leases
```

---

## 🚀 Quick Start

### Step 1: Clone

```powershell
cd C:\Users\YOUR_USERNAME\Documents\Projects
git clone https://github.com/Sora-bluesky/grok-orchestra.git
cd grok-orchestra
Copy-Item .agents\STATE.example.md .agents\STATE.md   # optional: seed live state (gitignored)
```

### Step 2: Smoke test the Codex bridge

```powershell
.\scripts\delegate-codex.ps1 -JobId smoke-001 -Type review -PromptFile .agents\docs\packets\smoke-001.prompt.txt
```

Expect exit 0 and a non-empty `.agents/logs/codex/smoke-001.last.txt` (gitignored). If the packet were missing a required heading, the script would **refuse to run Codex at all** — that's the Prompt Contract gate.

> 💡 See the full cycle with real transcripts: [docs/walkthrough.md](docs/walkthrough.md) · [日本語](docs/walkthrough.ja.md)

### Step 3: Launch Grok as the operator

```powershell
grok
```

Example first message:

```text
You are the operator for this grok-orchestra workspace.
Follow ./AGENTS.md and skills under ./.agents/skills/.
If .agents/STATE.md is missing, seed it from .agents/STATE.example.md.
Summarize topology and the next safe action in under 10 lines.
```

### Step 4 (optional): Install into your own project

```powershell
.\scripts\install.ps1 -Target C:\path\to\your-app          # never overwrites existing files
.\scripts\install.ps1 -Target C:\path\to\your-app -DryRun  # preview only
```

The installer copies the harness (contract, skills, rules, scripts), generates a target-specific smoke packet, appends the gitignore block, and — if your app already has an `AGENTS.md` — writes a merge proposal as `AGENTS.grok-orchestra.md` instead of touching yours. Every skip is reported; nothing is silent.

---

## 📁 Directory Structure

```
grok-orchestra/
├── AGENTS.md                 # Shared operator contract (start here)
├── .agents/
│   ├── INDEX.md              # Registry: runtimes, skills, scripts, rules
│   ├── STATE.example.md      # Seed for local STATE.md (live state is gitignored)
│   ├── docs/
│   │   ├── DESIGN.md             # Invariants, routing, isolation decisions
│   │   ├── failure-modes.md      # F01–F20 catalog with mitigations
│   │   ├── CODEX_PACKET_PLAYBOOK.md
│   │   └── packets/              # Prompt Contract packets (job inputs)
│   ├── rules/                # codex-delegation, isolation, role-boundaries, tiers
│   ├── skills/               # 10 skills (see below)
│   ├── locks/                # write-job.lock + path leases (gitignored)
│   └── logs/codex/           # Job results *.last.txt (gitignored)
├── .codex/AGENTS.md          # Contract Codex reads inside this tree
├── .grok/rules/operator.md   # Thin Grok operator rules
├── scripts/
│   ├── delegate-codex.ps1    # Guarded bridge: contract gate → lock → codex exec → log
│   ├── verify-job.ps1        # Mechanical done gate (diff scope, stub/test-weakening scan)
│   ├── check.ps1             # Environment doctor + stale lock GC
│   ├── install.ps1           # One-command install into another project tree
│   ├── lease-paths.ps1       # L1 path leases
│   └── lib/path-normalize.ps1
├── tests/                    # Pester suite for the harness itself (40 tests)
├── .github/workflows/ci.yml  # windows-latest Pester run on push/PR
├── plans/                    # v0.2.0 dogfooding plans (advisor handoff)
└── docs/architecture.md
```

---

## 🛡️ The Guardrails

### Prompt Contract (F04)

Every Codex job is a file with five mandatory sections — `## Objective`, `## Constraints`, `## Relevant files`, `## Acceptance checks`, `## Output format`. The bridge **refuses to execute** an incomplete packet, so "telephone game" delegation can't happen quietly.

### Isolation ladder (F08)

| Layer | Default? | Mechanism |
|-------|----------|-----------|
| **L0** | ✅ | One product-code writer at a time — `write-job.lock` (with PID for stale detection) |
| **L1** | opt-in | Path leases: `scripts/lease-paths.ps1` refuses overlapping `owned_paths` |
| **L2** | future | Git worktree per job (planned for v0.3) |

### Done gate (F06/F07)

Worker prose is never *done*. Done means the Operator ran:

```powershell
.\scripts\verify-job.ps1 -JobId <id> [-OwnedPaths src] [-BaseRef <sha>]
```

which mechanically checks: result log exists, **diff stays inside owned paths** (staged + unstaged + untracked), no stub markers in added lines, and **no test files deleted, renamed away, or skip-marked** just to pass. Overrides (`-AcceptTestChanges`) are explicit, never implicit.

### Sandbox ladder (F18)

`review` / `design` / `investigate` run `read-only`; `implement` / `fix` run `workspace-write`; `danger-full-access` is never a default.

---

## 🧰 Skills

| Skill | Use for |
|-------|---------|
| `context-loader` | Minimal session load: STATE + DESIGN + active packet only (F01) |
| `codex-system` | Delegate design / review / investigation via the guarded bridge |
| `verify-job` | The done gate after any product write (backed by `verify-job.ps1`) |
| `plan` | Codex produces an approval-gated plan; Grok implements |
| `tdd` | Red → green → refactor; Grok writes, Codex reviews |
| `simplify` | Codex audits for deletions/simplification; Grok applies approved ones |
| `init` | Place or verify the file SSOT here or in another app tree (backed by `install.ps1`) |
| `startproject` | Six-phase project kickoff |
| `checkpointing` | Persist STATE / PROGRESS at session boundaries (F12) |
| `design-tracker` | Maintain design decisions with review evidence |

Details: [`.agents/INDEX.md`](.agents/INDEX.md).

---

## 💬 Basic Usage Examples

### Example 1: Design consultation (read-only Codex)

Ask Grok: *"How should I structure the auth module? Get a second opinion."*
Grok writes a `design` packet → Codex returns TL;DR / analysis / plan / risks → Grok integrates and implements.

### Example 2: Root-cause investigation

*"Tests fail only on CI and I don't know why."*
Grok delegates an `investigate` job. Codex returns **diagnosis + fix plan only** (read-only); Grok applies the fix, then runs `verify-job`.

### Example 3: Independent review before done

After any non-trivial Grok patch:

```powershell
.\scripts\delegate-codex.ps1 -JobId review-042 -Type review -PromptFile .agents\docs\packets\review-042.prompt.txt
.\scripts\verify-job.ps1 -JobId review-042
```

### Example 4: Exceptional Codex implement (with leases)

```powershell
.\scripts\delegate-codex.ps1 -JobId impl-007 -Type implement -PromptFile .agents\docs\packets\impl-007.prompt.txt -OwnedPaths src\parser
```

Takes the L0 write lock **and** an L1 lease on `src/parser`; a second job touching the same paths is refused.

---

## ❓ FAQ

<details>
<summary><strong>Q: Can I use this without Codex CLI?</strong></summary>

You lose the point of the harness — the independent skeptic. Grok would implement *and* review its own work, which is exactly the failure mode (F06, self-review bias) this design exists to prevent. The file layout still works, but get Codex (or adapt the bridge to another CLI).

</details>

<details>
<summary><strong>Q: Why do Grok and Codex only share files, not a session?</strong></summary>

Because "shared memory" between separate CLI tools is an illusion (F20) — each has its own context that silently diverges. Files (packets in, results out, STATE/DESIGN as SSOT) make every handoff explicit, auditable, and replayable.

</details>

<details>
<summary><strong>Q: Why is investigation read-only? Codex found the bug — let it fix it!</strong></summary>

Splitting diagnosis from patching keeps one writer at a time (F08) and forces the fix through the verify gate under the Operator's ownership. In practice the diagnosis is the hard part; the apply step is cheap and safer in Grok's hands.

</details>

<details>
<summary><strong>Q: Does this work on macOS / Linux?</strong></summary>

The contract and skills are tool-neutral Markdown, but the bridge scripts are PowerShell written for Windows. PowerShell 7 runs cross-platform, so a port is mostly path-and-lock plumbing — contributions welcome.

</details>

<details>
<summary><strong>Q: What do Grok and Codex subscriptions cost me?</strong></summary>

Grok Build needs a Grok/xAI account (`grok login`) or an `XAI_API_KEY`. Codex CLI works with a supported ChatGPT plan (Plus is sufficient) or API key. The harness itself adds no service — the "serial implement by default" routing (F11) exists precisely to keep token costs sane.

</details>

<details>
<summary><strong>Q: A write job crashed and now everything says another job is running.</strong></summary>

Run `.\scripts\check.ps1` — it detects locks whose recorded PID is no longer alive and, with `-Fix`, removes provable-stale locks and marks orphaned leases. Never delete `write-job.lock` by hand without checking.

</details>

---

## 🔧 Troubleshooting

| Issue | Solution |
|-------|----------|
| `running scripts is disabled on this system` | `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`, retry |
| `Prompt Contract incomplete. Missing: …` | Add the listed `##` headings to your packet — the gate is intentional, not a bug |
| `L0 single-writer: another write job is running` | A write job is active — wait, or run `.\scripts\check.ps1 -Fix` if it crashed |
| `lease overlap; refuse acquire` | Another running job owns those paths; pick disjoint `-OwnedPaths` or wait |
| `codex exec … empty last message` | Check `codex login`, then inspect `.agents/logs/codex/<id>.combined.log` |
| `verify-job: FAIL` on `f07:tests` | You removed/skipped tests. If genuinely intended, rerun with `-AcceptTestChanges` and say why in the PR |
| Grok ignores the contract | Make sure you launched `grok` inside the repo and your first message points at `./AGENTS.md` |

---

## ⚠️ Important Notes

- **Grok Build and Codex CLI are both under active development.** Flags and behavior may change; `check.ps1` is your first stop after upgrades.
- **This template is Windows-first** (PowerShell 5.1+/7). See FAQ for the porting story.
- Logs and locks under `.agents/` are gitignored on purpose — result files may quote your code and must never be committed (F19).

---

## 🤝 Feedback

For bug reports or suggestions, please [open an issue](https://github.com/Sora-bluesky/grok-orchestra/issues).

---

## 🔗 Related Links

### References

| Resource | Author | Content |
|----------|--------|---------|
| [Claude Code Orchestra](https://zenn.dev/mkj/articles/claude-code-orchestra_20260120) | @mkj (Matsuo Institute) | Multi-agent coordination concept |
| [GitHub: claude-code-orchestra](https://github.com/DeL-TaiseiOzaki/claude-code-orchestra) | DeL-TaiseiOzaki | Implementation example |
| [Antigravity Orchestra](https://github.com/Sora-bluesky/antigravity-orchestra) | Sora-bluesky | Sibling harness (Antigravity + Codex) |

### Tools

- [Grok Build (xAI)](https://x.ai)
- [OpenAI Codex CLI](https://github.com/openai/codex)

---

## 📜 License

MIT License — see [LICENSE](LICENSE) for details.

---

## 🙏 Acknowledgments

This project adapts the multi-agent coordination concept of **Claude Code Orchestra** by [@mkj](https://zenn.dev/mkj) (Matsuo Institute) and the single-UI role split of **Antigravity Orchestra** to the Grok Build + Codex CLI pairing, with the failure-mode catalog and script-enforced gates developed here.

---

📅 **Last Updated**: July 21, 2026
