#!/usr/bin/env bash
# Shared helpers for patrol hooks

# ─── Debug Logging ─────────────────────────────────────────────
patrol_debug() {
  case "${_PATROL_DEBUG_CACHED:-}" in
    0) return 0 ;;
    1) ;;
    *)
      if [ "${PATROL_DEBUG:-}" = "1" ]; then
        export _PATROL_DEBUG_CACHED=1
      else
        local debug_enabled
        debug_enabled=$(patrol_config "debug" "false" 2>/dev/null)
        if [ "$debug_enabled" = "true" ]; then
          export _PATROL_DEBUG_CACHED=1
        else
          export _PATROL_DEBUG_CACHED=0
          return 0
        fi
      fi
      ;;
  esac

  local log_file="$HOME/.patrol/debug.log"
  mkdir -p "$HOME/.patrol" 2>/dev/null

  if [ -f "$log_file" ]; then
    local size
    size=$(wc -c < "$log_file" 2>/dev/null | tr -d ' ')
    if [ "${size:-0}" -gt 1048576 ] 2>/dev/null; then
      mv "$log_file" "${log_file}.1" 2>/dev/null
    fi
  fi

  printf '%s [%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${PATROL_HOOK:-patrol}" "$*" >> "$log_file" 2>/dev/null
}

# ─── jq requirement ──────────────────────────────────────────
patrol_require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "patrol: jq not found — hook disabled" >&2
    exit 0
  fi
}

# ─── JSON escaping ───────────────────────────────────────────
patrol_escape_json() {
  printf '%s' "$1" | jq -Rs . | sed 's/^"//;s/"$//'
}

# ─── Config ──────────────────────────────────────────────────
# Reads config with project-level override: .patrol/config.json > ~/.patrol/config.json
patrol_config() {
  local key="$1"
  local default="$2"

  if [ -n "${PATROL_CWD:-}" ]; then
    local project_config="${PATROL_CWD}/.patrol/config.json"
    if [ -f "$project_config" ]; then
      local val
      val=$(jq -r --arg k "$key" 'if has($k) then (if (.[$k] | type) == "array" then (.[$k] | tojson) else .[$k] | tostring end) else empty end' "$project_config" 2>/dev/null)
      if [ -n "$val" ]; then
        echo "$val"
        return
      fi
    fi
  fi

  local config_file="$HOME/.patrol/config.json"
  if [ ! -f "$config_file" ]; then
    echo "$default"
    return
  fi

  local value
  value=$(jq -r --arg k "$key" 'if has($k) then (if (.[$k] | type) == "array" then (.[$k] | tojson) else .[$k] | tostring end) else empty end' "$config_file" 2>/dev/null)

  if [ -z "$value" ]; then
    echo "$default"
  else
    echo "$value"
  fi
}

# ─── Config writer ───────────────────────────────────────────
patrol_config_set() {
  local key="$1"
  local value="$2"
  local config_file="$HOME/.patrol/config.json"

  mkdir -p "$(dirname "$config_file")"
  [ ! -f "$config_file" ] && echo '{}' > "$config_file"

  local tmp
  tmp=$(mktemp "${config_file}.XXXXXX")
  local jq_ok=false
  if [ "$value" = "true" ] || [ "$value" = "false" ] || [[ "$value" =~ ^[0-9]+$ ]]; then
    jq --arg k "$key" --argjson v "$value" '.[$k] = $v' "$config_file" > "$tmp" 2>/dev/null && jq_ok=true
  elif echo "$value" | jq -e '.' >/dev/null 2>&1; then
    jq --arg k "$key" --argjson v "$value" '.[$k] = $v' "$config_file" > "$tmp" 2>/dev/null && jq_ok=true
  else
    jq --arg k "$key" --arg v "$value" '.[$k] = $v' "$config_file" > "$tmp" 2>/dev/null && jq_ok=true
  fi

  if [ "$jq_ok" = true ]; then
    mv "$tmp" "$config_file"
  else
    rm -f "$tmp"
    return 1
  fi
}

