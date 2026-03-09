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
  local repo_file="${PATROL_REPO_RULES:-.patrol/rules.json}"
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

  # Merge: safety (base) <- company <- repo <- personal
  local merged
  merged=$(patrol_merge_rules "$safety" "$company" "[]")
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
  if [ -f "$state_dir/reads" ] && grep -qF "$file" "$state_dir/reads"; then
    return 1  # File was read — no violation
  fi
  # File not read but edited
  return 0
}
