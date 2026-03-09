---
name: patrol-status
description: Show current patrol state — mode, tracked reads/edits, verification status
---

# Patrol Status

Run this diagnostic and show the output to the user:

```bash
SESSION_ID="${CLAUDE_SESSION_ID:-default}"
STATE_DIR="/tmp/patrol-${SESSION_ID}"

echo "=== Patrol Status ==="
echo ""

# Mode
MODE="auto-detect"
[ -f "$STATE_DIR/mode" ] && MODE=$(cat "$STATE_DIR/mode")
echo "Mode: $MODE"

# Reads
READ_COUNT=0
[ -f "$STATE_DIR/reads" ] && READ_COUNT=$(wc -l < "$STATE_DIR/reads" | tr -d ' ')
echo "Files read: $READ_COUNT"

# Edits
EDIT_COUNT=0
[ -f "$STATE_DIR/edits" ] && EDIT_COUNT=$(wc -l < "$STATE_DIR/edits" | tr -d ' ')
echo "Files edited: $EDIT_COUNT"

# Unread edits
if [ "$EDIT_COUNT" -gt 0 ] && [ -f "$STATE_DIR/edits" ]; then
  if [ -f "$STATE_DIR/reads" ]; then
    UNREAD=$(comm -23 <(sort -u "$STATE_DIR/edits") <(sort -u "$STATE_DIR/reads") | wc -l | tr -d ' ')
  else
    UNREAD=$EDIT_COUNT
  fi
  echo "Edits without prior read: $UNREAD"
fi

# Nudge level
NUDGE=0
[ -f "$STATE_DIR/nudge-level" ] && NUDGE=$(cat "$STATE_DIR/nudge-level")
case $NUDGE in
  0) echo "Escalation level: silent" ;;
  1) echo "Escalation level: nudge" ;;
  2) echo "Escalation level: warning" ;;
  3) echo "Escalation level: STOP" ;;
  *) echo "Escalation level: $NUDGE" ;;
esac

# Verification
if [ -f "$STATE_DIR/verified" ]; then
  TIMESTAMP=$(cat "$STATE_DIR/verified")
  echo "Last verified: $(date -r "$TIMESTAMP" '+%H:%M:%S' 2>/dev/null || echo "$TIMESTAMP")"
else
  echo "Last verified: never"
fi

# Config
echo ""
echo "=== Config ==="
if [ -f "$HOME/.patrol/config.json" ]; then
  cat "$HOME/.patrol/config.json" | jq .
else
  echo "(no global config — using defaults)"
fi

if [ -f ".patrol/config.json" ]; then
  echo ""
  echo "Project override:"
  cat ".patrol/config.json" | jq .
fi
```
