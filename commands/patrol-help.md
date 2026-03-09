---
name: patrol-help
description: List all Patrol commands, skills, and config options
---

# Patrol Help

Show the user this reference:

## Commands

| Command | Description |
|---------|-------------|
| `/patrol-on` | Force patrol mode on for this session |
| `/patrol-off` | Disable patrol mode for this session |
| `/patrol-status` | Diagnostic — show mode, tracking state, config |
| `/patrol-config` | Show/edit config |
| `/patrol-help` | This help |

## Skills

| Skill | Description |
|-------|-------------|
| `/diagnose` | Structured root-cause investigation — trace, hypothesize, verify, then fix |

## How It Works

```
Normal coding                    → silent (zero tokens)
Bug-fix detected (auto/manual)   → investigation gate active
  Edit without Read              → nudge
  3+ edits without investigation → warning
  4+ consecutive patches         → STOP
Files changed, no build/test     → reminder
```

## Config

**Global:** `~/.patrol/config.json`
**Per-project:** `.patrol/config.json` (overrides global)
**Auto-detect:** Package manager (pnpm > yarn > npm), project type (Cargo, pytest, go, make)

| Setting | Default | Description |
|---------|---------|-------------|
| `enabled` | `true` | Enable/disable patrol |
| `auto_detect_bugfix` | `true` | Auto-detect bug-fix sessions |
| `keywords` | `["fix","bug",...]` | Trigger keywords |
| `band_aid_threshold` | `3` | Edits before warning |
| `verify_commands` | `"auto"` | Build/test commands |
| `debug` | `false` | Debug logging |
