# Patrol

*"Investigate, you must. Band-aid, you must not."*

**Claude jumps to fixes before understanding the problem.** Patrol stops that.

### Install

```bash
claude plugin marketplace add cukas/patrol
claude plugin install patrol@cukas
```

That's it. Zero setup. Patrol monitors Claude's development discipline automatically.

```
Normal coding                    → silent (zero tokens)
Bug-fix detected (auto/manual)   → investigation gate active
  Edit without Read              → 🔵 Patrol: 1 file edited without being read first
  3+ patches without reading     → 🟡 Patrol: 3 consecutive patches. Step back and trace the code path.
  4+ patches, no investigation   → 🚨 PATROL: STOP. Read the files. Trace the root cause. NOW.
Files changed, no build/test     → 🔧 Patrol: 5 files changed, no build/test run yet.
```

---

## How It Works

> **Zero cost by default.** Patrol is completely silent during normal coding. It only speaks up when Claude starts patching without investigating — and then it escalates.

```
┌──────────────────────────────────────────────────────────────────────┐
│                         Claude Code Session                          │
│                                                                      │
│  PostToolUse ─── tool-tracker.sh (async, silent)                     │
│       │                                                              │
│       │          Tracks Read/Edit/Write/Bash → /tmp/patrol-{sid}/    │
│       │            reads: files Claude has read                      │
│       │            edits: files Claude has edited                    │
│       │            verified: timestamp of last build/test run        │
│       │                                                              │
│  UserPromptSubmit ─── prompt-monitor.sh                              │
│       │                                                              │
│       │          Reads state files, checks user message              │
│       │                    │                                         │
│       │          Bug-fix mode? ──── no ──── Check build/test only    │
│       │               │                           │                  │
│       │              yes                    >=3 edits, no verify?     │
│       │               │                           │                  │
│       │      Unread edits? ──┐                 🔧 remind             │
│       │          │           │                                       │
│       │       1 file      3 files     4+ files                       │
│       │          │           │           │                            │
│       │       🔵 nudge   🟡 warn    🚨 STOP                         │
│       │                                                              │
│  SessionStart ─── session-start.sh                                   │
│       │                                                              │
│       │          Resets state, injects intro message                  │
│       │          Preserves manual mode across clear/compact           │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

## Three Layers of Protection

1. **Investigation Gate** — Detects bug-fix sessions automatically from keywords (`fix`, `bug`, `broken`, `error`, `crash`, `doesn't work`, `not working` — plus German and French equivalents) or manually via `/patrol-on`. Tracks which files Claude reads vs edits. If Claude starts editing without reading, escalating warnings fire.

2. **Band-Aid Detector** — Counts consecutive edits without investigation. After the configurable threshold (default 3), warns Claude to stop patching and trace the root cause. At 4+ patches with no investigation, issues a hard STOP.

3. **Build/Test Reminder** — Tracks if build/test commands have been run after edits. Auto-detects package manager (`pnpm` > `yarn` > `npm`) and project type (Cargo, pytest, go, make). Reminds when 3+ files changed without verification.

---

<details>
<summary><strong>Full documentation</strong></summary>

## Installation

### Install

```bash
claude plugin marketplace add cukas/patrol
claude plugin install patrol@cukas
```

Run `/patrol-status` to verify.

## Configuration

Patrol uses two config layers — global and per-project:

**Global:** `~/.patrol/config.json`
**Per-project:** `.patrol/config.json` (in project root — overrides global)

```json
{
  "enabled": true,
  "auto_detect_bugfix": true,
  "keywords": ["fix", "bug", "broken", "error", "crash", "doesn't work", "not working", "Fehler", "kaputt", "Absturz", "funktioniert nicht", "erreur", "plantage", "cassé", "ne marche pas"],
  "band_aid_threshold": 3,
  "verify_commands": "auto",
  "escalation": "siren",
  "disabled_hooks": [],
  "debug": false
}
```

