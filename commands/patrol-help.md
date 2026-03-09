---
name: patrol-help
description: List all Patrol commands, skills, and config options
---

# Patrol Help

Show the user this reference:

## Commands

| Command | Description |
|---------|-------------|
| `/patrol-on` | Force full patrol mode on for this session |
| `/patrol-off` | Disable patrol mode for this session |
| `/patrol-status` | Dashboard — mode, tier, health, verification, config |
| `/patrol-keywords` | Manage custom trigger keywords (list/add/remove/reset) |
| `/patrol-config` | Show/edit configuration |
| `/patrol-help` | This help |

## Skills

| Skill | Description |
|-------|-------------|
| `/diagnose` | Structured root-cause investigation — trace, hypothesize, verify, then fix |

## How It Works

```
Two-tier enforcement:

  Light mode (always-on)           → read-before-edit nudge + build/test reminder
  Full mode (bugfix keyword/manual) → full escalation + band-aid detection + STOP gate

  Status line (real-time):
    🛡️                              → watching, no activity
    🛡️ 📖4 ✏️2                      → healthy: 4 files read, 2 edited
    🛡️ bugfix · 📖4 ✏️2             → bugfix mode, healthy
    🟡 2 unread                     → warning: edits without reads
    🚨 STOP                         → hard stop: investigate now
    ✅                              → build/test verified
```

## Config

**Global:** `~/.patrol/config.json`
**Per-project:** `.patrol/config.json` (overrides global)

| Setting | Default | Description |
|---------|---------|-------------|
| `enabled` | `true` | Enable/disable patrol |
| `always_on` | `true` | Light mode active even without bugfix keywords |
| `auto_detect_bugfix` | `true` | Auto-detect bug-fix sessions from keywords |
| `custom_keywords` | `[]` | Additional trigger keywords (extend defaults) |
| `band_aid_threshold` | `3` | Edits before warning in full mode |
| `verify_commands` | `"auto"` | Build/test commands (or auto-detect) |
| `easter_eggs` | `false` | Yoda-themed messages |
| `debug` | `false` | Debug logging to ~/.patrol/debug.log |
