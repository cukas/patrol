# Patrol — Plugin Design

*Development discipline enforcement for Claude Code. Stop band-aiding. Investigate first.*

## Problem

Claude Code's #1 anti-pattern: jumping to fixes before investigating the root cause. CLAUDE.md rules help but aren't enforced — Claude still violates them. Patrol uses hooks to detect and prevent this in real-time, at the tool level.

## Architecture

```
~/.patrol/config.json              ← Global defaults
.patrol/config.json                ← Per-project overrides (wins when present)
/tmp/patrol-{session_id}/          ← Session state (zero-cost tracking)
    mode                           ← "auto" | "manual" | "off"
    reads                          ← files Read this session
    edits                          ← files Edited this session
    verified                       ← timestamp of last build/test run
    nudge-level                    ← 0, 1, 2 (escalation state)
```

## Hooks

| Hook Event | Script | Purpose | Token cost |
|---|---|---|---|
| SessionStart | session-start.sh | Inject Patrol intro, reset state | ~20 tokens once |
| UserPromptSubmit | prompt-monitor.sh | Bug-fix detection, edit/read ratio check, verify check | 0 when clean |
| PostToolUse | tool-tracker.sh | Track Read/Edit/Bash calls to /tmp | Always 0 (no output) |

### PostToolUse (tool-tracker.sh) — Silent, never outputs anything

- Edit/Write → append file path to `/tmp/patrol-{sid}/edits`
- Read → append file path to `/tmp/patrol-{sid}/reads`
- Bash containing configured build/test command → write timestamp to `/tmp/patrol-{sid}/verified`, clear edits

### UserPromptSubmit (prompt-monitor.sh) — The brain

1. Check mode (auto-detect keywords or manual flag)
2. If bug-fix mode active:
   - Compare edits vs reads → escalating warnings if editing without reading
   - Check consecutive edit count → band-aid detection
3. Check edits-since-last-verify → reminder if files changed but no build/test
4. Deduplicate nudges (don't repeat same level)

## Escalation (bug-fix mode)

```
Level 0: No edits yet or reads > edits          → silent
Level 1: 1-2 edits without reads                → 🔵 nudge
Level 2: 3+ edits without reading other files    → 🟡 warning
Level 3: 4+ consecutive patches same area        → 🚨 STOP
```

Reset: Reading a new file resets level by 1. Running build/test resets verify state.

## Config

### Global (~/.patrol/config.json)

```json
{
  "enabled": true,
  "auto_detect_bugfix": true,
  "keywords": ["fix", "bug", "broken", "error", "crash", "doesn't work", "not working"],
  "band_aid_threshold": 3,
  "verify_commands": "auto",
  "escalation": "siren",
  "debug": false
}
```

### Per-project (.patrol/config.json) — overrides global

```json
{
  "verify_commands": ["pnpm build:electron", "pnpm test"],
  "keywords": ["fix", "bug", "silent", "glitch", "crash"]
}
```

### Auto-detection for verify_commands: "auto"

Package manager priority: pnpm-lock.yaml → yarn.lock → package-lock.json → npm fallback
Project type: Cargo.toml → pyproject.toml → go.mod → Makefile

## Skills

| Skill | Trigger | Purpose |
|---|---|---|
| diagnose | /diagnose | Structured root-cause investigation protocol |
| patrol-config | /patrol-config | Show/edit config |
| patrol-help | /patrol-help | Reference |

## Commands

| Command | Purpose |
|---|---|
| /patrol on | Force patrol mode on |
| /patrol off | Disable for this session |
| /patrol status | Show current tracking state |

## Plugin File Structure

```
patrol/
├── .claude-plugin/
│   ├── plugin.json
│   └── marketplace.json
├── hooks/
│   ├── hooks.json
│   ├── session-start.sh
│   ├── prompt-monitor.sh
│   ├── tool-tracker.sh
│   └── lib.sh
├── skills/
│   └── diagnose/
│       └── SKILL.md
├── commands/
│   ├── patrol-on.md
│   ├── patrol-off.md
│   ├── patrol-status.md
│   ├── patrol-config.md
│   └── patrol-help.md
├── README.md
└── LICENSE
```

## Token Budget

| Scenario | Tokens |
|---|---|
| Normal coding, no bugs | 0 |
| Bug-fix, investigating properly | 0 |
| Bug-fix, editing without reading | ~30 (one nudge) |
| Forgot to build/test | ~20 (one reminder) |
| Session start | ~20 (one-time intro) |