# ─── Hook enable/disable ────────────────────────────────────
patrol_hook_enabled() {
  local hook_name="$1"
  local disabled
  disabled=$(patrol_config "disabled_hooks" "[]")
  if echo "$disabled" | jq -e --arg h "$hook_name" 'index($h)' >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

# ─── State directory ─────────────────────────────────────────
patrol_state_dir() {
  local session_id="$1"
  local dir="/tmp/patrol-${session_id}"
  mkdir -p "$dir" 2>/dev/null
  echo "$dir"
}

# ─── Capped file append ─────────────────────────────────────
# Appends a line to a file, keeping only the last N lines (default 500)
patrol_append_capped() {
  local file="$1"
  local line="$2"
  local max="${3:-500}"

  echo "$line" >> "$file"

  local count
  count=$(wc -l < "$file" 2>/dev/null | tr -d ' ')
  if [ "${count:-0}" -gt "$max" ] 2>/dev/null; then
    local tmp="${file}.tmp.$$"
    tail -n "$max" "$file" > "$tmp" 2>/dev/null && mv "$tmp" "$file" 2>/dev/null || rm -f "$tmp"
  fi
}

# ─── Auto-detect verify commands ─────────────────────────────
patrol_detect_verify_commands() {
  local cwd="${1:-.}"
  local pkg_mgr="npm"
  local commands=()

  # Detect package manager (priority: pnpm > yarn > npm)
  if [ -f "$cwd/pnpm-lock.yaml" ]; then
    pkg_mgr="pnpm"
  elif [ -f "$cwd/yarn.lock" ]; then
    pkg_mgr="yarn"
  elif [ -f "$cwd/package-lock.json" ]; then
    pkg_mgr="npm"
  fi

  # Detect project type and build commands
  if [ -f "$cwd/package.json" ]; then
    if jq -e '.scripts.test' "$cwd/package.json" >/dev/null 2>&1; then
      commands+=("${pkg_mgr} test")
    fi
    if jq -e '.scripts.build' "$cwd/package.json" >/dev/null 2>&1; then
      commands+=("${pkg_mgr} run build")
    fi
  fi

  if [ -f "$cwd/Cargo.toml" ]; then
    commands+=("cargo test" "cargo build")
  fi

  if [ -f "$cwd/pyproject.toml" ] || [ -f "$cwd/setup.py" ]; then
    commands+=("pytest")
  fi

  if [ -f "$cwd/go.mod" ]; then
    commands+=("go test ./...")
  fi

  if [ -f "$cwd/Makefile" ] && grep -q "^test:" "$cwd/Makefile" 2>/dev/null; then
    commands+=("make test")
  fi

  if [ ${#commands[@]} -eq 0 ]; then
    echo '[]'
  else
    printf '%s\n' "${commands[@]}" | jq -R . | jq -s .
  fi
}

# ─── Get verify commands (config or auto-detect) ─────────────
patrol_verify_commands() {
  local cwd="${1:-.}"
  local configured
  configured=$(patrol_config "verify_commands" "auto")

  if [ "$configured" = "auto" ]; then
    patrol_detect_verify_commands "$cwd"
  else
    echo "$configured"
  fi
}

# ─── Default keywords ────────────────────────────────────────
PATROL_DEFAULT_KEYWORDS='["fix","bug","broken","error","crash","doesn'\''t work","not working","Fehler","kaputt","Absturz","funktioniert nicht","erreur","plantage","cassé","ne marche pas"]'

# ─── Merged keywords (defaults + custom) ─────────────────────
# Returns a JSON array of all keywords (defaults + custom_keywords from config)
patrol_merged_keywords() {
  local custom
  custom=$(patrol_config "custom_keywords" "[]")

  # Merge: defaults + custom, deduplicated
  echo "$PATROL_DEFAULT_KEYWORDS" "$custom" | jq -s 'add | unique'
}

# ─── Easter egg messages ──────────────────────────────────────
# Usage: patrol_yoda_message "nudge|warning|stop" "normal_message"
# Returns yoda-themed message if easter_eggs enabled, otherwise the normal message
patrol_yoda_message() {
  local level="$1"
  local normal_msg="$2"
  local easter_eggs
  easter_eggs=$(patrol_config "easter_eggs" "false")

  if [ "$easter_eggs" != "true" ]; then
    echo "$normal_msg"
    return
  fi

  case "$level" in
    nudge)   echo "${normal_msg}, hmm" ;;
    warning) echo "band-aid this is" ;;
    stop)    echo "investigate you must" ;;
    verify)  echo "verify your work, you should" ;;
    *)       echo "$normal_msg" ;;
  esac
}