| Setting | Default | Description |
|---------|---------|-------------|
| `enabled` | `true` | Enable/disable Patrol globally |
| `auto_detect_bugfix` | `true` | Auto-detect bug-fix sessions from keywords in user messages |
| `keywords` | `["fix","bug","broken","error","crash","doesn't work","not working","Fehler","kaputt","Absturz","funktioniert nicht","erreur","plantage","cassé","ne marche pas"]` | Keywords that trigger bug-fix mode (EN/DE/FR) |
| `band_aid_threshold` | `3` | Consecutive edits before escalating to warning level |
| `verify_commands` | `"auto"` | Build/test commands to detect, or `"auto"` to auto-detect from project files |
| `escalation` | `"siren"` | Escalation style |
| `disabled_hooks` | `[]` | Hooks to disable by name (e.g., `["tool-tracker"]`) |
| `debug` | `false` | Enable debug logging to `~/.patrol/debug.log` |

Settings apply globally — once configured, all Claude sessions respect them. Per-project config takes priority for any key it defines.

## Commands

| Command | Description |
|---------|-------------|
| `/patrol-on` | Force patrol mode on for this session — enables investigation gate and band-aid detection |
| `/patrol-off` | Disable patrol mode for this session (auto-detection still applies unless disabled in config) |
| `/patrol-status` | Diagnostic — show mode, tracked reads/edits, nudge level, verification status, config |
| `/patrol-config` | Show/edit configuration — lists all settings with current values |
| `/patrol-help` | Quick reference for all commands, skills, escalation levels, and config options |

## Skills

| Skill | Description |
|-------|-------------|
| `/diagnose` | Structured root-cause investigation protocol — trace the call chain, form hypotheses, verify, then fix. Prevents code changes until the protocol is complete. |

The `/diagnose` skill enforces a six-step protocol:

1. **Understand the symptom** — expected vs actual behavior, reproduction conditions
2. **Trace the code path** — read every file in the call chain, entry point to bug
3. **Form a hypothesis** — root cause, supporting evidence, what would disprove it
4. **Verify the hypothesis** — gather more evidence until confidence is HIGH
5. **Present analysis** — root cause, evidence, proposed fix, risk assessment
6. **Implement and verify** — minimal fix, run build/test, confirm resolution

## Auto-Detection

Patrol auto-detects your project's verification commands:

**Package manager** (priority order):
1. `pnpm-lock.yaml` found → `pnpm`
2. `yarn.lock` found → `yarn`
3. `package-lock.json` found → `npm`

**Project type:**

| File | Commands detected |
|------|-------------------|
| `package.json` (with `test` script) | `{pkg_mgr} test` |
| `package.json` (with `build` script) | `{pkg_mgr} run build` |
| `Cargo.toml` | `cargo test`, `cargo build` |
| `pyproject.toml` or `setup.py` | `pytest` |
| `go.mod` | `go test ./...` |
| `Makefile` (with `test:` target) | `make test` |

Override with `verify_commands` in config:

```json
{
  "verify_commands": ["pnpm test", "pnpm run build"]
}
```

## Escalation System

Patrol uses a progressive escalation model. Each level fires at most once per session — no repeated nagging.

| Level | Trigger | Message |
|-------|---------|---------|
| Silent | Normal coding, no bug-fix mode | Nothing — zero tokens |
| Nudge | 1+ files edited without being read first | 🔵 `Patrol: N file(s) edited without being read first` |
| Warning | 3+ consecutive patches with minimal reads | 🟡 `Patrol: N consecutive patches. Step back and trace the code path.` |
| STOP | 4+ patches, no investigation | 🚨 `PATROL: STOP. Read the files. Trace the root cause. NOW.` |
| Verify | 3+ files changed, no build/test run | 🔧 `Patrol: N files changed, no build/test run yet.` |

Escalation only increases — once you hit warning level, a nudge won't fire again. The verify reminder operates independently from the investigation gate.

## Token Budget

| Scenario | Token cost |
|----------|-----------|
| Normal coding (no bug-fix keywords) | **0 tokens** — tool-tracker runs async and silent, prompt-monitor exits without output |
| Bug-fix mode, Claude investigates properly | **0 tokens** — reads before edits, no warnings triggered |
| Bug-fix mode, Claude skips investigation | ~30-50 tokens per warning (fires once per level) |
| Session start | ~50 tokens for the intro message |
| Build/test reminder | ~20 tokens (fires once per edit batch) |

## State Files

Patrol stores per-session state in `/tmp/patrol-{session_id}/`:

