---
name: patrol-off
description: Disable patrol mode for this session
---

# Patrol Off

Run this command to deactivate patrol mode:

```bash
SESSION_ID="${CLAUDE_SESSION_ID:-default}"
STATE_DIR="/tmp/patrol-${SESSION_ID}"
mkdir -p "$STATE_DIR" 2>/dev/null
echo "off" > "$STATE_DIR/mode"
echo "Patrol mode deactivated"
```

Tell the user: "Patrol mode OFF for this session. Auto-detection still applies unless disabled in config."
