# Patrol — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a Claude Code plugin that enforces development discipline through hook-based monitoring — detecting band-aid fixes, enforcing investigation before edits, and verifying builds/tests before completion.

**Architecture:** Three hooks (SessionStart, PostToolUse, UserPromptSubmit) coordinate via `/tmp/patrol-{session_id}/` state files. PostToolUse silently tracks Read/Edit/Bash events. UserPromptSubmit reads state and injects escalating warnings when anti-patterns are detected. Config merges global (`~/.patrol/config.json`) with per-project (`.patrol/config.json`).

**Tech Stack:** Bash hooks, jq for JSON, `/tmp` for state, markdown for skills/commands.

---

### Task 1: Plugin Scaffold

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `.claude-plugin/marketplace.json`
- Create: `.gitignore`
- Create: `LICENSE`

**Step 1: Create plugin.json**

```json
{
  "name": "patrol",
  "description": "Development discipline enforcement for Claude Code — stop band-aiding, investigate first, verify before done",
  "version": "1.0.0",
  "author": {
    "name": "cukas"
  },
  "homepage": "https://github.com/cukas/patrol",
  "repository": "https://github.com/cukas/patrol",
  "license": "MIT",
  "keywords": ["discipline", "investigation", "debugging", "verification", "band-aid", "root-cause", "quality"]
}
```

**Step 2: Create marketplace.json**

```json
{
  "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
  "name": "cukas",
  "description": "Development discipline enforcement for Claude Code — stop band-aiding, investigate first, verify before done",
  "owner": {
    "name": "cukas"
  },
  "plugins": [
    {
      "name": "patrol",
      "description": "Stop band-aiding. Investigate first. Verify before done.",
      "version": "1.0.0",
      "author": {
        "name": "cukas"
      },
      "source": "./",
      "category": "productivity",
      "homepage": "https://github.com/cukas/patrol",
      "tags": ["discipline", "investigation", "debugging", "verification", "quality", "root-cause"]
    }
  ]
}
```

**Step 3: Create .gitignore**

```
*.log
.DS_Store
```

**Step 4: Create LICENSE (MIT)**

Standard MIT license with "cukas" as copyright holder, year 2026.

**Step 5: Commit**

```bash
git add .claude-plugin/ .gitignore LICENSE
git commit -m "feat: scaffold patrol plugin with metadata"
```

---

### Task 2: Shared Library (lib.sh)

**Files:**
- Create: `hooks/lib.sh`

The shared library provides config reading, debug logging, JSON escaping, and state helpers. Modeled after Remembrall's lib.sh but much simpler (no calibration, no model detection).

**Step 1: Write lib.sh with these functions**

```bash
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

  # Rotate at 1MB
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
# Usage: patrol_config "key" "default_value"
patrol_config() {
  local key="$1"
  local default="$2"

  # Try project-level config first (set by hook input CWD)
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

  # Fall back to global config
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
# Returns /tmp/patrol-{session_id}/, creating it if needed
patrol_state_dir() {
  local session_id="$1"
  local dir="/tmp/patrol-${session_id}"
  mkdir -p "$dir" 2>/dev/null
  echo "$dir"
}

# ─── Auto-detect verify commands ─────────────────────────────
# Detects package manager and project type, returns JSON array of commands
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
    # Check if test script exists
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

  # Output as JSON array
  printf '%s\n' "${commands[@]}" | jq -R . | jq -s .
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
```

**Step 2: Make executable**

```bash
chmod +x hooks/lib.sh
```

**Step 3: Commit**

```bash
git add hooks/lib.sh
git commit -m "feat: add shared library with config, logging, and auto-detection"
```

---

### Task 3: Hook Registration (hooks.json)

**Files:**
- Create: `hooks/hooks.json`