```
/tmp/patrol-{session_id}/
  reads       # file paths Claude has read (one per line)
  edits       # file paths Claude has edited (one per line)
  verified    # timestamp of last build/test run
  nudge-level # current escalation level (0-3)
  verify-nudged # edit count at last verify reminder
  mode        # manual mode override ("on" or "off")
```

State is reset on session start. Manual mode is preserved across `/clear` and `/compact` but reset on fresh `startup`.

## Requirements

- Claude Code with plugin support
- `jq` — required; hooks exit gracefully if missing but will not function

### Platform Support

| Platform | Status |
|----------|--------|
| macOS | Fully supported |
| Linux | Fully supported |
| WSL (Windows Subsystem for Linux) | Fully supported (uses Linux userspace) |
| Windows (native) | Not supported — use WSL |

## Debug Logging

Enable debug logging to troubleshoot hook behavior:

```bash
# Via config (persistent)
mkdir -p ~/.patrol
echo '{"debug": true}' | jq . > ~/.patrol/config.json

# Via environment (one-off)
PATROL_DEBUG=1 claude
```

Logs are written to `~/.patrol/debug.log` with ISO timestamps and hook names. The log is auto-rotated at 1MB. Each hook identifies itself in log entries (e.g., `[tool-tracker]`, `[prompt-monitor]`, `[session-start]`).

## Troubleshooting

**`jq` not installed** — Hooks exit silently without `jq`. Run `jq --version` to check. Install via `brew install jq` (macOS) or `sudo apt-get install jq` (Linux).

**Patrol doesn't activate on bug-fix messages** — Check that `auto_detect_bugfix` is `true` in config. Verify your message contains one of the trigger keywords. Run `/patrol-status` to see current mode and config.

**Warnings don't escalate** — Escalation only increases within a session. If the nudge level is already at the current threshold, no new warning fires. Check `/patrol-status` for the current nudge level.

**Build/test reminder fires for the wrong command** — Override auto-detection by setting `verify_commands` in your config to an explicit list of commands.

**Hooks don't seem to be running** — Verify `jq --version` returns a version. Check that the plugin is installed: `claude plugin list`. Enable debug logging and check `~/.patrol/debug.log` for hook activity.

**State persists after restarting Claude** — State files live in `/tmp/` and are cleared on reboot. For immediate reset, start a new session or use `/patrol-status` to inspect state.

**Want to disable a specific hook** — Add the hook name to `disabled_hooks` in config: `{"disabled_hooks": ["tool-tracker"]}`. Valid names: `tool-tracker`, `prompt-monitor`, `session-start`.

## FAQ

**Does Patrol bloat my context?** No. During normal operation, Patrol uses exactly zero tokens. The tool-tracker hook runs asynchronously and never produces output. The prompt-monitor only injects a message when it detects a problem — and each warning fires at most once per escalation level.

**What triggers bug-fix mode?** Two things: keywords in your message (like "fix", "bug", "crash") that are auto-detected, or manually running `/patrol-on`. You can customize the keyword list via config.

**Can I customize the trigger keywords?** Yes. Set `keywords` in `~/.patrol/config.json` or `.patrol/config.json`:

```json
{
  "keywords": ["fix", "bug", "broken", "error", "crash", "regression", "failing"]
}
```

**Does Patrol work alongside Remembrall?** Yes. They complement each other — Remembrall manages context lifecycle, Patrol enforces investigation discipline. They use separate state directories and hooks with no conflicts.

**Can I use Patrol in CI or automated pipelines?** Patrol is designed for interactive Claude Code sessions. In CI, there's no user prompt to trigger keyword detection. You could force it on with `/patrol-on`, but the primary value is in interactive development.

**How do I reset patrol state mid-session?** Run `/patrol-off` then `/patrol-on` to reset the manual mode. State files (reads, edits, nudge level) are reset on each session start automatically.

## Privacy

Patrol is fully local. It does not collect, transmit, or store any data outside your machine.

- State files are stored in `/tmp/patrol-{session_id}/` and cleared on reboot
- Config is stored in `~/.patrol/config.json` on your local filesystem
- Debug logs are stored in `~/.patrol/debug.log` locally
- No network requests, no analytics, no telemetry
- No external services or APIs are contacted
- All processing happens in local shell scripts

## License

MIT

</details>
