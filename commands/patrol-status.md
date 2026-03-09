---
name: patrol-status
description: Show patrol dashboard — mode, tier, health, verification, config
---

# Patrol Status Dashboard

Run this diagnostic and present the output as a formatted dashboard:

```bash
SESSION_ID="${CLAUDE_SESSION_ID:-default}"
STATE_DIR="/tmp/patrol-${SESSION_ID}"

# Mode
MODE="watching"
TIER="off"
[ -f "$STATE_DIR/mode" ] && MODE=$(cat "$STATE_DIR/mode")
[ -f "$STATE_DIR/tier" ] && TIER=$(cat "$STATE_DIR/tier")

# Reads/Edits
READ_COUNT=0
EDIT_COUNT=0
UNREAD=0
[ -f "$STATE_DIR/reads" ] && READ_COUNT=$(wc -l < "$STATE_DIR/reads" | tr -d ' ')
[ -f "$STATE_DIR/edits" ] && EDIT_COUNT=$(wc -l < "$STATE_DIR/edits" | tr -d ' ')
if [ "$EDIT_COUNT" -gt 0 ] && [ -f "$STATE_DIR/edits" ]; then
  if [ -f "$STATE_DIR/reads" ]; then
    UNREAD=$(comm -23 <(sort -u "$STATE_DIR/edits") <(sort -u "$STATE_DIR/reads") | wc -l | tr -d ' ')
  else
    UNREAD=$EDIT_COUNT
  fi
fi

# Nudge level
NUDGE=0
[ -f "$STATE_DIR/nudge-level" ] && NUDGE=$(cat "$STATE_DIR/nudge-level" | tr -d '[:space:]')

# Verification
VERIFY_STATUS="never"
if [ -f "$STATE_DIR/verified" ]; then
  TIMESTAMP=$(cat "$STATE_DIR/verified")
  NOW=$(date +%s)
  AGO=$(( (NOW - TIMESTAMP) / 60 ))
  if [ "$AGO" -lt 1 ]; then
    VERIFY_STATUS="just now"
  else
    VERIFY_STATUS="${AGO}m ago"
  fi
fi

# Custom keywords count
CUSTOM_KW=0
if [ -f "$HOME/.patrol/config.json" ]; then
  CUSTOM_KW=$(jq -r '.custom_keywords // [] | length' "$HOME/.patrol/config.json" 2>/dev/null)
fi

# Config values
ALWAYS_ON=$(jq -r '.always_on // true' "$HOME/.patrol/config.json" 2>/dev/null || echo "true")
EASTER_EGGS=$(jq -r '.easter_eggs // false' "$HOME/.patrol/config.json" 2>/dev/null || echo "false")
THRESHOLD=$(jq -r '.band_aid_threshold // 3' "$HOME/.patrol/config.json" 2>/dev/null || echo "3")
AUTO_DETECT=$(jq -r '.auto_detect_bugfix // true' "$HOME/.patrol/config.json" 2>/dev/null || echo "true")

echo "MODE=$MODE"
echo "TIER=$TIER"
echo "READS=$READ_COUNT"
echo "EDITS=$EDIT_COUNT"
echo "UNREAD=$UNREAD"
echo "NUDGE=$NUDGE"
echo "VERIFY=$VERIFY_STATUS"
echo "CUSTOM_KW=$CUSTOM_KW"
echo "ALWAYS_ON=$ALWAYS_ON"
echo "EASTER_EGGS=$EASTER_EGGS"
echo "THRESHOLD=$THRESHOLD"
echo "AUTO_DETECT=$AUTO_DETECT"
```

Present the output as this formatted dashboard (fill in actual values):

```
╭──────────────────── Patrol ─────────────────────╮
│  Mode:     {icon} {mode description}            │
│  Tier:     {tier description}                   │
│  Health:   🛡️ 📖{reads} ✏️{edits}               │
│  Unread:   {unread} file(s) edited without read │
│  Verify:   {verify status}                      │
│  Keywords: 14 default + {custom} custom         │
│  Config:   ~/.patrol/config.json                │
├─────────────────────────────────────────────────┤
│  always_on: {val} | easter_eggs: {val}          │
│  threshold: {val} | auto_detect: {val}          │
╰─────────────────────────────────────────────────╯
```

Mode icons:
- MODE=on → `🟢 bugfix (manual)`
- MODE=auto or TIER=full → `🟢 bugfix (auto-detected)`
- MODE=watching + TIER=light → `⚪ watching (always-on light)`
- MODE=off → `🔴 disabled (/patrol-off)`
- TIER=off + no mode → `⚪ inactive`

Tier descriptions:
- full → `Full escalation (nudge → warning → STOP)`
- light → `Light (nudge only, no STOP)`
- off → `Off`

Nudge level in Health line:
- 0 → shows just the read/edit counts
- 1+ → show the nudge level label after counts

Verify status:
- "never" → `⏳ no build/test run yet`
- time value → `✅ {time}`
