# Patrol Polish Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Polish Patrol with status line indicator, two-tier enforcement, keyword management, rich dashboard, and visual identity.

**Architecture:** Extend existing hook pipeline. `prompt-monitor.sh` gains a light/full tier system. `session-start.sh` auto-injects a status line snippet into `~/.claude/settings.json`. New `/patrol-keywords` command. Enriched `/patrol-status` and `/patrol-help` commands. Updated README with hero image.

**Tech Stack:** Bash, jq, Claude Code hooks/commands

**Design doc:** `docs/plans/2026-03-09-patrol-polish-design.md`

---

### Task 1: Add helper functions to lib.sh

**Files:**
- Modify: `hooks/lib.sh:209` (append after last function)

**Step 1: Write the failing test**

Add to `tests/run-tests.sh` before the session-start integration tests section:

```bash
# ── patrol_merged_keywords ───────────────────────────────────
printf "\n  patrol_merged_keywords:\n"

reset_config
result=$(run_lib patrol_merged_keywords)
assert_match "returns default keywords without config" "fix" "$result"
assert_match "defaults include German keyword" "Fehler" "$result"

reset_config
echo '{"custom_keywords": ["regression", "timeout"]}' > "$HOME/.patrol/config.json"
result=$(run_lib patrol_merged_keywords)
assert_match "includes custom keywords" "regression" "$result"
assert_match "still includes defaults" "fix" "$result"

# ── patrol_yoda_message ──────────────────────────────────────
printf "\n  patrol_yoda_message:\n"

reset_config
echo '{"easter_eggs": false}' > "$HOME/.patrol/config.json"
result=$(run_lib patrol_yoda_message "nudge" "2 unread")
assert_eq "returns normal message when easter_eggs disabled" "2 unread" "$result"

reset_config
echo '{"easter_eggs": true}' > "$HOME/.patrol/config.json"
result=$(run_lib patrol_yoda_message "nudge" "2 unread")
assert_match "returns yoda message when easter_eggs enabled" "hmm" "$result"

reset_config
echo '{"easter_eggs": true}' > "$HOME/.patrol/config.json"
result=$(run_lib patrol_yoda_message "warning" "3 patches")
assert_match "returns yoda warning" "band-aid this is" "$result"

reset_config
echo '{"easter_eggs": true}' > "$HOME/.patrol/config.json"
result=$(run_lib patrol_yoda_message "stop" "STOP")
assert_match "returns yoda stop" "investigate you must" "$result"
```

**Step 2: Run test to verify it fails**

Run: `bash tests/run-tests.sh`
Expected: FAIL — `patrol_merged_keywords: command not found`

**Step 3: Write implementation**

Append to `hooks/lib.sh`:

```bash
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
```

**Step 4: Run test to verify it passes**

Run: `bash tests/run-tests.sh`
Expected: All new tests PASS

**Step 5: Commit**

```bash
git add hooks/lib.sh tests/run-tests.sh
git commit -m "feat: add keyword merge and easter egg helpers to lib.sh"
```

---

### Task 2: Refactor prompt-monitor.sh for two-tier enforcement

**Files:**
- Modify: `hooks/prompt-monitor.sh` (full rewrite of mode determination + escalation)

**Step 1: Write the failing test**

Add to `tests/run-tests.sh` after the existing prompt-monitor tests, before cross-hook tests:

```bash
# ── Two-tier enforcement ────────────────────────────────────
printf "\n  Two-tier enforcement:\n"

# Light mode: always_on=true, no keywords → nudge fires but no escalation past level 1
reset_config
echo '{"always_on": true}' > "$HOME/.patrol/config.json"
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
echo "0" > "$STATE_DIR/nudge-level"
echo "/src/a.ts" > "$STATE_DIR/edits"
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"add a new feature\"}")
assert_match "light mode: nudge fires on unread edit" "edited without being read" "$result"
tier=$(cat "$STATE_DIR/tier" 2>/dev/null)
assert_eq "light mode: tier file written as light" "light" "$tier"

# Light mode: 4+ unread edits → stays at nudge, no STOP
reset_config
echo '{"always_on": true}' > "$HOME/.patrol/config.json"
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
echo "0" > "$STATE_DIR/nudge-level"
printf "/src/a.ts\n/src/b.ts\n/src/c.ts\n/src/d.ts\n" > "$STATE_DIR/edits"
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"add a new feature\"}")
assert_no_match "light mode: no STOP even with 4+ unread edits" "STOP" "$result"

# Full mode via keyword: STOP fires at 4+
reset_config
echo '{"always_on": true}' > "$HOME/.patrol/config.json"
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
echo "0" > "$STATE_DIR/nudge-level"
printf "/src/a.ts\n/src/b.ts\n/src/c.ts\n/src/d.ts\n" > "$STATE_DIR/edits"
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"fix the crash\"}")
assert_match "full mode: STOP fires at 4+ unread edits" "STOP" "$result"
tier=$(cat "$STATE_DIR/tier" 2>/dev/null)
assert_eq "full mode: tier file written as full" "full" "$tier"

# always_on=false: no keywords, no manual mode → silent (v1.1.0 behavior)
reset_config
echo '{"always_on": false}' > "$HOME/.patrol/config.json"
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
echo "0" > "$STATE_DIR/nudge-level"
echo "/src/a.ts" > "$STATE_DIR/edits"
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"add a new feature\"}")
assert_empty "always_on=false: silent without keywords" "$result"

# Custom keywords via custom_keywords config
reset_config
echo '{"custom_keywords": ["regression"]}' > "$HOME/.patrol/config.json"
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
echo "0" > "$STATE_DIR/nudge-level"
echo "/src/a.ts" > "$STATE_DIR/edits"
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"there is a regression\"}")
assert_match "custom_keywords triggers full mode" "Patrol" "$result"
```

**Step 2: Run test to verify it fails**

Run: `bash tests/run-tests.sh`
Expected: FAIL — light mode tests fail because always_on not yet implemented

**Step 3: Write implementation**

Refactor `hooks/prompt-monitor.sh` — key changes:

1. Replace hardcoded keyword list with `patrol_merged_keywords`
2. Add `always_on` config check
3. Determine tier (`light` or `full`) and write to state file
4. Light tier: only allows nudge level 1, skips warning/STOP
5. Full tier: existing behavior unchanged

The refactored mode determination section (lines 26-63) becomes:

```bash
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
```

The escalation section (lines 92-129) changes to respect tier:

```bash
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
```

The verify check section (lines 131-172) — change the mode check:

```bash
# ─── Check 2: Build/test verification ───────────────────────
# Skip verify check when patrol is explicitly off (not just non-bugfix)
if [ "$MANUAL_MODE" = "off" ] || [ "$TIER" = "off" ]; then
  exit 0
fi
```

Rest of verify check stays the same.

**Step 4: Run test to verify it passes**

Run: `bash tests/run-tests.sh`
Expected: All tests PASS (existing + new two-tier tests)

**Step 5: Commit**

```bash
git add hooks/prompt-monitor.sh tests/run-tests.sh
git commit -m "feat: two-tier enforcement model (light always-on + full bugfix)"
```

---

### Task 3: Auto-inject status line + compact banner in session-start.sh

**Files:**
- Modify: `hooks/session-start.sh`
- Modify: `hooks/lib.sh` (add status line injection helper)

**Step 1: Write the failing test**

Add to `tests/run-tests.sh` in the session-start section:

```bash
# Compact banner
reset_config
reset_state "$SID"
result=$(run_hook session-start.sh "{\"session_id\":\"$SID\",\"source\":\"startup\",\"cwd\":\"$PATROL_CWD\"}")
assert_match "compact startup banner" "Patrol active" "$result"
assert_no_match "no multi-line intro" "Detects bug-fix sessions" "$result"

# Writes initial tier file
reset_config
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
run_hook session-start.sh "{\"session_id\":\"$SID\",\"source\":\"startup\",\"cwd\":\"$PATROL_CWD\"}" >/dev/null
assert_file_exists "writes initial tier state file" "$STATE_DIR/tier"
tier=$(cat "$STATE_DIR/tier" 2>/dev/null)
assert_eq "initial tier is light (always_on default true)" "light" "$tier"

# Status line injection (test with a temp settings.json)
reset_config
reset_state "$SID"
FAKE_HOME="$TMPDIR_ROOT/statusline-test"
mkdir -p "$FAKE_HOME/.claude" "$FAKE_HOME/.patrol"
echo '{}' > "$FAKE_HOME/.patrol/config.json"
echo '{"statusLine":{"type":"command","command":"echo test"}}' > "$FAKE_HOME/.claude/settings.json"
HOME="$FAKE_HOME" run_hook session-start.sh "{\"session_id\":\"$SID\",\"source\":\"startup\",\"cwd\":\"$PATROL_CWD\"}" >/dev/null
settings_content=$(cat "$FAKE_HOME/.claude/settings.json")
assert_match "injects patrol snippet into settings.json" "patrol-state" "$settings_content"

# Idempotent: second run doesn't double-inject
HOME="$FAKE_HOME" run_hook session-start.sh "{\"session_id\":\"$SID\",\"source\":\"startup\",\"cwd\":\"$PATROL_CWD\"}" >/dev/null
count=$(grep -o "patrol-state" "$FAKE_HOME/.claude/settings.json" | wc -l | tr -d ' ')
assert_eq "idempotent: only one patrol-state marker" "1" "$count"
```

