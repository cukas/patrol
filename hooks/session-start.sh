#!/usr/bin/env bash
# SessionStart hook: reset patrol state, inject status line, show compact banner
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
export PATROL_HOOK="session-start"
source "$SCRIPT_DIR/lib.sh"

patrol_require_jq
patrol_hook_enabled "session-start" || exit 0

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
SOURCE=$(echo "$INPUT" | jq -r '.source // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
export PATROL_CWD="$CWD"

# Check if plugin is enabled
ENABLED=$(patrol_config "enabled" "true")
[ "$ENABLED" = "false" ] && exit 0

# Reset state for this session
if [ -n "$SESSION_ID" ]; then
  STATE_DIR=$(patrol_state_dir "$SESSION_ID")
  rm -f "$STATE_DIR/reads" "$STATE_DIR/edits" "$STATE_DIR/verified" "$STATE_DIR/nudge-level" "$STATE_DIR/verify-nudged" 2>/dev/null
  echo "0" > "$STATE_DIR/nudge-level"

  # Write initial tier based on always_on config
  ALWAYS_ON=$(patrol_config "always_on" "true")
  if [ "$ALWAYS_ON" = "true" ]; then
    echo "light" > "$STATE_DIR/tier"
  else
    echo "off" > "$STATE_DIR/tier"
  fi

  # Preserve manual mode across clear/compact, reset on fresh startup
  if [ "$SOURCE" = "startup" ]; then
    rm -f "$STATE_DIR/mode" 2>/dev/null
  fi
fi

# Auto-inject status line on startup (not on clear/compact)
if [ "$SOURCE" = "startup" ]; then
  _patrol_ensure_statusline
fi

INTRO="🛡️ Patrol active · /patrol-help for commands"

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "${INTRO}"
  }
}
EOF

exit 0