**Step 1: Write hooks.json**

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh",
            "timeout": 10,
            "async": false
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Read|Edit|Write|Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/tool-tracker.sh",
            "timeout": 5,
            "async": true
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/prompt-monitor.sh",
            "timeout": 10,
            "async": false
          }
        ]
      }
    ]
  }
}
```

**Step 2: Commit**

```bash
git add hooks/hooks.json
git commit -m "feat: register SessionStart, PostToolUse, and UserPromptSubmit hooks"
```

---

### Task 4: Session Start Hook

**Files:**
- Create: `hooks/session-start.sh`

**Step 1: Write session-start.sh**

This hook:
1. Resets session state in `/tmp/patrol-{sid}/`
2. Injects a minimal Patrol intro into Claude's context

```bash
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
  rm -f "$STATE_DIR/reads" "$STATE_DIR/edits" "$STATE_DIR/verified" "$STATE_DIR/nudge-level" 2>/dev/null
  echo "0" > "$STATE_DIR/nudge-level"

  # Preserve manual mode across clear/compact, reset on fresh startup
  if [ "$SOURCE" = "startup" ]; then
    rm -f "$STATE_DIR/mode" 2>/dev/null
  fi
fi

# Read the intro skill content
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INTRO="Patrol is active. It monitors your development discipline:\\n- Detects bug-fix sessions automatically (or use /patrol on)\\n- Warns if you edit files without reading them first\\n- Warns if you apply successive patches without investigating\\n- Reminds you to run build/test after making changes\\nUse /patrol-help for commands. Zero token cost when you're working properly."

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "${INTRO}"
  }
}
EOF

exit 0
```

**Step 2: Make executable**

```bash
chmod +x hooks/session-start.sh
```

**Step 3: Commit**

```bash
git add hooks/session-start.sh
git commit -m "feat: session-start hook with state reset and intro injection"
```

---

### Task 5: Tool Tracker Hook (Silent PostToolUse)

**Files:**
- Create: `hooks/tool-tracker.sh`

**Step 1: Write tool-tracker.sh**

This hook NEVER outputs anything — it only writes state to `/tmp`. Runs async so it doesn't block Claude.

```bash
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
[ -z "$SESSION_ID" ] || [ -z "$TOOL_NAME" ] && exit 0

# Check if enabled
ENABLED=$(patrol_config "enabled" "true")
[ "$ENABLED" = "false" ] && exit 0

STATE_DIR=$(patrol_state_dir "$SESSION_ID")

case "$TOOL_NAME" in
  Read)
    # Track file reads
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    if [ -n "$FILE_PATH" ]; then
      echo "$FILE_PATH" >> "$STATE_DIR/reads"
      patrol_debug "read tracked: $FILE_PATH"
    fi
    ;;
  Edit|Write)
    # Track file edits
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    if [ -n "$FILE_PATH" ]; then
      echo "$FILE_PATH" >> "$STATE_DIR/edits"
      patrol_debug "edit tracked: $FILE_PATH"
    fi
    ;;
  Bash)
    # Check if command matches verify commands
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
    if [ -n "$COMMAND" ] && [ -n "$CWD" ]; then
      VERIFY_CMDS=$(patrol_verify_commands "$CWD" 2>/dev/null)
      if [ -n "$VERIFY_CMDS" ]; then
        # Check if the bash command contains any verify command
        MATCHED=$(echo "$VERIFY_CMDS" | jq -r '.[]' 2>/dev/null | while read -r cmd; do
          if echo "$COMMAND" | grep -qF "$cmd"; then
            echo "1"
            break
          fi
        done)
        if [ "$MATCHED" = "1" ]; then
          # Mark as verified, clear unverified edits
          date +%s > "$STATE_DIR/verified"
          > "$STATE_DIR/edits"
          patrol_debug "verified: $COMMAND"
        fi
      fi
    fi
    ;;
esac

# NEVER output anything — silent hook
exit 0
```

**Step 2: Make executable**

```bash
chmod +x hooks/tool-tracker.sh
```

**Step 3: Commit**

```bash
git add hooks/tool-tracker.sh
git commit -m "feat: silent tool-tracker hook for Read/Edit/Bash state tracking"
```

---

### Task 6: Prompt Monitor Hook (The Brain)

**Files:**
- Create: `hooks/prompt-monitor.sh`

**Step 1: Write prompt-monitor.sh**

This is the main enforcement hook. It reads state from `/tmp/patrol-{sid}/` and decides whether to inject a warning.

```bash
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

# Check if enabled
ENABLED=$(patrol_config "enabled" "true")
[ "$ENABLED" = "false" ] && exit 0

STATE_DIR=$(patrol_state_dir "$SESSION_ID")

# ─── Determine patrol mode ──────────────────────────────────
MODE="off"
MANUAL_MODE=""
[ -f "$STATE_DIR/mode" ] && MANUAL_MODE=$(cat "$STATE_DIR/mode" 2>/dev/null)