**Step 2: Run test to verify it fails**

Run: `bash tests/run-tests.sh`
Expected: FAIL — compact banner test fails (old multi-line still present)

**Step 3: Write implementation**

Add to `hooks/lib.sh` — the status line injection function:

```bash
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
  # Uses session_id variable already extracted by existing status line
  # Reads state from /tmp/patrol-{session_id}/ written by tool-tracker + prompt-monitor
  local patrol_snippet
  patrol_snippet='PATROL_DIR="/tmp/patrol-${session_id}"; if [ -d "$PATROL_DIR" ]; then p_tier=$(cat "$PATROL_DIR/tier" 2>/dev/null); p_mode=$(cat "$PATROL_DIR/mode" 2>/dev/null); p_nudge=$(cat "$PATROL_DIR/nudge-level" 2>/dev/null | tr -d "[:space:]"); p_edits=0; p_reads=0; p_unread=0; [ -f "$PATROL_DIR/edits" ] && p_edits=$(wc -l < "$PATROL_DIR/edits" | tr -d " "); [ -f "$PATROL_DIR/reads" ] && p_reads=$(wc -l < "$PATROL_DIR/reads" | tr -d " "); if [ "$p_edits" -gt 0 ] && [ -f "$PATROL_DIR/edits" ]; then if [ -f "$PATROL_DIR/reads" ]; then p_unread=$(comm -23 <(sort -u "$PATROL_DIR/edits") <(sort -u "$PATROL_DIR/reads") | wc -l | tr -d " "); else p_unread=$p_edits; fi; fi; p_verified=false; [ -f "$PATROL_DIR/verified" ] && p_verified=true; p_easter=$(jq -r ".easter_eggs // false" "$HOME/.patrol/config.json" 2>/dev/null); p_display=""; if [ "$p_mode" != "off" ]; then if [ "${p_nudge:-0}" -ge 3 ] 2>/dev/null; then if [ "$p_easter" = "true" ]; then p_display="$(printf '"'"'\033[31m'"'"')🚨 investigate you must$(printf '"'"'\033[0m'"'"')"; else p_display="$(printf '"'"'\033[31m'"'"')🚨 STOP$(printf '"'"'\033[0m'"'"')"; fi; elif [ "${p_nudge:-0}" -ge 2 ] 2>/dev/null; then if [ "$p_easter" = "true" ]; then p_display="$(printf '"'"'\033[33m'"'"')🟡 band-aid this is$(printf '"'"'\033[0m'"'"')"; else p_display="$(printf '"'"'\033[33m'"'"')🟡 ${p_edits} patches$(printf '"'"'\033[0m'"'"')"; fi; elif [ "$p_unread" -ge 1 ] 2>/dev/null; then if [ "$p_easter" = "true" ]; then p_display="$(printf '"'"'\033[33m'"'"')🛡️ ${p_unread} unread, hmm$(printf '"'"'\033[0m'"'"')"; else p_display="$(printf '"'"'\033[33m'"'"')🛡️ ${p_unread} unread$(printf '"'"'\033[0m'"'"')"; fi; elif [ "$p_edits" -gt 0 ] || [ "$p_reads" -gt 0 ]; then if [ "$p_tier" = "full" ]; then p_display="$(printf '"'"'\033[32m'"'"')🛡️ bugfix · 📖${p_reads} ✏️${p_edits}$(printf '"'"'\033[0m'"'"')"; else p_display="$(printf '"'"'\033[32m'"'"')🛡️ 📖${p_reads} ✏️${p_edits}$(printf '"'"'\033[0m'"'"')"; fi; else if [ "$p_tier" != "off" ]; then p_display="🛡️"; fi; fi; if [ "$p_verified" = true ] && [ -n "$p_display" ]; then p_display="${p_display} ✅"; fi; fi; if [ -n "$p_display" ]; then status="$status | $p_display"; fi; fi; # patrol-state'

  if [ -z "$has_statusline" ]; then
    # No existing status line — warn but don't create one from scratch
    # (Patrol's snippet depends on $session_id and $status being set by existing status line)
    patrol_debug "WARNING: no statusLine.command found in settings.json — skipping injection"
    echo "Patrol: no status line found in settings.json — run /patrol-setup or add a status line first" >&2
    return 0
  fi

  # Append snippet to existing command
  local new_command
  new_command=$(jq -r '.statusLine.command' "$settings_file" 2>/dev/null)
  new_command="${new_command}; ${patrol_snippet}"

  # Write back atomically
  local tmp
  tmp=$(mktemp "${settings_file}.XXXXXX")
  jq --arg cmd "$new_command" '.statusLine.command = $cmd' "$settings_file" > "$tmp" 2>/dev/null
  if [ $? -eq 0 ] && [ -s "$tmp" ]; then
    mv "$tmp" "$settings_file"
    patrol_debug "status line auto-configured in settings.json"
    echo "Patrol: status line configured in settings.json" >&2
  else
    rm -f "$tmp"
    patrol_debug "ERROR: failed to write settings.json"
  fi
}
```

