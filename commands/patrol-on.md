---
name: patrol-on
description: Force patrol mode on for this session — enables investigation gate and band-aid detection
---

# Patrol On

Run this command to activate patrol mode:

```bash
SESSION_ID="${CLAUDE_SESSION_ID:-default}"
STATE_DIR="/tmp/patrol-${SESSION_ID}"
mkdir -p "$STATE_DIR" 2>/dev/null
echo "on" > "$STATE_DIR/mode"
echo "Patrol mode activated"
```

Tell the user: "Patrol mode ON. I'll now enforce investigation before edits and detect band-aid patterns."
