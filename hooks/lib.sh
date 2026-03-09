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
    block)   echo "Proceed you shall not." ;;
    warn)    echo "A disturbance in the Force, I sense." ;;
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

# Load rules array from a rules.json file. Returns JSON array.
patrol_load_rules() {
  local file="$1"
  [ ! -f "$file" ] && echo "[]" && return 0
  local rules
  rules=$(jq -r '.rules // []' "$file" 2>/dev/null) || { echo "[]"; return 0; }
  # Validate each rule, filter out invalid ones
  local valid_ndjson=""
  while IFS= read -r rule; do
    if echo "$rule" | patrol_validate_rule 2>/dev/null; then
      # Skip rules with enabled: false
      local is_enabled
      is_enabled=$(echo "$rule" | jq -r 'if has("enabled") then .enabled else true end')
      if [ "$is_enabled" = "false" ]; then
        patrol_debug "skipping disabled rule: $(echo "$rule" | jq -r '.id')"
        continue
      fi
      valid_ndjson="${valid_ndjson}${rule}"$'\n'
    else
      patrol_debug "skipping invalid rule: $(echo "$rule" | jq -r '.id // "unknown"')"
    fi
  done < <(echo "$rules" | jq -c '.[]')
  if [ -n "$valid_ndjson" ]; then
    echo "$valid_ndjson" | jq -s '.'
  else
    echo "[]"
  fi
}

# Merge three layers of rules. Returns merged JSON array.
# Company (base) <- Repo (overrides) <- Personal (extends, cannot weaken)
patrol_merge_rules() {
  local company="${1:-[]}" repo="${2:-[]}" personal="${3:-[]}"

  # Level strength for comparison
  local level_order='{"inform":1,"warn":2,"block":3}'

  # Start with company rules
  local merged="$company"

  # Repo overrides company (can strengthen or weaken)
  merged=$(jq -n --argjson base "$merged" --argjson overlay "$repo" '
    ($base | map({key: .id, value: .}) | from_entries) as $base_map |
    ($overlay | map({key: .id, value: .}) | from_entries) as $overlay_map |
    ($base_map + $overlay_map) | to_entries | map(.value)
  ')

  # Personal extends but cannot weaken (level must be >= existing)
  merged=$(jq -n --argjson base "$merged" --argjson overlay "$personal" --argjson levels "$level_order" '
    ($base | map({key: .id, value: .}) | from_entries) as $base_map |
    reduce ($overlay | .[]) as $rule ($base_map;
      if .[$rule.id] then
        # Rule exists — only override if personal level is >= base level
        if ($levels[$rule.level] // 0) >= ($levels[.[$rule.id].level] // 0)
        then . + {($rule.id): $rule}
        else .
        end
      else
        # New rule — add it
        . + {($rule.id): $rule}
      end
    ) | to_entries | map(.value)
  ')

  echo "$merged"
}

# Load all rules from all layers + built-in safety. Returns merged JSON array.
patrol_load_all_rules() {
  local company_file="${PATROL_COMPANY_RULES:-$HOME/.patrol/company.json}"
  local repo_file="${PATROL_REPO_RULES:-${PATROL_CWD:-.}/.patrol/rules.json}"
  local personal_file="${PATROL_PERSONAL_RULES:-$HOME/.patrol/my-rules.json}"

  local company repo personal safety
  company=$(patrol_load_rules "$company_file")
  repo=$(patrol_load_rules "$repo_file")
  personal=$(patrol_load_rules "$personal_file")

  # Built-in safety rules (from templates dir relative to script, validated)
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local safety_file="$script_dir/../templates/safety-rules.json"
  safety=$(patrol_load_rules "$safety_file")

  # Built-in investigation rules (v2 behavior as templates)
  local investigation_file="$script_dir/../templates/investigation-rules.json"
  local investigation
  investigation=$(patrol_load_rules "$investigation_file")

  # Merge: safety (base) <- investigation <- company <- repo <- personal
  local merged
  merged=$(patrol_merge_rules "$safety" "$investigation" "[]")
  merged=$(patrol_merge_rules "$merged" "$company" "[]")
  merged=$(patrol_merge_rules "$merged" "$repo" "[]")
  merged=$(patrol_merge_rules "$merged" "[]" "$personal")

  # Safety rules always win — re-inject to prevent any layer from weakening them
  merged=$(jq -n --argjson base "$merged" --argjson safety "$safety" '
    ($base | map({key: .id, value: .}) | from_entries) as $base_map |
    ($safety | map({key: .id, value: .}) | from_entries) as $safety_map |
    ($base_map + $safety_map) | to_entries | map(.value)
  ')

  echo "$merged"
}

# Check if a rule's trigger matches the current tool use.
# Args: tool_name, file_path, bash_command
# Rule from stdin. Returns 0 if triggered, 1 if not.
patrol_check_trigger() {
  local tool="$1" file="$2" command="$3"
  local rule
  rule=$(cat)

  local trigger_type trigger_match trigger_tool trigger_glob
  trigger_type=$(echo "$rule" | jq -r '.trigger.type')
  trigger_match=$(echo "$rule" | jq -r '.trigger.match // empty')
  trigger_tool=$(echo "$rule" | jq -r '.trigger.tool // empty')
  trigger_glob=$(echo "$rule" | jq -r '.trigger.glob // empty')

  case "$trigger_type" in
    bash_command)
      [ "$tool" = "Bash" ] || return 1
      [ -z "$trigger_match" ] && return 1
      echo "$command" | grep -qE "$trigger_match" && return 0
      return 1
      ;;
    tool_use)
      [ -n "$trigger_tool" ] && [ "$tool" != "$trigger_tool" ] && return 1
      if [ -n "$trigger_glob" ] && [ -n "$file" ]; then
        # Simple glob match using bash pattern
        case "$file" in
          $trigger_glob) return 0 ;;
          *) return 1 ;;
        esac
      fi
      [ "$tool" = "$trigger_tool" ] && return 0
      return 1
      ;;
    file_changed)
      [ -z "$file" ] && return 1
      [ -z "$trigger_glob" ] && return 1
      case "$tool" in Edit|Write|MultiEdit) ;; *) return 1 ;; esac
      case "$file" in
        $trigger_glob) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    *)
      return 1
      ;;
  esac
}