# ─── Status line auto-injection ───────────────────────────────
# Appends Patrol's adaptive display snippet to settings.json statusLine.command
# Guard: checks for "patrol-state" marker to avoid double-injection
_patrol_ensure_statusline() {
  local settings_file="$HOME/.claude/settings.json"
  mkdir -p "$HOME/.claude" 2>/dev/null
  [ -f "$settings_file" ] || echo '{}' > "$settings_file"

  # Already injected? Skip.
  if grep -q "patrol-state" "$settings_file" 2>/dev/null; then
    return 0
  fi

  # Backup before mutation
  cp "$settings_file" "${settings_file}.patrol-backup" 2>/dev/null || true

  local has_statusline
  has_statusline=$(jq -r '.statusLine.command // empty' "$settings_file" 2>/dev/null)

  # Build the Patrol status line snippet
  local patrol_snippet
  patrol_snippet='PATROL_DIR="/tmp/patrol-${session_id}"; if [ -d "$PATROL_DIR" ]; then p_tier=$(cat "$PATROL_DIR/tier" 2>/dev/null); p_mode=$(cat "$PATROL_DIR/mode" 2>/dev/null); p_nudge=$(cat "$PATROL_DIR/nudge-level" 2>/dev/null | tr -d "[:space:]"); p_edits=0; p_reads=0; p_unread=0; [ -f "$PATROL_DIR/edits" ] && p_edits=$(wc -l < "$PATROL_DIR/edits" | tr -d " "); [ -f "$PATROL_DIR/reads" ] && p_reads=$(wc -l < "$PATROL_DIR/reads" | tr -d " "); if [ "$p_edits" -gt 0 ] && [ -f "$PATROL_DIR/edits" ]; then if [ -f "$PATROL_DIR/reads" ]; then p_unread=$(comm -23 <(sort -u "$PATROL_DIR/edits") <(sort -u "$PATROL_DIR/reads") | wc -l | tr -d " "); else p_unread=$p_edits; fi; fi; p_verified=false; [ -f "$PATROL_DIR/verified" ] && p_verified=true; p_easter=$(jq -r ".easter_eggs // false" "$HOME/.patrol/config.json" 2>/dev/null); p_display=""; if [ "$p_mode" != "off" ]; then if [ "${p_nudge:-0}" -ge 3 ] 2>/dev/null; then if [ "$p_easter" = "true" ]; then p_display="$(printf '"'"'\033[31m'"'"')🚨 investigate you must$(printf '"'"'\033[0m'"'"')"; else p_display="$(printf '"'"'\033[31m'"'"')🚨 STOP$(printf '"'"'\033[0m'"'"')"; fi; elif [ "${p_nudge:-0}" -ge 2 ] 2>/dev/null; then if [ "$p_easter" = "true" ]; then p_display="$(printf '"'"'\033[33m'"'"')🟡 band-aid this is$(printf '"'"'\033[0m'"'"')"; else p_display="$(printf '"'"'\033[33m'"'"')🟡 ${p_edits} patches$(printf '"'"'\033[0m'"'"')"; fi; elif [ "$p_unread" -ge 1 ] 2>/dev/null; then if [ "$p_easter" = "true" ]; then p_display="$(printf '"'"'\033[33m'"'"')🛡️ ${p_unread} unread, hmm$(printf '"'"'\033[0m'"'"')"; else p_display="$(printf '"'"'\033[33m'"'"')🛡️ ${p_unread} unread$(printf '"'"'\033[0m'"'"')"; fi; elif [ "$p_edits" -gt 0 ] || [ "$p_reads" -gt 0 ]; then if [ "$p_tier" = "full" ]; then p_display="$(printf '"'"'\033[32m'"'"')🛡️ bugfix · 📖${p_reads} ✏️${p_edits}$(printf '"'"'\033[0m'"'"')"; else p_display="$(printf '"'"'\033[32m'"'"')🛡️ 📖${p_reads} ✏️${p_edits}$(printf '"'"'\033[0m'"'"')"; fi; else if [ "$p_tier" != "off" ]; then p_display="🛡️"; fi; fi; if [ "$p_verified" = true ] && [ -n "$p_display" ]; then p_display="${p_display} ✅"; fi; fi; if [ -n "$p_display" ]; then status="$status | $p_display"; fi; fi; # patrol-state'

  if [ -z "$has_statusline" ]; then
    patrol_debug "WARNING: no statusLine.command found — skipping injection"
    echo "Patrol: no status line found in settings.json — status line indicator requires an existing status line" >&2
    return 0
  fi

  # Append snippet to existing command
  local new_command
  new_command=$(jq -r '.statusLine.command' "$settings_file" 2>/dev/null)
  new_command="${new_command}; ${patrol_snippet}"

  # Write back atomically
  local tmp
  tmp=$(mktemp "${settings_file}.XXXXXX")
  if jq --arg cmd "$new_command" '.statusLine.command = $cmd' "$settings_file" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    mv "$tmp" "$settings_file"
    patrol_debug "status line auto-configured in settings.json"
    echo "Patrol: status line configured in settings.json" >&2
  else
    rm -f "$tmp"
    patrol_debug "ERROR: failed to write settings.json"
  fi
}