Rewrite `hooks/session-start.sh`:

```bash
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
if [ -n "$SESSION_ID" ]; then
  STATE_DIR=$(patrol_state_dir "$SESSION_ID")
  rm -f "$STATE_DIR/reads" "$STATE_DIR/edits" "$STATE_DIR/verified" "$STATE_DIR/nudge-level" "$STATE_DIR/verify-nudged" 2>/dev/null
  echo "0" > "$STATE_DIR/nudge-level"

  # Write initial tier based on always_on config
  ALWAYS_ON=$(patrol_config "always_on" "true")
  if [ "$ALWAYS_ON" = "true" ]; then
    echo "light" > "$STATE_DIR/tier"
  else
    echo "off" > "$STATE_DIR/tier"
  fi

  # Preserve manual mode across clear/compact, reset on fresh startup
  if [ "$SOURCE" = "startup" ]; then
    rm -f "$STATE_DIR/mode" 2>/dev/null
  fi
fi

# Auto-inject status line on startup (not on clear/compact)
if [ "$SOURCE" = "startup" ]; then
  _patrol_ensure_statusline
fi

INTRO="🛡️ Patrol active · /patrol-help for commands"

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

**Step 4: Run test to verify it passes**

Run: `bash tests/run-tests.sh`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add hooks/session-start.sh hooks/lib.sh tests/run-tests.sh
git commit -m "feat: auto-inject status line + compact startup banner"
```

---

### Task 4: Create `/patrol-keywords` command

**Files:**
- Create: `commands/patrol-keywords.md`

**Step 1: Write the command**

