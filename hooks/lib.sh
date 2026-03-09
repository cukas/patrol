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
