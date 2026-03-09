#!/usr/bin/env bash
# SessionStart hook: reset patrol state and inject discipline intro
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

  # Preserve manual mode across clear/compact, reset on fresh startup
  if [ "$SOURCE" = "startup" ]; then
    rm -f "$STATE_DIR/mode" 2>/dev/null
  fi
fi

INTRO="Patrol is active. It monitors your development discipline:\\n- Detects bug-fix sessions automatically (or use /patrol-on)\\n- Warns if you edit files without reading them first\\n- Warns if you apply successive patches without investigating\\n- Reminds you to run build/test after making changes\\nUse /patrol-help for commands. Zero token cost when you're working properly."

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "${INTRO}"
  }
}
EOF

exit 0
