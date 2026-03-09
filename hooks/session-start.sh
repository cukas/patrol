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
RULE_COUNT=0
if [ -n "$SESSION_ID" ]; then
  STATE_DIR=$(patrol_state_dir "$SESSION_ID")
  rm -f "$STATE_DIR/reads" "$STATE_DIR/edits" "$STATE_DIR/verified" "$STATE_DIR/nudge-level" "$STATE_DIR/verify-nudged" "$STATE_DIR/violations.jsonl" "$STATE_DIR/bash_history" 2>/dev/null
  echo "0" > "$STATE_DIR/nudge-level"

  # Write initial tier based on always_on config
  ALWAYS_ON=$(patrol_config "always_on" "true")
  if [ "$ALWAYS_ON" = "true" ]; then
    echo "light" > "$STATE_DIR/tier"
  else
    echo "off" > "$STATE_DIR/tier"
  fi

  # V3: Load and cache merged rules
  RULES=$(patrol_load_all_rules 2>/dev/null) || RULES="[]"

  # Adaptive level adjustment
  ADAPTIVE_ENABLED=$(patrol_config "adaptive" "true")
  ADAPTIVE_CHANGES=""
  if [ "$ADAPTIVE_ENABLED" = "true" ]; then
    local_rules="$RULES"
    while IFS= read -r rule; do
      [ -z "$rule" ] && continue
      rule_id=$(echo "$rule" | jq -r '.id')
      # Skip safety rules — never adjust them
      case "$rule_id" in _safety-*) continue ;; esac

      configured_level=$(echo "$rule" | jq -r '.level')
      adaptive_min=$(echo "$rule" | jq -r '.adaptive.min // empty')
      adaptive_max=$(echo "$rule" | jq -r '.adaptive.max // empty')

      adjusted_level=$(patrol_adaptive_level_with_bounds "$rule_id" "$configured_level" "$adaptive_min" "$adaptive_max")

      if [ "$adjusted_level" != "$configured_level" ]; then
        local_rules=$(echo "$local_rules" | jq --arg rid "$rule_id" --arg lvl "$adjusted_level" \
          '[.[] | if .id == $rid then .level = $lvl else . end]')
        ADAPTIVE_CHANGES="${ADAPTIVE_CHANGES}  ${rule_id}: ${configured_level} → ${adjusted_level}\n"
        patrol_debug "adaptive: $rule_id level $configured_level → $adjusted_level"
      fi
    done < <(echo "$RULES" | jq -c '.[]')
    RULES="$local_rules"
  fi

  echo "$RULES" > "$STATE_DIR/rules.json"
  RULE_COUNT=$(echo "$RULES" | jq 'length' 2>/dev/null || echo "0")
  patrol_debug "loaded $RULE_COUNT rules to cache"

  # Also clear v3 state files on reset
  rm -f "$STATE_DIR/violations.jsonl" "$STATE_DIR/bash_history" 2>/dev/null

  # Preserve manual mode across clear/compact, reset on fresh startup
  if [ "$SOURCE" = "startup" ]; then
    rm -f "$STATE_DIR/mode" 2>/dev/null
  fi
fi

# Auto-inject status line on startup (not on clear/compact)
if [ "$SOURCE" = "startup" ]; then
  _patrol_ensure_statusline
fi

if [ "$RULE_COUNT" -gt 0 ] 2>/dev/null; then
  if [ "${ADAPTIVE_ENABLED:-false}" = "true" ]; then
    INTRO="🛡️ Patrol active · ${RULE_COUNT} rules loaded · adaptive enabled · /patrol-help for commands"
  else
    INTRO="🛡️ Patrol active · ${RULE_COUNT} rules loaded · /patrol-help for commands"
  fi
else
  INTRO="🛡️ Patrol active · /patrol-help for commands"
fi

# Append adaptive level changes to banner
if [ -n "${ADAPTIVE_CHANGES:-}" ]; then
  INTRO="${INTRO}\\nPatrol: adaptive levels changed:\\n${ADAPTIVE_CHANGES%\\n}"
fi

# First-time adaptive introduction (only on startup, once per install)
if [ "${ADAPTIVE_ENABLED:-false}" = "true" ] && [ "${SOURCE:-}" = "startup" ]; then
  if [ ! -f "$HOME/.patrol/.adaptive-introduced" ]; then
    INTRO="${INTRO}\\nPatrol: adaptive enforcement active — levels adjust based on your behavior."
    mkdir -p "$HOME/.patrol" 2>/dev/null
    touch "$HOME/.patrol/.adaptive-introduced"
  fi
fi

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "${INTRO}"
  }
}
EOF

exit 0