# Check sequence rules (edit-without-read).
# Args: state_dir, file_path
# Returns 0 if file was edited but not read (i.e., violation detected).
patrol_check_sequence() {
  local state_dir="$1" file="$2"
  [ -z "$file" ] && return 1
  # Check if file was read in this session
  if [ -f "$state_dir/reads" ] && grep -qxF "$file" "$state_dir/reads"; then
    return 1  # File was read — no violation
  fi
  # File not read but edited
  return 0
}

# ── Adaptive Score Engine ────────────────────────────────────────

PATROL_ADAPTIVE_DECAY=0.95
PATROL_ADAPTIVE_ESCALATE=5.0
PATROL_ADAPTIVE_DEESCALATE=0.5

# Read adaptive history from ~/.patrol/history.json
# Returns JSON object with version and rules map
patrol_adaptive_history() {
  local history_file="$HOME/.patrol/history.json"
  if [ ! -f "$history_file" ]; then
    echo '{"version":"1.0","rules":{}}'
    return 0
  fi
  cat "$history_file"
}

# Write history atomically (write to temp, mv)
patrol_adaptive_save_history() {
  local history="$1"
  local history_file="$HOME/.patrol/history.json"
  mkdir -p "$HOME/.patrol" 2>/dev/null
  local tmp
  tmp=$(mktemp "${history_file}.XXXXXX")
  if printf '%s\n' "$history" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$history_file"
  else
    rm -f "$tmp"
    return 1
  fi
}

# Parse ISO 8601 timestamp to epoch seconds
# macOS: date -j -f, Linux: date -d
_patrol_parse_iso_to_epoch() {
  local iso="$1"
  local epoch
  # Try macOS first
  epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" "+%s" 2>/dev/null) && { echo "$epoch"; return 0; }
  # Fallback to Linux
  epoch=$(date -d "$iso" "+%s" 2>/dev/null) && { echo "$epoch"; return 0; }
  # Last resort: return current time
  date "+%s"
}

# Get current effective score for a rule, applying decay.
# Args: rule_id
# Returns: float score (0 if unknown rule)
patrol_adaptive_get_score() {
  local rule_id="$1"
  local history
  history=$(patrol_adaptive_history)

  # Check if rule exists in history
  local entry
  entry=$(echo "$history" | jq -r --arg rid "$rule_id" '.rules[$rid] // empty')
  if [ -z "$entry" ]; then
    echo "0"
    return 0
  fi

  local score last_updated
  score=$(echo "$entry" | jq -r '.score // 0')
  last_updated=$(echo "$entry" | jq -r '.last_updated // empty')

  if [ -z "$last_updated" ]; then
    echo "$score"
    return 0
  fi

  # Calculate days since last update
  local now_epoch last_epoch
  now_epoch=$(date "+%s")
  last_epoch=$(_patrol_parse_iso_to_epoch "$last_updated")

  local decay
  decay=$(patrol_config "adaptive_decay" "$PATROL_ADAPTIVE_DECAY")

  # effective = score * decay^days_since_last_update
  local effective
  effective=$(awk -v s="$score" -v d="$decay" -v now="$now_epoch" -v last="$last_epoch" \
    'BEGIN { days = (now - last) / 86400; if (days < 0) days = 0; printf "%.6f", s * (d ^ days) }')

  echo "$effective"
}

