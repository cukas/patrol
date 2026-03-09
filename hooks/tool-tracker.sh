#!/usr/bin/env bash
# PostToolUse hook: silently track Read/Edit/Write/Bash events
# NEVER outputs anything — zero token cost always

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
export PATROL_HOOK="tool-tracker"
source "$SCRIPT_DIR/lib.sh"

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
export PATROL_CWD="$CWD"

# Need session_id and tool_name
[ -z "$SESSION_ID" ] && exit 0
[ -z "$TOOL_NAME" ] && exit 0

# Check if enabled
ENABLED=$(patrol_config "enabled" "true")
[ "$ENABLED" = "false" ] && exit 0

# Respect disabled_hooks config
patrol_hook_enabled "tool-tracker" || exit 0

STATE_DIR=$(patrol_state_dir "$SESSION_ID")

case "$TOOL_NAME" in
  Read)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    if [ -n "$FILE_PATH" ]; then
      echo "$FILE_PATH" >> "$STATE_DIR/reads"
      patrol_debug "read tracked: $FILE_PATH"
    fi
    ;;
  Edit|Write)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    if [ -n "$FILE_PATH" ]; then
      echo "$FILE_PATH" >> "$STATE_DIR/edits"
      patrol_debug "edit tracked: $FILE_PATH"
    fi
    ;;
  Bash)
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
    if [ -n "$COMMAND" ] && [ -n "$CWD" ]; then
      VERIFY_CMDS=$(patrol_verify_commands "$CWD" 2>/dev/null)
      if [ -n "$VERIFY_CMDS" ] && [ "$VERIFY_CMDS" != "[]" ]; then
        MATCHED=$(echo "$VERIFY_CMDS" | jq -r '.[]' 2>/dev/null | while read -r cmd; do
          # Match command at start or after && / ; / | (not substring of other words)
          if echo "$COMMAND" | grep -qE "(^|&&|;|\|)\s*${cmd}(\s|$|;|&&|\|)"; then
            echo "1"
            break
          fi
        done)
        if [ "$MATCHED" = "1" ]; then
          # Atomic: clear edits before marking verified to avoid TOCTOU race
          > "$STATE_DIR/edits"
          date +%s > "$STATE_DIR/verified"
          patrol_debug "verified: $COMMAND"
        fi
      fi
    fi
    ;;
esac

exit 0