```markdown
---
name: patrol-keywords
description: Manage custom trigger keywords — list, add, remove, or reset
---

# Patrol Keywords

Manage the keywords that trigger bug-fix mode. Custom keywords extend the built-in defaults.

## Instructions

1. Parse the user's arguments (text after `/patrol-keywords`):
   - No arguments → list all keywords
   - `add "word1" "word2" ...` → add to custom_keywords
   - `remove "word"` → remove from custom_keywords
   - `reset` → clear all custom keywords

2. Read current config:
```bash
cat ~/.patrol/config.json 2>/dev/null || echo '{}'
```

3. For **list**: show defaults and custom separately:

**Default keywords** (built-in, always active):
fix, bug, broken, error, crash, doesn't work, not working, Fehler, kaputt, Absturz, funktioniert nicht, erreur, plantage, cassé, ne marche pas

**Custom keywords** (from config):
[list from custom_keywords array, or "none" if empty]

4. For **add**: read current `custom_keywords` array, append new words, write back:
```bash
# Read current
CURRENT=$(jq -r '.custom_keywords // []' ~/.patrol/config.json 2>/dev/null || echo '[]')
# Add new words (replace WORDS with actual words)
NEW=$(echo "$CURRENT" | jq --arg w "WORD" '. + [$w] | unique')
# Write back using jq
jq --argjson kw "$NEW" '.custom_keywords = $kw' ~/.patrol/config.json > /tmp/patrol-config-tmp.json && mv /tmp/patrol-config-tmp.json ~/.patrol/config.json
```

5. For **remove**: filter out the word:
```bash
jq --arg w "WORD" '.custom_keywords = (.custom_keywords // [] | map(select(. != $w)))' ~/.patrol/config.json > /tmp/patrol-config-tmp.json && mv /tmp/patrol-config-tmp.json ~/.patrol/config.json
```

6. For **reset**: remove custom_keywords key:
```bash
jq 'del(.custom_keywords)' ~/.patrol/config.json > /tmp/patrol-config-tmp.json && mv /tmp/patrol-config-tmp.json ~/.patrol/config.json
```

7. Show confirmation with the updated keyword list.
```

**Step 2: Commit**

```bash
git add commands/patrol-keywords.md
git commit -m "feat: add /patrol-keywords command for custom keyword management"
```

---

### Task 5: Rewrite `/patrol-status` with rich dashboard

**Files:**
- Modify: `commands/patrol-status.md`

**Step 1: Write the new command**

Replace entire content of `commands/patrol-status.md`:

```markdown
---
name: patrol-status
description: Show patrol dashboard — mode, tier, health, verification, config
---

# Patrol Status Dashboard

Run this diagnostic and present the output as a formatted dashboard:

```bash
SESSION_ID="${CLAUDE_SESSION_ID:-default}"
STATE_DIR="/tmp/patrol-${SESSION_ID}"

# Mode
MODE="watching"
TIER="off"
[ -f "$STATE_DIR/mode" ] && MODE=$(cat "$STATE_DIR/mode")
[ -f "$STATE_DIR/tier" ] && TIER=$(cat "$STATE_DIR/tier")

# Reads/Edits
READ_COUNT=0
EDIT_COUNT=0
UNREAD=0
[ -f "$STATE_DIR/reads" ] && READ_COUNT=$(wc -l < "$STATE_DIR/reads" | tr -d ' ')
[ -f "$STATE_DIR/edits" ] && EDIT_COUNT=$(wc -l < "$STATE_DIR/edits" | tr -d ' ')
if [ "$EDIT_COUNT" -gt 0 ] && [ -f "$STATE_DIR/edits" ]; then
  if [ -f "$STATE_DIR/reads" ]; then
    UNREAD=$(comm -23 <(sort -u "$STATE_DIR/edits") <(sort -u "$STATE_DIR/reads") | wc -l | tr -d ' ')
  else
    UNREAD=$EDIT_COUNT
  fi
fi

# Nudge level
NUDGE=0
[ -f "$STATE_DIR/nudge-level" ] && NUDGE=$(cat "$STATE_DIR/nudge-level" | tr -d '[:space:]')

# Verification
VERIFY_STATUS="never"
if [ -f "$STATE_DIR/verified" ]; then
  TIMESTAMP=$(cat "$STATE_DIR/verified")
  NOW=$(date +%s)
  AGO=$(( (NOW - TIMESTAMP) / 60 ))
  if [ "$AGO" -lt 1 ]; then
    VERIFY_STATUS="just now"
  else
    VERIFY_STATUS="${AGO}m ago"
  fi
fi

# Custom keywords count
CUSTOM_KW=0
if [ -f "$HOME/.patrol/config.json" ]; then
  CUSTOM_KW=$(jq -r '.custom_keywords // [] | length' "$HOME/.patrol/config.json" 2>/dev/null)
fi

# Config values
ALWAYS_ON=$(jq -r '.always_on // true' "$HOME/.patrol/config.json" 2>/dev/null || echo "true")
EASTER_EGGS=$(jq -r '.easter_eggs // false' "$HOME/.patrol/config.json" 2>/dev/null || echo "false")
THRESHOLD=$(jq -r '.band_aid_threshold // 3' "$HOME/.patrol/config.json" 2>/dev/null || echo "3")
AUTO_DETECT=$(jq -r '.auto_detect_bugfix // true' "$HOME/.patrol/config.json" 2>/dev/null || echo "true")