# Record a violation for a rule.
# Args: rule_id
# Updates score: new_score = current_score * decay^days + 1.0
# Increments total_violations. Writes atomically.
patrol_adaptive_record_violation() {
  local rule_id="$1"
  local history
  history=$(patrol_adaptive_history)

  local now_iso
  now_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local now_epoch
  now_epoch=$(date "+%s")

  local decay
  decay=$(patrol_config "adaptive_decay" "$PATROL_ADAPTIVE_DECAY")

  # Get existing entry (may be empty for first-time)
  local entry
  entry=$(echo "$history" | jq -r --arg rid "$rule_id" '.rules[$rid] // empty')

  local new_score total_violations
  if [ -z "$entry" ]; then
    # First-time: score = 1.0, total_violations = 1
    new_score="1.000000"
    total_violations=1
  else
    local old_score last_updated old_total
    old_score=$(echo "$entry" | jq -r '.score // 0')
    last_updated=$(echo "$entry" | jq -r '.last_updated // empty')
    old_total=$(echo "$entry" | jq -r '.total_violations // 0')

    if [ -z "$last_updated" ]; then
      new_score=$(awk -v s="$old_score" 'BEGIN { printf "%.6f", s + 1.0 }')
    else
      local last_epoch
      last_epoch=$(_patrol_parse_iso_to_epoch "$last_updated")
      new_score=$(awk -v s="$old_score" -v d="$decay" -v now="$now_epoch" -v last="$last_epoch" \
        'BEGIN { days = (now - last) / 86400; if (days < 0) days = 0; printf "%.6f", s * (d ^ days) + 1.0 }')
    fi

    total_violations=$((old_total + 1))
  fi

  # Update history
  history=$(echo "$history" | jq --arg rid "$rule_id" \
    --argjson score "$new_score" \
    --argjson total "$total_violations" \
    --arg ts "$now_iso" \
    '.rules[$rid] = {"score": $score, "total_violations": $total, "last_updated": $ts}')

  patrol_adaptive_save_history "$history"
}

# Calculate adaptive level for a rule.
# Args: rule_id, configured_level
# Returns: adjusted level string (inform/warn/block)
patrol_adaptive_level() {
  local rule_id="$1"
  local configured_level="$2"

  local score
  score=$(patrol_adaptive_get_score "$rule_id")

  local escalate_threshold deescalate_threshold
  escalate_threshold=$(patrol_config "adaptive_escalate_threshold" "$PATROL_ADAPTIVE_ESCALATE")
  deescalate_threshold=$(patrol_config "adaptive_deescalate_threshold" "$PATROL_ADAPTIVE_DEESCALATE")

  # Level order: inform=0, warn=1, block=2
  local level_num
  case "$configured_level" in
    inform) level_num=0 ;;
    warn)   level_num=1 ;;
    block)  level_num=2 ;;
    *)      echo "$configured_level"; return 0 ;;
  esac

  # Check escalation/de-escalation
  local should_escalate should_deescalate
  should_escalate=$(awk -v s="$score" -v t="$escalate_threshold" 'BEGIN { print (s > t) ? "1" : "0" }')
  should_deescalate=$(awk -v s="$score" -v t="$deescalate_threshold" 'BEGIN { print (s < t) ? "1" : "0" }')

  if [ "$should_escalate" = "1" ]; then
    level_num=$((level_num + 1))
  elif [ "$should_deescalate" = "1" ]; then
    level_num=$((level_num - 1))
  fi

  # Clamp to boundaries
  [ "$level_num" -lt 0 ] && level_num=0
  [ "$level_num" -gt 2 ] && level_num=2

  # Convert back to string
  case "$level_num" in
    0) echo "inform" ;;
    1) echo "warn" ;;
    2) echo "block" ;;
  esac
}

# Helper: convert level string to number
_patrol_level_to_num() {
  case "$1" in
    inform) echo 0 ;;
    warn)   echo 1 ;;
    block)  echo 2 ;;
    *)      echo 1 ;;
  esac
}

# Helper: convert level number to string
_patrol_num_to_level() {
  case "$1" in
    0) echo "inform" ;;
    1) echo "warn" ;;
    2) echo "block" ;;
    *) echo "warn" ;;
  esac
}

# Calculate adaptive level with explicit min/max bounds.
# Args: rule_id, configured_level, min_level, max_level
# If min_level or max_level are empty, use default ±1 from configured_level.
patrol_adaptive_level_with_bounds() {
  local rule_id="$1"
  local configured_level="$2"
  local min_level="${3:-}"
  local max_level="${4:-}"

  # Get the unbounded adaptive level first
  local adaptive
  adaptive=$(patrol_adaptive_level "$rule_id" "$configured_level")

  local adaptive_num configured_num
  adaptive_num=$(_patrol_level_to_num "$adaptive")
  configured_num=$(_patrol_level_to_num "$configured_level")

  # Calculate default bounds if not provided (±1 from configured, clamped to 0-2)
  local min_num max_num
  if [ -z "$min_level" ]; then
    min_num=$((configured_num - 1))
    [ "$min_num" -lt 0 ] && min_num=0
  else
    min_num=$(_patrol_level_to_num "$min_level")
  fi

  if [ -z "$max_level" ]; then
    max_num=$((configured_num + 1))
    [ "$max_num" -gt 2 ] && max_num=2
  else
    max_num=$(_patrol_level_to_num "$max_level")
  fi

  # Clamp adaptive to bounds
  [ "$adaptive_num" -lt "$min_num" ] && adaptive_num=$min_num
  [ "$adaptive_num" -gt "$max_num" ] && adaptive_num=$max_num

  # Convert back to string
  _patrol_num_to_level "$adaptive_num"
}
