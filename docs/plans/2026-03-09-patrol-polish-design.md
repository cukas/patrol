# Patrol Polish Design — Status Line, Two-Tier Model, Full Package

**Date:** 2026-03-09
**Status:** Approved

---

## Overview

Polish Patrol from a functional discipline enforcer into a visually polished, always-present developer tool. Inspired by Remembrall's status line gauge but adapted to Patrol's event-driven nature (mode indicator, not a percentage gauge).

## 1. Two-Tier Enforcement Model

### Light Mode (always-on)

- **Trigger:** Default when `always_on: true` (new config, default true)
- **Enforces:** Read-before-edit nudge (🔵) — fires once, never escalates
- **Enforces:** Build/test reminder (🔧) — same as current
- **Does NOT:** Band-aid detection, STOP gate

### Full Mode (bugfix)

- **Trigger:** Keyword auto-detection or manual `/patrol-on`
- **Enforces:** Full escalation: 🔵 nudge → 🟡 warning → 🚨 STOP
- **Enforces:** Band-aid detection, build/test reminder
- **Behavior:** Same as current Patrol v1.1.0

### State

New state file: `/tmp/patrol-{session_id}/tier` — contains `light` or `full`.
Set by `prompt-monitor.sh` when determining mode.

### Config

```json
{
  "always_on": true,
  "easter_eggs": false
}
```

When `always_on: false`, Patrol reverts to v1.1.0 behavior (silent until bugfix detected).

## 2. Status Line — Adaptive Display

### Auto-injection

`session-start.sh` appends a Patrol rendering snippet to `~/.claude/settings.json` statusLine.command on first session start. Guard: `grep -q "patrol-state"` to skip if already present. Same pattern as Remembrall's bridge.

### Data Flow

```
tool-tracker.sh (PostToolUse, async)
  → writes /tmp/patrol-{session_id}/reads, edits, nudge-level, mode, tier, verified

status line command (after each Claude response)
  → reads /tmp/patrol-{session_id}/* files
  → renders adaptive display
```

### Display States

| Tier | Nudge Level | Display | Color |
|------|-------------|---------|-------|
| Light, no edits | 0 | `🛡️` | default |
| Light, has activity | 0 | `🛡️ 📖4 ✏️2` | green (32) |
| Light, unread edits | 1 | `🛡️ 2 unread` | orange (33) |
| Full (bugfix), clean | 0 | `🛡️ bugfix · 📖4 ✏️2` | green (32) |
| Full, nudge | 1 | `🟡 bugfix · 2 unread` | orange (33) |
| Full, warning | 2 | `🟡 3 patches` | orange (33) |
| Full, STOP | 3 | `🚨 STOP` | red (31) |
| Verified | any | appends `✅` | — |
| Disabled | — | nothing | — |

### Easter Egg Variants (easter_eggs: true)

| Level | Normal | Yoda |
|-------|--------|------|
| Nudge | `🛡️ 2 unread` | `🛡️ 2 unread, hmm` |
| Warning | `🟡 3 patches` | `🟡 band-aid this is` |
| STOP | `🚨 STOP` | `🚨 investigate you must` |

### Position

Appended after Remembrall's gauge (or end of existing status line) with ` | ` separator:
```
Opus 4.6 in ~/project on main | 🔮 [████████░░] 93% | 🛡️ 📖4 ✏️2
```

## 3. `/patrol-keywords` Command

Simple keyword management — zero token cost beyond the command itself.

| Usage | Effect |
|-------|--------|
| `/patrol-keywords` | Lists all current keywords (defaults + custom) |
| `/patrol-keywords add "word1" "word2"` | Appends to custom keywords |
| `/patrol-keywords remove "word"` | Removes from custom keywords |
| `/patrol-keywords reset` | Clears custom keywords, restores defaults only |

Custom keywords **extend** defaults. Defaults stay built-in in `prompt-monitor.sh`.
Config key: `custom_keywords` (array in `~/.patrol/config.json`).

## 4. Rich `/patrol-status` Dashboard

Replaces current raw state dump:

```
╭──────────────────── Patrol ─────────────────────╮
│  Mode:     🟢 bugfix (auto-detected)            │
│  Tier:     Full escalation                       │
│  Health:   🛡️ 📖12 ✏️3                           │
│  Unread:   1 file edited without reading         │
│  Verify:   ✅ 2m ago (pnpm test)                 │
│  Keywords: 14 default + 2 custom                 │
│  Config:   ~/.patrol/config.json                 │
├─────────────────────────────────────────────────╮│
│  always_on: true | easter_eggs: false            │
│  band_aid_threshold: 3 | auto_detect_bugfix: true│
╰──────────────────────────────────────────────────╯
```

Claude command (markdown). Costs tokens only when user runs it.

## 5. Compact Startup Banner

Replace multi-line intro with:

```
🛡️ Patrol active · /patrol-help for commands
```

Status line carries the real-time info now.

## 6. Hero Image

Shield sentinel image at `docs/patrol-hero.png`.
Used at top of README.md.

## 7. Demo GIF

Created after implementation. Shows status line transitioning through states.
Placed at `docs/patrol-demo.gif`, referenced in README.md.

---

## Files to Modify

| File | Change |
|------|--------|
| `hooks/session-start.sh` | Auto-inject status line snippet + compact banner |
| `hooks/prompt-monitor.sh` | Two-tier logic (light vs full) |
| `hooks/tool-tracker.sh` | Write `tier` state file |
| `hooks/lib.sh` | Status line rendering helpers, Yoda messages, keyword merge |
| `commands/patrol-keywords.md` | New command |
| `commands/patrol-status.md` | Rewrite with rich dashboard |
| `commands/patrol-help.md` | Update with new features |
| `README.md` | Hero image, updated feature docs |

## Files Unchanged

- `hooks/hooks.json` — no new hooks needed
- `skills/diagnose/SKILL.md` — untouched
- `commands/patrol-on.md` — works as-is
- `commands/patrol-off.md` — works as-is
- `commands/patrol-config.md` — works as-is