echo "MODE=$MODE"
echo "TIER=$TIER"
echo "READS=$READ_COUNT"
echo "EDITS=$EDIT_COUNT"
echo "UNREAD=$UNREAD"
echo "NUDGE=$NUDGE"
echo "VERIFY=$VERIFY_STATUS"
echo "CUSTOM_KW=$CUSTOM_KW"
echo "ALWAYS_ON=$ALWAYS_ON"
echo "EASTER_EGGS=$EASTER_EGGS"
echo "THRESHOLD=$THRESHOLD"
echo "AUTO_DETECT=$AUTO_DETECT"
```

Present the output as this formatted dashboard (fill in actual values):

```
╭──────────────────── Patrol ─────────────────────╮
│  Mode:     {icon} {mode description}            │
│  Tier:     {tier description}                   │
│  Health:   🛡️ 📖{reads} ✏️{edits}               │
│  Unread:   {unread} file(s) edited without read │
│  Verify:   {verify status}                      │
│  Keywords: 14 default + {custom} custom         │
│  Config:   ~/.patrol/config.json                │
├─────────────────────────────────────────────────┤
│  always_on: {val} | easter_eggs: {val}          │
│  threshold: {val} | auto_detect: {val}          │
╰─────────────────────────────────────────────────╯
```

Mode icons:
- MODE=on → `🟢 bugfix (manual)`
- MODE=auto or TIER=full → `🟢 bugfix (auto-detected)`
- MODE=watching + TIER=light → `⚪ watching (always-on light)`
- MODE=off → `🔴 disabled (/patrol-off)`
- TIER=off + no mode → `⚪ inactive`

Tier descriptions:
- full → `Full escalation (nudge → warning → STOP)`
- light → `Light (nudge only, no STOP)`
- off → `Off`

Nudge level labels:
- 0 → `silent`
- 1 → `nudge 🔵`
- 2 → `warning 🟡`
- 3 → `STOP 🚨`

Verify status:
- "never" → `⏳ no build/test run yet`
- time value → `✅ {time}`
```

**Step 2: Commit**

```bash
git add commands/patrol-status.md
git commit -m "feat: rich /patrol-status dashboard with box-drawing"
```

---

### Task 6: Update `/patrol-help` with new features

**Files:**
- Modify: `commands/patrol-help.md`

**Step 1: Update the command**

Replace content of `commands/patrol-help.md`:

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
| `/patrol-on` | Force full patrol mode on for this session |
| `/patrol-off` | Disable patrol mode for this session |
| `/patrol-status` | Dashboard — mode, tier, health, verification, config |
| `/patrol-keywords` | Manage custom trigger keywords (list/add/remove/reset) |
| `/patrol-config` | Show/edit configuration |
| `/patrol-help` | This help |

## Skills

| Skill | Description |
|-------|-------------|
| `/diagnose` | Structured root-cause investigation — trace, hypothesize, verify, then fix |

## How It Works

```
Two-tier enforcement:

  Light mode (always-on)           → read-before-edit nudge + build/test reminder
  Full mode (bugfix keyword/manual) → full escalation + band-aid detection + STOP gate

  Status line (real-time):
    🛡️                              → watching, no activity
    🛡️ 📖4 ✏️2                      → healthy: 4 files read, 2 edited
    🛡️ bugfix · 📖4 ✏️2             → bugfix mode, healthy
    🟡 2 unread                     → warning: edits without reads
    🚨 STOP                         → hard stop: investigate now
    ✅                              → build/test verified
```

## Config

**Global:** `~/.patrol/config.json`
**Per-project:** `.patrol/config.json` (overrides global)

