---
name: patrol-config
description: Show or edit patrol configuration
---

# Patrol Config

Show the current config and help the user modify it:

**Global config:** `~/.patrol/config.json`
**Project override:** `.patrol/config.json` (in project root)

| Setting | Default | Description |
|---------|---------|-------------|
| `enabled` | `true` | Enable/disable patrol globally |
| `auto_detect_bugfix` | `true` | Auto-detect bug-fix sessions from keywords |
| `keywords` | `["fix","bug","broken","error","crash","doesn't work","not working"]` | Keywords that trigger bug-fix mode |
| `band_aid_threshold` | `3` | Consecutive edits before escalating to warning |
| `verify_commands` | `"auto"` | Build/test commands (or "auto" to detect) |
| `escalation` | `"siren"` | Escalation style |
| `disabled_hooks` | `[]` | Hooks to disable (e.g., `["tool-tracker"]`) |
| `debug` | `false` | Enable debug logging to `~/.patrol/debug.log` |

To modify, ask the user what they'd like to change, then update the appropriate config file.

Example:
```bash
# Set globally
mkdir -p ~/.patrol
echo '{"verify_commands": ["pnpm test", "pnpm run build"]}' | jq . > ~/.patrol/config.json

# Set per-project
mkdir -p .patrol
echo '{"verify_commands": ["cargo test"]}' | jq . > .patrol/config.json
```
