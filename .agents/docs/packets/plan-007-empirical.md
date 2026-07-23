# Plan 007 empirical probe log

Probe base: C:\Users\sorab\AppData\Local\Temp\grok-orch-007-b3c74558
Host: Windows 11
Date: 2026-07-23

## Versions
- codex: codex-cli 0.145.0 (PATH); with helper PATH prepend → 0.145.0-alpha.30
- grok: 0.2.111 (94172f2aa4) [stable]
- agy: 1.1.5
- claude: 2.1.218 (Claude Code)
- gemini: NOT INSTALLED

## Marker write probes (disposable cwd)

| Runtime | Mode under test | Marker created? | Enforced? | Evidence |
|---------|-----------------|-----------------|-----------|----------|
| codex | exec -s read-only (no helper PATH) | NO | fail-closed shell (not usable RO worker) | helper program not found; WRITE_BLOCKED |
| codex | exec -s read-only (helper on PATH) | NO | YES (sandbox reject) | writing is blocked by read-only sandbox |
| grok | --sandbox read-only | YES (PROBE_OK) | NO on Windows | OS sandbox docs: Linux/macOS only |
| grok | --disallowed-tools search_replace,run_terminal_cmd,run_terminal_command | YES | incomplete denylist (cause not fully identified) | still wrote |
| grok | --tools read_file,grep,list_dir | NO | YES (tool allowlist) | WRITE_BLOCKED |
| grok | --deny Write(**) Edit(**) Bash(**) | NO | YES (permission deny rules) | WRITE_BLOCKED |
| claude | --permission-mode plan + disallowed Edit,Write,NotebookEdit | NO | YES | WRITE_BLOCKED |
| claude | --tools Read,Grep,Glob,LS | NO | YES | WRITE_BLOCKED |
| agy | --sandbox --mode plan | YES | NO | PROBE_OK |
| agy | --mode plan | YES | NO | PROBE_OK |
| agy | --sandbox | YES | NO | PROBE_OK |

## Supplemental I/O / exit samples (same session, not marker probes)

| Check | Result |
|-------|--------|
| codex exec --not-a-real-flag | exit 2 |
| codex blocked write (helper on) | process exit 0 + text WRITE_BLOCKED; marker absent |
| grok -p with --sandbox not-a-profile | still answered; exit 0 |
| claude -p --permission-mode not-a-mode | exit 1 (invalid choice) |
| claude stdin: `"say only HI" \| claude -p --output-format text --max-turns 1` | printed HI; exit 0 |

## Headless surface (from --help + samples above)

- codex: stdin or arg prompt; -C cwd; -o last message; sandbox read-only|workspace-write|danger-full-access
- grok: -p/--prompt-file/--prompt-json; --cwd; --sandbox PROFILE; --tools / --disallowed-tools; --deny/--allow
- claude: -p print; prompt arg or stdin; permission-mode; --tools / --disallowedTools; process cwd
- agy: -p/--print; --print-timeout; --sandbox; --mode accept-edits|plan

## Docs cited (local + public where known)
- Grok sandbox local: ~/.grok/docs/user-guide/18-sandbox.md (Platform Support: Linux Landlock, macOS Seatbelt; Windows not listed)
- Grok headless local: ~/.grok/docs/user-guide/14-headless-mode.md