| Setting | Default | Description |
|---------|---------|-------------|
| `enabled` | `true` | Enable/disable patrol |
| `always_on` | `true` | Light mode active even without bugfix keywords |
| `auto_detect_bugfix` | `true` | Auto-detect bug-fix sessions from keywords |
| `custom_keywords` | `[]` | Additional trigger keywords (extend defaults) |
| `band_aid_threshold` | `3` | Edits before warning in full mode |
| `verify_commands` | `"auto"` | Build/test commands (or auto-detect) |
| `easter_eggs` | `false` | Yoda-themed messages |
| `debug` | `false` | Debug logging to ~/.patrol/debug.log |
```

**Step 2: Commit**

```bash
git add commands/patrol-help.md
git commit -m "docs: update /patrol-help with two-tier model and new commands"
```

---

### Task 7: Update tests for existing behavior changes

**Files:**
- Modify: `tests/run-tests.sh`

**Step 1: Fix existing tests broken by compact banner**

The existing session-start test checks for `hookSpecificOutput` — the compact banner still uses this, so it should pass. But the verify check tests need updating because the verify section now checks `TIER` instead of `MANUAL_MODE`:

- Tests that set `auto_detect_bugfix: false` and expect verify reminders: these now need `always_on: true` to be set (or it defaults to true, so they should work).
- Tests that set `mode=off` and expect silence: these still work since `MANUAL_MODE=off` → `TIER=off`.

Review each existing test and ensure it still passes with the two-tier changes. The key change is the verify check condition: old code checked `MANUAL_MODE = "off"`, new code checks `MANUAL_MODE = "off" || TIER = "off"`.

**Step 2: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests PASS

**Step 3: Commit**

```bash
git add tests/run-tests.sh
git commit -m "test: update tests for two-tier enforcement and compact banner"
```

---

### Task 8: Update README.md with hero image and new docs

**Files:**
- Modify: `README.md`

**Step 1: Add hero image and update feature descriptions**

At the top of README.md, add hero image:

```markdown
<div align="center">
  <img src="docs/patrol-hero.png" alt="Patrol" width="600">
</div>

# Patrol
```

Update the quick overview section to show the status line and two-tier model. Update the config table to include new settings (`always_on`, `custom_keywords`, `easter_eggs`). Add `/patrol-keywords` to the commands table. Update the "How It Works" diagram to show light vs full mode.

Keep the existing detailed docs in the `<details>` section but update them to match the new behavior.

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add hero image and update README for v2.0.0"
```

---

### Task 9: Version bump + changelog

**Files:**
- Modify: `.claude-plugin/plugin.json:6` (version "1.1.0" → "2.0.0")
- Modify: `CHANGELOG.md`

**Step 1: Bump version**

In `.claude-plugin/plugin.json`, change version to `"2.0.0"`.

**Step 2: Update changelog**

Prepend to `CHANGELOG.md`:

```markdown
## v2.0.0 — 2026-03-09

### Added
- **Status line indicator** — real-time adaptive display showing read/edit counts, mode, and escalation level
- **Two-tier enforcement** — light mode (always-on, nudge only) + full mode (bugfix, full escalation)
- **`/patrol-keywords`** — manage custom trigger keywords (list/add/remove/reset)
- **`always_on` config** — light discipline enforcement even outside bugfix sessions (default: true)
- **`easter_eggs` config** — opt-in Yoda-themed messages
- **`custom_keywords` config** — extend default keywords without replacing them
- **Rich `/patrol-status` dashboard** — box-drawn display with mode, tier, health, verification
- **Hero image** — shield sentinel visual identity

### Changed
- Startup banner condensed to single line (status line carries the detail now)
- `/patrol-help` updated with two-tier model and new commands
- Keyword matching now uses merged defaults + custom_keywords
- Verify check respects tier (active in both light and full mode)

### Migration from v1.x
- No breaking changes. Existing config continues to work.
- `keywords` config still works but `custom_keywords` is preferred (extends defaults instead of replacing).
- Set `always_on: false` to restore v1.x behavior (silent until bugfix detected).
```

**Step 3: Commit**

```bash
git add .claude-plugin/plugin.json CHANGELOG.md
git commit -m "chore: bump version to 2.0.0"
```

---

### Task 10: Final integration test

**Step 1: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests PASS, 0 failures

**Step 2: Manual smoke test**

Verify in a real Claude Code session:
1. Start new session → see compact banner `🛡️ Patrol active`
2. Status line shows `🛡️` (watching, light mode)
3. Edit a file without reading → status line shows `🛡️ 1 unread`
4. Type "fix the bug" → status line shows `🛡️ bugfix · 📖0 ✏️1`
5. Run `/patrol-status` → see rich dashboard
6. Run `/patrol-keywords` → see keyword list
7. Run `/patrol-keywords add "regression"` → confirmation

**Step 3: Tag release**

```bash
git tag v2.0.0
```