if [ "$MANUAL_MODE" = "on" ]; then
  MODE="on"
elif [ "$MANUAL_MODE" = "off" ]; then
  MODE="off"
else
  # Auto-detect from user message keywords
  AUTO_DETECT=$(patrol_config "auto_detect_bugfix" "true")
  if [ "$AUTO_DETECT" = "true" ] && [ -n "$USER_MESSAGE" ]; then
    KEYWORDS=$(patrol_config "keywords" '["fix","bug","broken","error","crash","doesn'\''t work","not working"]')
    # Check if user message contains any keyword (case-insensitive)
    MSG_LOWER=$(echo "$USER_MESSAGE" | tr '[:upper:]' '[:lower:]')
    KEYWORD_MATCH=$(echo "$KEYWORDS" | jq -r '.[]' 2>/dev/null | while read -r kw; do
      kw_lower=$(echo "$kw" | tr '[:upper:]' '[:lower:]')
      if echo "$MSG_LOWER" | grep -qF "$kw_lower"; then
        echo "1"
        break
      fi
    done)
    if [ "$KEYWORD_MATCH" = "1" ]; then
      MODE="auto"
      patrol_debug "bug-fix mode auto-activated by keyword match"
    fi
  fi
fi

patrol_debug "mode=$MODE manual=$MANUAL_MODE"

# ─── Read state ──────────────────────────────────────────────
EDIT_COUNT=0
READ_COUNT=0
UNREAD_EDIT_COUNT=0
NUDGE_LEVEL=0

[ -f "$STATE_DIR/edits" ] && EDIT_COUNT=$(wc -l < "$STATE_DIR/edits" | tr -d ' ')
[ -f "$STATE_DIR/reads" ] && READ_COUNT=$(wc -l < "$STATE_DIR/reads" | tr -d ' ')
[ -f "$STATE_DIR/nudge-level" ] && NUDGE_LEVEL=$(cat "$STATE_DIR/nudge-level" | tr -d ' ')

# Count edits to files that weren't read first
if [ "$EDIT_COUNT" -gt 0 ] && [ -f "$STATE_DIR/edits" ]; then
  if [ -f "$STATE_DIR/reads" ]; then
    UNREAD_EDIT_COUNT=$(comm -23 <(sort -u "$STATE_DIR/edits") <(sort -u "$STATE_DIR/reads") | wc -l | tr -d ' ')
  else
    UNREAD_EDIT_COUNT=$EDIT_COUNT
  fi
fi

patrol_debug "edits=$EDIT_COUNT reads=$READ_COUNT unread_edits=$UNREAD_EDIT_COUNT nudge=$NUDGE_LEVEL"

# ─── Check 1: Investigation gate (bug-fix mode) ─────────────
if [ "$MODE" = "on" ] || [ "$MODE" = "auto" ]; then
  THRESHOLD=$(patrol_config "band_aid_threshold" "3")
  NEW_LEVEL=0

  if [ "$UNREAD_EDIT_COUNT" -ge 4 ] || [ "$EDIT_COUNT" -ge "$((THRESHOLD + 1))" ]; then
    NEW_LEVEL=3
  elif [ "$UNREAD_EDIT_COUNT" -ge 3 ] || [ "$EDIT_COUNT" -ge "$THRESHOLD" ]; then
    NEW_LEVEL=2
  elif [ "$UNREAD_EDIT_COUNT" -ge 1 ]; then
    NEW_LEVEL=1
  fi

  # Only escalate, never downgrade within a session (until reset by reading)
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
# Only check if there are unverified edits
if [ "$EDIT_COUNT" -gt 0 ]; then
  VERIFIED=false
  if [ -f "$STATE_DIR/verified" ]; then
    VERIFIED=true
  fi

  if [ "$VERIFIED" = false ]; then
    # Only remind once per batch of edits (use a separate nudge tracker)
    VERIFY_NUDGE_FILE="$STATE_DIR/verify-nudged"
    VERIFY_NUDGE_COUNT=0
    [ -f "$VERIFY_NUDGE_FILE" ] && VERIFY_NUDGE_COUNT=$(cat "$VERIFY_NUDGE_FILE" | tr -d ' ')
    CURRENT_EDIT_HASH=$(wc -l < "$STATE_DIR/edits" | tr -d ' ')

    if [ "$VERIFY_NUDGE_COUNT" != "$CURRENT_EDIT_HASH" ]; then
      # Only show verify reminder if enough edits accumulated (avoid nagging on first edit)
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
```

**Step 2: Make executable**

```bash
chmod +x hooks/prompt-monitor.sh
```

**Step 3: Commit**

```bash
git add hooks/prompt-monitor.sh
git commit -m "feat: prompt-monitor hook with investigation gate and verify check"
```

---

### Task 7: Diagnose Skill

**Files:**
- Create: `skills/diagnose/SKILL.md`

**Step 1: Write SKILL.md**

```markdown
---
name: diagnose
description: Use when investigating a bug or unexpected behavior. Forces structured root-cause investigation before any code changes. Trace the call chain, document hypotheses, confirm the root cause, then fix.
---

# Structured Root-Cause Investigation

**You are in investigation mode.** Do NOT edit any code until you complete the protocol below.

## Protocol

### Step 1: Understand the symptom
- What exactly is the user reporting?
- What is the expected behavior vs actual behavior?
- Can you reproduce it? Under what conditions?

### Step 2: Trace the code path
- Read all files in the call chain from entry point to where the bug manifests
- For each file, note: what it does, what it passes to the next layer, where it could go wrong
- Do NOT skip files — read every file in the path

### Step 3: Form a hypothesis
- Based on the code you've read, what is the most likely root cause?
- What evidence supports this hypothesis?
- What would disprove it?
- Rate your confidence: LOW / MEDIUM / HIGH

### Step 4: Verify the hypothesis
- If confidence is LOW: read more files, check related tests, grep for similar patterns
- If confidence is MEDIUM: check edge cases and error handling in the suspected area
- If confidence is HIGH: proceed to Step 5

### Step 5: Present analysis
Before writing ANY code, present to the user:
1. **Root cause:** One sentence explaining what's broken and why
2. **Evidence:** Which files/lines confirmed this
3. **Proposed fix:** What you'll change and why
4. **Risk:** What else could this fix affect?

### Step 6: Implement and verify
- Apply the minimal fix
- Run build and tests
- Confirm the fix addresses the symptom

## Anti-Patterns to Avoid
- ❌ Editing a file you haven't read
- ❌ Trying a fix "to see if it works"
- ❌ Changing thresholds or config values as a first fix
- ❌ Adding try/catch blocks around the symptom instead of fixing the cause
- ❌ Declaring "this might be a platform limitation" without evidence
```

**Step 2: Commit**

```bash
git add skills/diagnose/SKILL.md
git commit -m "feat: add /diagnose skill for structured root-cause investigation"
```

---

### Task 8: Commands

**Files:**
- Create: `commands/patrol-on.md`
- Create: `commands/patrol-off.md`
- Create: `commands/patrol-status.md`
- Create: `commands/patrol-config.md`
- Create: `commands/patrol-help.md`

**Step 1: Write patrol-on.md**

```markdown
---
name: patrol-on
description: Force patrol mode on for this session — enables investigation gate and band-aid detection
---

# Patrol On

Run this command to activate patrol mode:

```bash
SESSION_ID="${CLAUDE_SESSION_ID:-default}"
STATE_DIR="/tmp/patrol-${SESSION_ID}"
mkdir -p "$STATE_DIR" 2>/dev/null
echo "on" > "$STATE_DIR/mode"
echo "Patrol mode activated"
```

Tell the user: "🛡️ Patrol mode ON. I'll now enforce investigation before edits and detect band-aid patterns."
```

**Step 2: Write patrol-off.md**

```markdown
---
name: patrol-off
description: Disable patrol mode for this session
---

# Patrol Off

Run this command to deactivate patrol mode:

```bash
SESSION_ID="${CLAUDE_SESSION_ID:-default}"
STATE_DIR="/tmp/patrol-${SESSION_ID}"
mkdir -p "$STATE_DIR" 2>/dev/null
echo "off" > "$STATE_DIR/mode"
echo "Patrol mode deactivated"
```

Tell the user: "Patrol mode OFF for this session. Auto-detection still applies unless disabled in config."
```

**Step 3: Write patrol-status.md**

```markdown
---
name: patrol-status
description: Show current patrol state — mode, tracked reads/edits, verification status
---

# Patrol Status

Run this diagnostic and show the output to the user:

```bash
SESSION_ID="${CLAUDE_SESSION_ID:-default}"
STATE_DIR="/tmp/patrol-${SESSION_ID}"

echo "=== Patrol Status ==="
echo ""

# Mode
MODE="auto-detect"
[ -f "$STATE_DIR/mode" ] && MODE=$(cat "$STATE_DIR/mode")
echo "Mode: $MODE"

# Reads
READ_COUNT=0
[ -f "$STATE_DIR/reads" ] && READ_COUNT=$(wc -l < "$STATE_DIR/reads" | tr -d ' ')
echo "Files read: $READ_COUNT"

# Edits
EDIT_COUNT=0
[ -f "$STATE_DIR/edits" ] && EDIT_COUNT=$(wc -l < "$STATE_DIR/edits" | tr -d ' ')
echo "Files edited: $EDIT_COUNT"

# Unread edits
if [ "$EDIT_COUNT" -gt 0 ] && [ -f "$STATE_DIR/edits" ]; then
  if [ -f "$STATE_DIR/reads" ]; then
    UNREAD=$(comm -23 <(sort -u "$STATE_DIR/edits") <(sort -u "$STATE_DIR/reads") | wc -l | tr -d ' ')
  else
    UNREAD=$EDIT_COUNT
  fi
  echo "Edits without prior read: $UNREAD"
fi

# Nudge level
NUDGE=0
[ -f "$STATE_DIR/nudge-level" ] && NUDGE=$(cat "$STATE_DIR/nudge-level")
LEVEL_NAMES=("silent" "🔵 nudge" "🟡 warning" "🚨 STOP")
echo "Escalation level: ${LEVEL_NAMES[$NUDGE]:-$NUDGE}"

# Verification
if [ -f "$STATE_DIR/verified" ]; then
  TIMESTAMP=$(cat "$STATE_DIR/verified")
  echo "Last verified: $(date -r "$TIMESTAMP" '+%H:%M:%S' 2>/dev/null || echo "$TIMESTAMP")"
else
  echo "Last verified: never"
fi

# Config
echo ""
echo "=== Config ==="
if [ -f "$HOME/.patrol/config.json" ]; then
  cat "$HOME/.patrol/config.json" | jq .
else
  echo "(no global config — using defaults)"
fi

if [ -f ".patrol/config.json" ]; then
  echo ""
  echo "Project override:"
  cat ".patrol/config.json" | jq .
fi
```
```

**Step 4: Write patrol-config.md**

```markdown
---
name: patrol-config
description: Show or edit patrol configuration
---

# Patrol Config

Show the current config and help the user modify it:

**Global config:** `~/.patrol/config.json`
**Project override:** `.patrol/config.json` (in project root)

| Setting | Default | Description |
|---------|---------|-------------|
| `enabled` | `true` | Enable/disable patrol globally |
| `auto_detect_bugfix` | `true` | Auto-detect bug-fix sessions from keywords |
| `keywords` | `["fix","bug","broken","error","crash","doesn't work","not working"]` | Keywords that trigger bug-fix mode |
| `band_aid_threshold` | `3` | Consecutive edits before escalating to warning |
| `verify_commands` | `"auto"` | Build/test commands (or "auto" to detect) |
| `escalation` | `"siren"` | Escalation style |
| `disabled_hooks` | `[]` | Hooks to disable (e.g., `["tool-tracker"]`) |
| `debug` | `false` | Enable debug logging to `~/.patrol/debug.log` |

To modify, ask the user what they'd like to change, then update the appropriate config file.

Example:
```bash
# Set globally
mkdir -p ~/.patrol
echo '{"verify_commands": ["pnpm test", "pnpm run build"]}' | jq . > ~/.patrol/config.json

# Set per-project
mkdir -p .patrol
echo '{"verify_commands": ["cargo test"]}' | jq . > .patrol/config.json
```
```

**Step 5: Write patrol-help.md**

```markdown
---
name: patrol-help
description: List all Patrol commands, skills, and config options
---

# Patrol Help

Show the user this reference:

## Commands

| Command | Description |
|---------|-------------|
| `/patrol-on` | Force patrol mode on for this session |
| `/patrol-off` | Disable patrol mode for this session |
| `/patrol-status` | Diagnostic — show mode, tracking state, config |
| `/patrol-config` | Show/edit config |
| `/patrol-help` | This help |

## Skills

| Skill | Description |
|-------|-------------|
| `/diagnose` | Structured root-cause investigation — trace, hypothesize, verify, then fix |

## How It Works

```
Normal coding                    → silent (zero tokens)
Bug-fix detected (auto/manual)   → investigation gate active
  Edit without Read              → 🔵 nudge
  3+ edits without investigation → 🟡 warning
  4+ consecutive patches         → 🚨 STOP
Files changed, no build/test     → 🔧 reminder
```

## Config

**Global:** `~/.patrol/config.json`
**Per-project:** `.patrol/config.json` (overrides global)
**Auto-detect:** Package manager (pnpm > yarn > npm), project type (Cargo, pytest, go, make)

| Setting | Default | Description |
|---------|---------|-------------|
| `enabled` | `true` | Enable/disable patrol |
| `auto_detect_bugfix` | `true` | Auto-detect bug-fix sessions |
| `keywords` | `["fix","bug",...]` | Trigger keywords |
| `band_aid_threshold` | `3` | Edits before warning |
| `verify_commands` | `"auto"` | Build/test commands |
| `debug` | `false` | Debug logging |
```

**Step 6: Commit**

```bash
git add commands/
git commit -m "feat: add patrol commands (on, off, status, config, help)"
```

---

### Task 9: README

**Files:**
- Create: `README.md`

**Step 1: Write README.md**

Write a README following the Remembrall style:
- Catchy tagline with Star Wars hint
- Quick install block
- ASCII visualization of the escalation system
- "How It Works" diagram
- Three Layers of Protection section
- Full docs in collapsible `<details>`
- Config reference, troubleshooting, FAQ
- Privacy section

Key elements:
```
# Patrol

*"Investigate, you must. Band-aid, you must not."*

**Claude jumps to fixes before understanding the problem.** Patrol stops that.

### Install
claude plugin marketplace add cukas/patrol
claude plugin install patrol@cukas

That's it. Patrol monitors Claude's behavior and enforces investigation discipline.

🔵 Nudge  →  🟡 Warning  →  🚨 STOP
```

Include the escalation visualization, how-it-works diagram, and all sections from design doc. See full README content in implementation.

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README with install, usage, and configuration reference"
```

---

### Task 10: Git Init and Final Verification

**Step 1: Initialize git repo (if not already)**

```bash
cd /Users/nicolascukas/Web/patrol
git init
```

**Step 2: Verify all files are present**

```bash
ls -R
# Expected:
# .claude-plugin/plugin.json
# .claude-plugin/marketplace.json
# .gitignore
# LICENSE
# README.md
# hooks/hooks.json
# hooks/lib.sh
# hooks/session-start.sh
# hooks/tool-tracker.sh
# hooks/prompt-monitor.sh
# skills/diagnose/SKILL.md
# commands/patrol-on.md
# commands/patrol-off.md
# commands/patrol-status.md
# commands/patrol-config.md
# commands/patrol-help.md
# docs/plans/*.md
```

**Step 3: Verify all hooks are executable**

```bash
chmod +x hooks/*.sh
ls -la hooks/*.sh
```

**Step 4: Test hooks locally**

```bash
# Test session-start (should output JSON with additionalContext)
echo '{"session_id":"test","source":"startup","cwd":"/tmp"}' | bash hooks/session-start.sh

# Test tool-tracker (should output nothing — silent)
echo '{"session_id":"test","tool_name":"Read","tool_input":{"file_path":"/tmp/test.ts"},"cwd":"/tmp"}' | bash hooks/tool-tracker.sh
echo $?  # Should be 0

# Test prompt-monitor (should output nothing with no edits)
echo '{"session_id":"test","cwd":"/tmp","user_message":"hello"}' | bash hooks/prompt-monitor.sh
```

**Step 5: Create initial commit with all files**

```bash
git add -A
git commit -m "feat: patrol v1.0.0 — development discipline enforcement for Claude Code"
```

**Step 6: Create GitHub repo and push**

```bash
gh repo create cukas/patrol --public --description "Development discipline enforcement for Claude Code — stop band-aiding, investigate first" --source . --push
```
