#!/usr/bin/env bash
# UserPromptSubmit hook: the brain of Patrol
# Checks investigation state and verify state, injects escalating warnings
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
export PATROL_HOOK="prompt-monitor"
source "$SCRIPT_DIR/lib.sh"

patrol_require_jq
patrol_hook_enabled "prompt-monitor" || exit 0

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
USER_MESSAGE=$(echo "$INPUT" | jq -r '.user_message // empty')
export PATROL_CWD="$CWD"

[ -z "$SESSION_ID" ] && exit 0

ENABLED=$(patrol_config "enabled" "true")
[ "$ENABLED" = "false" ] && exit 0

STATE_DIR=$(patrol_state_dir "$SESSION_ID")

# ─── Determine patrol mode and tier ──────────────────────────
MODE="off"
TIER="off"
MANUAL_MODE=""
[ -f "$STATE_DIR/mode" ] && MANUAL_MODE=$(cat "$STATE_DIR/mode" 2>/dev/null)

if [ "$MANUAL_MODE" = "on" ]; then
  MODE="on"
  TIER="full"
elif [ "$MANUAL_MODE" = "off" ]; then
  MODE="off"
  TIER="off"
else
  # Check for keyword-triggered full mode
  AUTO_DETECT=$(patrol_config "auto_detect_bugfix" "true")
  if [ "$AUTO_DETECT" = "true" ] && [ -n "$USER_MESSAGE" ]; then
    KEYWORDS=$(patrol_merged_keywords)
    MSG_LOWER=$(echo "$USER_MESSAGE" | tr '[:upper:]' '[:lower:]')
    KEYWORD_MATCH=""
    while read -r kw; do
      kw_lower=$(echo "$kw" | tr '[:upper:]' '[:lower:]')
      if echo "$kw_lower" | grep -q ' '; then
        if echo "$MSG_LOWER" | grep -qF "$kw_lower"; then
          KEYWORD_MATCH="1"
          break
        fi
      else
        if echo "$MSG_LOWER" | grep -qwF "$kw_lower"; then
          KEYWORD_MATCH="1"
          break
        fi
      fi
    done < <(echo "$KEYWORDS" | jq -r '.[]' 2>/dev/null)
    if [ "$KEYWORD_MATCH" = "1" ]; then
      MODE="auto"
      TIER="full"
      patrol_debug "bug-fix mode auto-activated by keyword match"
    fi
  fi

  # If no keyword match, check always_on for light mode
  if [ "$TIER" = "off" ]; then
    ALWAYS_ON=$(patrol_config "always_on" "true")
    if [ "$ALWAYS_ON" = "true" ]; then
      MODE="light"
      TIER="light"
    fi
  fi
fi

# Write tier to state file (for status line to read)
echo "$TIER" > "$STATE_DIR/tier"

patrol_debug "mode=$MODE tier=$TIER manual=$MANUAL_MODE"

# ─── Read state ──────────────────────────────────────────────
EDIT_COUNT=0
READ_COUNT=0
UNREAD_EDIT_COUNT=0
NUDGE_LEVEL=0

[ -f "$STATE_DIR/edits" ] && EDIT_COUNT=$(wc -l < "$STATE_DIR/edits" | tr -d ' ')
[ -f "$STATE_DIR/reads" ] && READ_COUNT=$(wc -l < "$STATE_DIR/reads" | tr -d ' ')
if [ -f "$STATE_DIR/nudge-level" ]; then
  _nl=$(cat "$STATE_DIR/nudge-level" | tr -d '[:space:]')
  [[ "$_nl" =~ ^[0-9]+$ ]] && NUDGE_LEVEL=$_nl
fi

# Count edits to files that weren't read first
if [ "$EDIT_COUNT" -gt 0 ] && [ -f "$STATE_DIR/edits" ]; then
  if [ -f "$STATE_DIR/reads" ]; then
    UNREAD_EDIT_COUNT=$(comm -23 <(sort -u "$STATE_DIR/edits") <(sort -u "$STATE_DIR/reads") | wc -l | tr -d ' ')
  else
    UNREAD_EDIT_COUNT=$EDIT_COUNT
  fi
fi

patrol_debug "edits=$EDIT_COUNT reads=$READ_COUNT unread_edits=$UNREAD_EDIT_COUNT nudge=$NUDGE_LEVEL"