# ── Rule Engine ─────────────────────────────────────────────────

PATROL_VALID_LEVELS='["inform","warn","block"]'
PATROL_VALID_CATEGORIES='["safety","workflow","quality","architecture","custom"]'
PATROL_VALID_TRIGGER_TYPES='["bash_command","tool_use","sequence","keyword","file_changed","session_event"]'
PATROL_VALID_REQUIRE_TYPES='["bash_ran","file_read","tool_used","rule_passed","cooldown","branch_name_match"]'

# Validate a single rule from stdin. Returns 0 if valid, 1 if not.
patrol_validate_rule() {
  local rule
  rule=$(cat)

  # Extract all fields in a single jq call (also catches invalid JSON)
  local fields
  fields=$(echo "$rule" | jq -r '[.id // "", .name // "", .category // "", .level // "", (.trigger.type // ""), .message // "", (.require.type // "")] | @tsv') || {
    patrol_debug "rule validation: invalid JSON"; return 1
  }
  local id name category level trigger_type message require_type
  IFS=$'\t' read -r id name category level trigger_type message require_type <<< "$fields"

  # Required fields
  [ -z "$id" ] && patrol_debug "rule validation: missing id" && return 1
  [ -z "$name" ] && patrol_debug "rule validation: missing name for $id" && return 1
  [ -z "$category" ] && patrol_debug "rule validation: missing category for $id" && return 1
  [ -z "$level" ] && patrol_debug "rule validation: missing level for $id" && return 1
  [ -z "$trigger_type" ] && patrol_debug "rule validation: missing trigger.type for $id" && return 1
  [ -z "$message" ] && patrol_debug "rule validation: missing message for $id" && return 1

  # Valid enums (use --arg to prevent jq expression injection)
  echo "$PATROL_VALID_LEVELS" | jq -e --arg v "$level" 'index($v)' >/dev/null 2>&1 || {
    patrol_debug "rule validation: invalid level '$level' for $id"; return 1
  }
  echo "$PATROL_VALID_CATEGORIES" | jq -e --arg v "$category" 'index($v)' >/dev/null 2>&1 || {
    patrol_debug "rule validation: invalid category '$category' for $id"; return 1
  }
  echo "$PATROL_VALID_TRIGGER_TYPES" | jq -e --arg v "$trigger_type" 'index($v)' >/dev/null 2>&1 || {
    patrol_debug "rule validation: invalid trigger type '$trigger_type' for $id"; return 1
  }

  # Validate require type if present
  if [ -n "$require_type" ]; then
    echo "$PATROL_VALID_REQUIRE_TYPES" | jq -e --arg v "$require_type" 'index($v)' >/dev/null 2>&1 || {
      patrol_debug "rule validation: invalid require type '$require_type' for $id"; return 1
    }
  fi

  return 0
}
