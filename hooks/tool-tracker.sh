#!/usr/bin/env bash
# PostToolUse hook: track tool events + evaluate rules
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
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# ── Track tool usage (same as v2) ──

case "$TOOL_NAME" in
  Read)
    [ -n "$FILE_PATH" ] && patrol_append_capped "$STATE_DIR/reads" "$FILE_PATH"
    patrol_debug "read tracked: $FILE_PATH"
    ;;
  Edit|Write|MultiEdit)
    [ -n "$FILE_PATH" ] && patrol_append_capped "$STATE_DIR/edits" "$FILE_PATH"
    patrol_debug "edit tracked: $FILE_PATH"
    ;;
  Bash)
    if [ -n "$COMMAND" ] && [ -n "$CWD" ]; then
      VERIFY_CMDS=$(patrol_verify_commands "$CWD" 2>/dev/null)
      if [ -n "$VERIFY_CMDS" ] && [ "$VERIFY_CMDS" != "[]" ]; then
        MATCHED=$(echo "$VERIFY_CMDS" | jq -r '.[]' 2>/dev/null | while read -r cmd; do
          if echo "$COMMAND" | grep -qE "(^|&&|;|\|)\s*${cmd}(\s|$|;|&&|\|)"; then
            echo "1"
            break
          fi
        done)
        if [ "$MATCHED" = "1" ]; then
          > "$STATE_DIR/edits"
          date +%s > "$STATE_DIR/verified"
          patrol_debug "verified: $COMMAND"
        fi
      fi
    fi
    # Track bash commands for require checks
    [ -n "$COMMAND" ] && patrol_append_capped "$STATE_DIR/bash_history" "$COMMAND"
    ;;
esac

# ── Evaluate rules ──

RULES_CACHE="$STATE_DIR/rules.json"
[ -f "$RULES_CACHE" ] || exit 0

# Check each rule's trigger
while IFS= read -r rule; do
  rule_id=$(echo "$rule" | jq -r '.id')
  enabled=$(echo "$rule" | jq -r '.enabled // true')
  [ "$enabled" = "false" ] && continue

  # Check trigger
  if echo "$rule" | patrol_check_trigger "$TOOL_NAME" "$FILE_PATH" "$COMMAND"; then
    # Trigger matched — check require (if any)
    require_type=$(echo "$rule" | jq -r '.require.type // empty')
    violated=false

    if [ -z "$require_type" ]; then
      # No require — trigger alone means violation (for bash_command/tool_use direct rules)
      violated=true
    else
      case "$require_type" in
        bash_ran)
          require_match=$(echo "$rule" | jq -r '.require.match // empty')
          [ -z "$require_match" ] && { violated=false; break; }
          if [ -f "$STATE_DIR/bash_history" ] && grep -qE "$require_match" "$STATE_DIR/bash_history"; then
            violated=false
          else
            violated=true
          fi
          ;;
        file_read)
          if [ -n "$FILE_PATH" ]; then
            if patrol_check_sequence "$STATE_DIR" "$FILE_PATH"; then
              violated=true
            else
              violated=false
            fi
          fi
          ;;
        *)
          violated=false
          ;;
      esac
    fi

    if [ "$violated" = "true" ]; then
      patrol_debug "violation: $rule_id ($(echo "$rule" | jq -r '.level'))"
      echo "$rule" | jq -c --arg tool "$TOOL_NAME" --arg file "$FILE_PATH" \
        '{rule_id: .id, level: .level, message: .message, tool: $tool, file: $file, timestamp: now}' \
        >> "$STATE_DIR/violations.jsonl"

      # Record in adaptive history (if enabled)
      ADAPTIVE_ENABLED=$(patrol_config "adaptive" "true")
      if [ "$ADAPTIVE_ENABLED" = "true" ]; then
        case "$rule_id" in _safety-*) ;; *)
          patrol_adaptive_record_violation "$rule_id"
          ;;
        esac
      fi
    fi
  fi
done < <(jq -c '.[]' "$RULES_CACHE" 2>/dev/null)

exit 0