# ─── Check 0: V3 Rule violations ──────────────────────────────
# Process violations written by tool-tracker's rule evaluation
VIOLATIONS_FILE="$STATE_DIR/violations.jsonl"
if [ -f "$VIOLATIONS_FILE" ] && [ -s "$VIOLATIONS_FILE" ]; then
  # Read violations and group by level
  BLOCK_MSGS=""
  WARN_MSGS=""
  INFORM_MSGS=""

  while IFS= read -r violation; do
    v_level=$(echo "$violation" | jq -r '.level // empty' 2>/dev/null) || continue
    v_message=$(echo "$violation" | jq -r '.message // empty' 2>/dev/null) || continue
    v_rule_id=$(echo "$violation" | jq -r '.rule_id // empty' 2>/dev/null) || continue
    [ -z "$v_level" ] && continue
    [ -z "$v_message" ] && continue

    case "$v_level" in
      block)
        BLOCK_MSGS="${BLOCK_MSGS}$(printf '🚫 [%s] %s\n' "$v_rule_id" "$v_message")"
        ;;
      warn)
        WARN_MSGS="${WARN_MSGS}$(printf '⚠️ [%s] %s\n' "$v_rule_id" "$v_message")"
        ;;
      inform)
        INFORM_MSGS="${INFORM_MSGS}$(printf 'ℹ️ [%s] %s\n' "$v_rule_id" "$v_message")"
        ;;
    esac
  done < "$VIOLATIONS_FILE"

  # Clear violations after processing
  > "$VIOLATIONS_FILE"

  # Build output message (block first, then warn, then inform)
  OUTPUT_MSG=""
  if [ -n "$BLOCK_MSGS" ]; then
    OUTPUT_MSG="$(printf '🚨 PATROL BLOCKED:\n%s' "$BLOCK_MSGS")"
  fi
  if [ -n "$WARN_MSGS" ]; then
    OUTPUT_MSG="$(printf '%s🟡 PATROL WARNING:\n%s' "$OUTPUT_MSG" "$WARN_MSGS")"
  fi
  if [ -n "$INFORM_MSGS" ]; then
    OUTPUT_MSG="${OUTPUT_MSG}${INFORM_MSGS}"
  fi

  if [ -n "$OUTPUT_MSG" ]; then
    # Format as additionalContext
    ESCAPED_MSG=$(patrol_escape_json "$OUTPUT_MSG")
    cat <<EOF
{
  "additionalContext": "${ESCAPED_MSG}"
}
EOF
    exit 0
  fi
fi

# ─── Check 1: Investigation gate ─────────────────────────────
if [ "$TIER" = "full" ] || [ "$TIER" = "light" ]; then
  THRESHOLD=$(patrol_config "band_aid_threshold" "3")
  NEW_LEVEL=0

  if [ "$TIER" = "full" ]; then
    # Full escalation
    if [ "$UNREAD_EDIT_COUNT" -ge 4 ] || [ "$EDIT_COUNT" -ge "$((THRESHOLD + 1))" ]; then
      NEW_LEVEL=3
    elif [ "$UNREAD_EDIT_COUNT" -ge 3 ] || [ "$EDIT_COUNT" -ge "$THRESHOLD" ]; then
      NEW_LEVEL=2
    elif [ "$UNREAD_EDIT_COUNT" -ge 1 ]; then
      NEW_LEVEL=1
    fi
  else
    # Light mode: nudge only, cap at level 1
    if [ "$UNREAD_EDIT_COUNT" -ge 1 ]; then
      NEW_LEVEL=1
    fi
  fi

  if [ "$NEW_LEVEL" -gt "$NUDGE_LEVEL" ]; then
    echo "$NEW_LEVEL" > "$STATE_DIR/nudge-level"

    case "$NEW_LEVEL" in
      1)
        MSG="🔵 Patrol: ${UNREAD_EDIT_COUNT} file(s) edited without being read first. Consider reading the relevant code before patching."
        ;;
      2)
        MSG="🟡 Patrol: ${EDIT_COUNT} consecutive patches with only ${READ_COUNT} files read. You may be band-aiding. Step back and trace the actual code path before trying another fix."
        ;;
      3)
        MSG="🚨 PATROL: STOP. You've applied ${EDIT_COUNT} patches without proper investigation. Read the files. Trace the root cause. Use /diagnose for a structured investigation protocol. Do NOT apply another patch until you understand the problem."
        ;;
    esac

    if [ -n "${MSG:-}" ]; then
      ESCAPED_MSG=$(patrol_escape_json "$MSG")
      cat <<EOF
{
  "additionalContext": "${ESCAPED_MSG}"
}
EOF
      exit 0
    fi
  fi
fi

# ─── Check 2: Build/test verification ───────────────────────
# Skip verify check when patrol is explicitly off
if [ "$MANUAL_MODE" = "off" ] || [ "$TIER" = "off" ]; then
  exit 0
fi
if [ "$EDIT_COUNT" -gt 0 ]; then
  VERIFIED=false
  [ -f "$STATE_DIR/verified" ] && VERIFIED=true

  if [ "$VERIFIED" = false ]; then
    VERIFY_NUDGE_FILE="$STATE_DIR/verify-nudged"
    VERIFY_NUDGE_COUNT=0
    [ -f "$VERIFY_NUDGE_FILE" ] && VERIFY_NUDGE_COUNT=$(cat "$VERIFY_NUDGE_FILE" | tr -d ' ')
    CURRENT_EDIT_HASH=$(wc -l < "$STATE_DIR/edits" | tr -d ' ')

    if [ "$VERIFY_NUDGE_COUNT" != "$CURRENT_EDIT_HASH" ]; then
      if [ "$EDIT_COUNT" -ge 3 ]; then
        echo "$CURRENT_EDIT_HASH" > "$VERIFY_NUDGE_FILE"

        VERIFY_CMDS=$(patrol_verify_commands "$CWD" 2>/dev/null)
        CMD_LIST=""
        if [ -n "$VERIFY_CMDS" ] && [ "$VERIFY_CMDS" != "[]" ]; then
          CMD_LIST=$(echo "$VERIFY_CMDS" | jq -r 'join(", ")' 2>/dev/null)
        fi

        if [ -n "$CMD_LIST" ]; then
          MSG="🔧 Patrol: ${EDIT_COUNT} files changed, no build/test run yet. Consider running: ${CMD_LIST}"
        else
          MSG="🔧 Patrol: ${EDIT_COUNT} files changed, no build/test run yet."
        fi

        ESCAPED_MSG=$(patrol_escape_json "$MSG")
        cat <<EOF
{
  "additionalContext": "${ESCAPED_MSG}"
}
EOF
        exit 0
      fi
    fi
  fi
fi

# Nothing to report — silent exit (zero tokens)
exit 0
