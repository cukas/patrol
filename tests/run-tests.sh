#!/usr/bin/env bash
# Patrol test runner — zero external dependencies
# Usage: bash tests/run-tests.sh
set -euo pipefail

# ─── Globals ──────────────────────────────────────────────────
PASS=0
FAIL=0
ERRORS=""
PATROL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR_ROOT=$(mktemp -d "/tmp/patrol-test-XXXXXX")

cleanup() {
  rm -rf "$TMPDIR_ROOT"
  rm -rf /tmp/patrol-test-*
}
trap cleanup EXIT

# ─── Isolated HOME and CWD ──────────────────────────────────
export HOME="$TMPDIR_ROOT/home"
mkdir -p "$HOME/.patrol"
export PATROL_CWD="$TMPDIR_ROOT/project"
mkdir -p "$PATROL_CWD/.patrol"

# ─── Helpers ──────────────────────────────────────────────────
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    printf "  ✓ %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${label}\n    expected: ${expected}\n    actual:   ${actual}"
    printf "  ✗ %s\n    expected: %s\n    actual:   %s\n" "$label" "$expected" "$actual"
  fi
}

assert_match() {
  local label="$1" pattern="$2" actual="$3"
  if printf '%s\n' "$actual" | grep -qE "$pattern"; then
    PASS=$((PASS + 1))
    printf "  ✓ %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${label}\n    pattern: ${pattern}\n    actual:  ${actual}"
    printf "  ✗ %s\n    pattern: %s\n    actual:  %s\n" "$label" "$pattern" "$actual"
  fi
}

assert_no_match() {
  local label="$1" pattern="$2" actual="$3"
  if printf '%s\n' "$actual" | grep -qE "$pattern"; then
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${label}\n    should NOT match: ${pattern}\n    actual:  ${actual}"
    printf "  ✗ %s\n    should NOT match: %s\n    actual:  %s\n" "$label" "$pattern" "$actual"
  else
    PASS=$((PASS + 1))
    printf "  ✓ %s\n" "$label"
  fi
}

assert_empty() {
  local label="$1" actual="$2"
  if [ -z "$actual" ]; then
    PASS=$((PASS + 1))
    printf "  ✓ %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${label}\n    expected empty, got: ${actual}"
    printf "  ✗ %s\n    expected empty, got: %s\n" "$label" "$actual"
  fi
}

assert_not_empty() {
  local label="$1" actual="$2"
  if [ -n "$actual" ]; then
    PASS=$((PASS + 1))
    printf "  ✓ %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${label}\n    expected non-empty string"
    printf "  ✗ %s\n    expected non-empty string\n" "$label"
  fi
}

assert_exit_code() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    printf "  ✓ %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${label}\n    expected exit code: ${expected}\n    actual exit code:   ${actual}"
    printf "  ✗ %s\n    expected exit code: %s\n    actual exit code:   %s\n" "$label" "$expected" "$actual"
  fi
}

assert_file_exists() {
  local label="$1" path="$2"
  if [ -f "$path" ]; then
    PASS=$((PASS + 1))
    printf "  ✓ %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${label}\n    file not found: ${path}"
    printf "  ✗ %s\n    file not found: %s\n" "$label" "$path"
  fi
}

assert_file_not_exists() {
  local label="$1" path="$2"
  if [ ! -f "$path" ]; then
    PASS=$((PASS + 1))
    printf "  ✓ %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${label}\n    file should not exist: ${path}"
    printf "  ✗ %s\n    file should not exist: %s\n" "$label" "$path"
  fi
}

# Reset config between tests
reset_config() {
  rm -f "$HOME/.patrol/config.json"
  rm -f "$PATROL_CWD/.patrol/config.json"
  echo '{}' > "$HOME/.patrol/config.json"
}

# Reset state directory for a given session
reset_state() {
  local sid="${1:-test-session}"
  rm -rf "/tmp/patrol-${sid}"
  mkdir -p "/tmp/patrol-${sid}"
}

# Source lib.sh in a subshell and run a function
run_lib() {
  (
    source "$PATROL_ROOT/hooks/lib.sh"
    "$@"
  )
}

# Run a hook with JSON input (tolerates non-zero exit from hooks)
run_hook() {
  local hook="$1"
  local json="$2"
  echo "$json" | bash "$PATROL_ROOT/hooks/${hook}" || true
}

# ─── Banner ──────────────────────────────────────────────────
printf "\n══════════════════════════════════════════\n"
printf "  Patrol Test Suite\n"
printf "══════════════════════════════════════════\n\n"

# ══════════════════════════════════════════════════════════════
# 1. lib.sh unit tests
# ══════════════════════════════════════════════════════════════
printf "▸ lib.sh unit tests\n"

# ── patrol_config ────────────────────────────────────────────
printf "\n  patrol_config:\n"

reset_config
result=$(run_lib patrol_config "nonexistent_key" "default_val")
assert_eq "missing config returns default" "default_val" "$result"

reset_config
echo '{"threshold": "5"}' > "$HOME/.patrol/config.json"
result=$(run_lib patrol_config "threshold" "3")
assert_eq "global config value read correctly" "5" "$result"

reset_config
echo '{"threshold": "10"}' > "$HOME/.patrol/config.json"
echo '{"threshold": "20"}' > "$PATROL_CWD/.patrol/config.json"
result=$(run_lib patrol_config "threshold" "3")
assert_eq "project-level config overrides global" "20" "$result"

reset_config
echo '{"enabled": true, "count": 42, "name": "patrol"}' > "$HOME/.patrol/config.json"
result_bool=$(run_lib patrol_config "enabled" "false")
result_num=$(run_lib patrol_config "count" "0")
result_str=$(run_lib patrol_config "name" "default")
assert_eq "boolean stored as correct type" "true" "$result_bool"
assert_eq "number stored as correct type" "42" "$result_num"
assert_eq "string stored as correct type" "patrol" "$result_str"

reset_config
echo '{"threshold": "10"}' > "$HOME/.patrol/config.json"
rm -f "$PATROL_CWD/.patrol/config.json"
result=$(run_lib patrol_config "threshold" "3")
assert_eq "missing key falls through to global" "10" "$result"

reset_config
echo '{"other": "val"}' > "$PATROL_CWD/.patrol/config.json"
echo '{"threshold": "10"}' > "$HOME/.patrol/config.json"
result=$(run_lib patrol_config "threshold" "3")
assert_eq "project config without key falls through to global" "10" "$result"

# ── patrol_config_set ────────────────────────────────────────
printf "\n  patrol_config_set:\n"

reset_config
rm -f "$HOME/.patrol/config.json"
run_lib patrol_config_set "mykey" "myval"
assert_file_exists "creates config file if missing" "$HOME/.patrol/config.json"

reset_config
run_lib patrol_config_set "flag" "true"
result=$(jq -r '.flag | type' "$HOME/.patrol/config.json")
assert_eq "boolean stored as JSON boolean" "boolean" "$result"

reset_config
run_lib patrol_config_set "count" "42"
result=$(jq -r '.count | type' "$HOME/.patrol/config.json")
assert_eq "number stored as JSON number" "number" "$result"

reset_config
run_lib patrol_config_set "name" "hello world"
result=$(jq -r '.name | type' "$HOME/.patrol/config.json")
assert_eq "string stored as JSON string" "string" "$result"
result_val=$(jq -r '.name' "$HOME/.patrol/config.json")
assert_eq "string value is correct" "hello world" "$result_val"

# ── patrol_hook_enabled ──────────────────────────────────────
printf "\n  patrol_hook_enabled:\n"

reset_config
echo '{}' > "$HOME/.patrol/config.json"
run_lib patrol_hook_enabled "tool-tracker"
ec=$?
assert_exit_code "returns 0 (enabled) when hook not in disabled list" "0" "$ec"

reset_config
echo '{"disabled_hooks": ["tool-tracker", "prompt-monitor"]}' > "$HOME/.patrol/config.json"
run_lib patrol_hook_enabled "tool-tracker" || ec=$?
assert_exit_code "returns 1 (disabled) when hook is in disabled list" "1" "${ec:-0}"

reset_config
echo '{"disabled_hooks": []}' > "$HOME/.patrol/config.json"
run_lib patrol_hook_enabled "session-start"
ec=$?
assert_exit_code "works with empty disabled_hooks array" "0" "$ec"

# ── patrol_state_dir ─────────────────────────────────────────
printf "\n  patrol_state_dir:\n"

SID="unit-test-$$"
rm -rf "/tmp/patrol-${SID}"
result=$(run_lib patrol_state_dir "$SID")
assert_eq "returns correct path" "/tmp/patrol-${SID}" "$result"
if [ -d "$result" ]; then
  PASS=$((PASS + 1))
  printf "  ✓ %s\n" "creates directory in /tmp"
else
  FAIL=$((FAIL + 1))
  ERRORS="${ERRORS}\n  FAIL: creates directory in /tmp\n    directory not found: ${result}"
  printf "  ✗ %s\n    directory not found: %s\n" "creates directory in /tmp" "$result"
fi
rm -rf "/tmp/patrol-${SID}"

# ── patrol_detect_verify_commands ────────────────────────────
printf "\n  patrol_detect_verify_commands:\n"

DETECT_DIR="$TMPDIR_ROOT/detect-empty"
mkdir -p "$DETECT_DIR"
result=$(run_lib patrol_detect_verify_commands "$DETECT_DIR")
assert_eq "returns empty array for unknown project type" "[]" "$result"

DETECT_DIR="$TMPDIR_ROOT/detect-npm"
mkdir -p "$DETECT_DIR"
echo '{"scripts":{"test":"jest"}}' > "$DETECT_DIR/package.json"
result=$(run_lib patrol_detect_verify_commands "$DETECT_DIR")
assert_match "detects npm with package.json + test script" "npm test" "$result"

DETECT_DIR="$TMPDIR_ROOT/detect-pnpm"
mkdir -p "$DETECT_DIR"
echo '{"scripts":{"test":"vitest"}}' > "$DETECT_DIR/package.json"
touch "$DETECT_DIR/pnpm-lock.yaml"
result=$(run_lib patrol_detect_verify_commands "$DETECT_DIR")
assert_match "detects pnpm from pnpm-lock.yaml" "pnpm test" "$result"

DETECT_DIR="$TMPDIR_ROOT/detect-yarn"
mkdir -p "$DETECT_DIR"
echo '{"scripts":{"test":"jest"}}' > "$DETECT_DIR/package.json"
touch "$DETECT_DIR/yarn.lock"
result=$(run_lib patrol_detect_verify_commands "$DETECT_DIR")
assert_match "detects yarn from yarn.lock" "yarn test" "$result"

DETECT_DIR="$TMPDIR_ROOT/detect-cargo"
mkdir -p "$DETECT_DIR"
echo '[package]' > "$DETECT_DIR/Cargo.toml"
result=$(run_lib patrol_detect_verify_commands "$DETECT_DIR")
assert_match "detects Cargo.toml" "cargo test" "$result"

DETECT_DIR="$TMPDIR_ROOT/detect-python"
mkdir -p "$DETECT_DIR"
echo '[project]' > "$DETECT_DIR/pyproject.toml"
result=$(run_lib patrol_detect_verify_commands "$DETECT_DIR")
assert_match "detects pyproject.toml" "pytest" "$result"

DETECT_DIR="$TMPDIR_ROOT/detect-go"
mkdir -p "$DETECT_DIR"
echo 'module example.com/test' > "$DETECT_DIR/go.mod"
result=$(run_lib patrol_detect_verify_commands "$DETECT_DIR")
assert_match "detects go.mod" "go test" "$result"

DETECT_DIR="$TMPDIR_ROOT/detect-make"
mkdir -p "$DETECT_DIR"
printf "test:\n\t@echo testing\n" > "$DETECT_DIR/Makefile"
result=$(run_lib patrol_detect_verify_commands "$DETECT_DIR")
assert_match "detects Makefile with test target" "make test" "$result"

# ── patrol_escape_json ────────────────────────────────────────
printf "\n  patrol_escape_json:\n"

result=$(run_lib patrol_escape_json 'say "hello"')
assert_match "escapes double quotes" '\\"hello\\"' "$result"

result=$(run_lib patrol_escape_json $'line1\nline2')
assert_match "escapes newlines" 'line1\\nline2' "$result"

result=$(run_lib patrol_escape_json 'simple')
assert_eq "simple string unchanged" "simple" "$result"

# ── patrol_append_capped ─────────────────────────────────────
printf "\n  patrol_append_capped:\n"

CAPPED_FILE="$TMPDIR_ROOT/capped-test"

# Basic append works
rm -f "$CAPPED_FILE"
run_lib patrol_append_capped "$CAPPED_FILE" "line1"
run_lib patrol_append_capped "$CAPPED_FILE" "line2"
count=$(wc -l < "$CAPPED_FILE" | tr -d ' ')
assert_eq "basic append writes lines" "2" "$count"

# Cap at 5 lines: write 7, should keep last 5
rm -f "$CAPPED_FILE"
for i in 1 2 3 4 5 6 7; do
  run_lib patrol_append_capped "$CAPPED_FILE" "line$i" "5"
done
count=$(wc -l < "$CAPPED_FILE" | tr -d ' ')
assert_eq "caps file at max lines" "5" "$count"
first=$(head -1 "$CAPPED_FILE")
assert_eq "keeps most recent lines after cap" "line3" "$first"
last=$(tail -1 "$CAPPED_FILE")
assert_eq "last line is newest after cap" "line7" "$last"

# Default cap (500) doesn't truncate small files
rm -f "$CAPPED_FILE"
for i in $(seq 1 10); do
  run_lib patrol_append_capped "$CAPPED_FILE" "line$i"
done
count=$(wc -l < "$CAPPED_FILE" | tr -d ' ')
assert_eq "default cap doesn't truncate small files" "10" "$count"


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


# ══════════════════════════════════════════════════════════════
# 2. session-start.sh integration tests
# ══════════════════════════════════════════════════════════════
printf "\n▸ session-start.sh integration tests\n\n"

SID="sess-start-$$"

reset_config
reset_state "$SID"
result=$(run_hook session-start.sh "{\"session_id\":\"$SID\",\"source\":\"startup\",\"cwd\":\"$PATROL_CWD\"}")
# Validate JSON
echo "$result" | jq . >/dev/null 2>&1
ec=$?
assert_exit_code "outputs valid JSON" "0" "$ec"
assert_match "has hookSpecificOutput" "hookSpecificOutput" "$result"

reset_config
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
echo "/some/file" > "$STATE_DIR/reads"
echo "/some/other" > "$STATE_DIR/edits"
echo "1234" > "$STATE_DIR/verified"
echo "2" > "$STATE_DIR/nudge-level"
run_hook session-start.sh "{\"session_id\":\"$SID\",\"source\":\"startup\",\"cwd\":\"$PATROL_CWD\"}" >/dev/null
assert_file_not_exists "resets reads on startup" "$STATE_DIR/reads"
assert_file_not_exists "resets edits on startup" "$STATE_DIR/edits"
assert_file_not_exists "resets verified on startup" "$STATE_DIR/verified"
# nudge-level gets recreated as "0"
result=$(cat "$STATE_DIR/nudge-level" 2>/dev/null | tr -d '[:space:]')
assert_eq "resets nudge-level to 0" "0" "$result"

reset_config
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
echo "on" > "$STATE_DIR/mode"
run_hook session-start.sh "{\"session_id\":\"$SID\",\"source\":\"clear\",\"cwd\":\"$PATROL_CWD\"}" >/dev/null
assert_file_exists "preserves mode file on clear source" "$STATE_DIR/mode"

reset_config
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
echo "on" > "$STATE_DIR/mode"
run_hook session-start.sh "{\"session_id\":\"$SID\",\"source\":\"compact\",\"cwd\":\"$PATROL_CWD\"}" >/dev/null
assert_file_exists "preserves mode file on compact source" "$STATE_DIR/mode"

reset_config
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
echo "on" > "$STATE_DIR/mode"
run_hook session-start.sh "{\"session_id\":\"$SID\",\"source\":\"startup\",\"cwd\":\"$PATROL_CWD\"}" >/dev/null
assert_file_not_exists "resets mode file on startup source" "$STATE_DIR/mode"

reset_config
echo '{"enabled": false}' > "$HOME/.patrol/config.json"
result=$(run_hook session-start.sh "{\"session_id\":\"$SID\",\"source\":\"startup\",\"cwd\":\"$PATROL_CWD\"}")
assert_empty "exits silently when enabled=false" "$result"

reset_config
echo '{"disabled_hooks": ["session-start"]}' > "$HOME/.patrol/config.json"
result=$(run_hook session-start.sh "{\"session_id\":\"$SID\",\"source\":\"startup\",\"cwd\":\"$PATROL_CWD\"}")
assert_empty "exits silently when hook disabled" "$result"

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

# always_on=false writes tier=off
reset_config
echo '{"always_on": false}' > "$HOME/.patrol/config.json"
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
run_hook session-start.sh "{\"session_id\":\"$SID\",\"source\":\"startup\",\"cwd\":\"$PATROL_CWD\"}" >/dev/null
tier=$(cat "$STATE_DIR/tier" 2>/dev/null)
assert_eq "always_on=false writes tier=off" "off" "$tier"

# Status line injection
reset_config
reset_state "$SID"
FAKE_HOME="$TMPDIR_ROOT/statusline-test-$$"
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

# No injection on clear/compact (only startup)
reset_config
reset_state "$SID"
FAKE_HOME2="$TMPDIR_ROOT/statusline-test2-$$"
mkdir -p "$FAKE_HOME2/.claude" "$FAKE_HOME2/.patrol"
echo '{}' > "$FAKE_HOME2/.patrol/config.json"
echo '{"statusLine":{"type":"command","command":"echo test2"}}' > "$FAKE_HOME2/.claude/settings.json"
HOME="$FAKE_HOME2" run_hook session-start.sh "{\"session_id\":\"$SID\",\"source\":\"clear\",\"cwd\":\"$PATROL_CWD\"}" >/dev/null
settings_content2=$(cat "$FAKE_HOME2/.claude/settings.json")
assert_no_match "no injection on clear source" "patrol-state" "$settings_content2"


# ══════════════════════════════════════════════════════════════
# 3. tool-tracker.sh integration tests
# ══════════════════════════════════════════════════════════════
printf "\n▸ tool-tracker.sh integration tests\n\n"

SID="tool-track-$$"

# Read: appends file path to reads
reset_config
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
result=$(run_hook tool-tracker.sh "{\"session_id\":\"$SID\",\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"/src/main.ts\"},\"cwd\":\"$PATROL_CWD\"}")
assert_empty "Read: produces no output (silent)" "$result"
content=$(cat "$STATE_DIR/reads" 2>/dev/null)
assert_match "Read: appends file path to reads" "/src/main.ts" "$content"

# Edit: appends file path to edits
reset_config
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
result=$(run_hook tool-tracker.sh "{\"session_id\":\"$SID\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/src/app.ts\"},\"cwd\":\"$PATROL_CWD\"}")
assert_empty "Edit: produces no output (silent)" "$result"
content=$(cat "$STATE_DIR/edits" 2>/dev/null)
assert_match "Edit: appends file path to edits" "/src/app.ts" "$content"

# Write: appends file path to edits
reset_config
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
result=$(run_hook tool-tracker.sh "{\"session_id\":\"$SID\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/src/new.ts\"},\"cwd\":\"$PATROL_CWD\"}")
assert_empty "Write: produces no output (silent)" "$result"
content=$(cat "$STATE_DIR/edits" 2>/dev/null)
assert_match "Write: appends file path to edits" "/src/new.ts" "$content"

# Bash with verify command: marks verified and clears edits
reset_config
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
# Set up a project with npm test as verify command
VERIFY_DIR="$TMPDIR_ROOT/verify-project"
mkdir -p "$VERIFY_DIR"
echo '{"scripts":{"test":"jest"}}' > "$VERIFY_DIR/package.json"
# Pre-populate some edits
echo "/src/a.ts" > "$STATE_DIR/edits"
echo "/src/b.ts" >> "$STATE_DIR/edits"
result=$(run_hook tool-tracker.sh "{\"session_id\":\"$SID\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"npm test\"},\"cwd\":\"$VERIFY_DIR\"}")
assert_empty "Bash verify: produces no output (silent)" "$result"
assert_file_exists "Bash verify: marks verified" "$STATE_DIR/verified"
edits_content=$(cat "$STATE_DIR/edits" 2>/dev/null)
assert_empty "Bash verify: clears edits" "$edits_content"

# Bash without verify command: no state change
reset_config
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
echo "/src/a.ts" > "$STATE_DIR/edits"
result=$(run_hook tool-tracker.sh "{\"session_id\":\"$SID\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls -la\"},\"cwd\":\"$VERIFY_DIR\"}")
assert_empty "Bash non-verify: produces no output" "$result"
assert_file_not_exists "Bash non-verify: no verified file" "$STATE_DIR/verified"
edits_content=$(cat "$STATE_DIR/edits" 2>/dev/null)
assert_not_empty "Bash non-verify: edits unchanged" "$edits_content"

# Exits on empty session_id
reset_config
result=$(run_hook tool-tracker.sh "{\"session_id\":\"\",\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"/x\"},\"cwd\":\"$PATROL_CWD\"}")
assert_empty "exits on empty session_id" "$result"

# Exits on empty tool_name
reset_config
result=$(run_hook tool-tracker.sh "{\"session_id\":\"$SID\",\"tool_name\":\"\",\"tool_input\":{},\"cwd\":\"$PATROL_CWD\"}")
assert_empty "exits on empty tool_name" "$result"

# Respects disabled_hooks config
reset_config
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
echo '{"disabled_hooks": ["tool-tracker"]}' > "$HOME/.patrol/config.json"
run_hook tool-tracker.sh "{\"session_id\":\"$SID\",\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"/disabled/test.ts\"},\"cwd\":\"$PATROL_CWD\"}" >/dev/null
if [ -f "$STATE_DIR/reads" ]; then
  content=$(cat "$STATE_DIR/reads")
else
  content=""
fi
assert_empty "respects disabled_hooks config" "$content"

# Respects enabled=false
reset_config
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
echo '{"enabled": false}' > "$HOME/.patrol/config.json"
run_hook tool-tracker.sh "{\"session_id\":\"$SID\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/disabled/edit.ts\"},\"cwd\":\"$PATROL_CWD\"}" >/dev/null
if [ -f "$STATE_DIR/edits" ]; then
  content=$(cat "$STATE_DIR/edits")
else
  content=""
fi
assert_empty "respects enabled=false" "$content"


# ══════════════════════════════════════════════════════════════
# 4. prompt-monitor.sh integration tests
# ══════════════════════════════════════════════════════════════
printf "\n▸ prompt-monitor.sh integration tests\n"

SID="prompt-mon-$$"

# ── Keyword detection ────────────────────────────────────────
printf "\n  Keyword detection:\n"

# "fix the bug" triggers bug-fix mode
reset_config
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
echo "0" > "$STATE_DIR/nudge-level"
# Need at least 1 unread edit for nudge to fire
echo "/src/a.ts" > "$STATE_DIR/edits"
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"fix the bug\"}")
assert_match "\"fix the bug\" triggers bug-fix mode" "Patrol" "$result"

# "I want to install Firefox" does NOT trigger (word boundary)
reset_config
echo '{"always_on": false}' > "$HOME/.patrol/config.json"
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
echo "0" > "$STATE_DIR/nudge-level"
echo "/src/a.ts" > "$STATE_DIR/edits"
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"I want to install Firefox\"}")
# "Firefox" should NOT match "fix" due to word boundary
assert_no_match "\"install Firefox\" does NOT trigger (word boundary)" "Patrol.*edited without" "$result"

# "prefix the thing" does NOT trigger
reset_config
echo '{"always_on": false}' > "$HOME/.patrol/config.json"
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
echo "0" > "$STATE_DIR/nudge-level"
echo "/src/a.ts" > "$STATE_DIR/edits"
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"prefix the thing\"}")
assert_no_match "\"prefix the thing\" does NOT trigger" "Patrol.*edited without" "$result"

# "error in the log" triggers
reset_config
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
echo "0" > "$STATE_DIR/nudge-level"
echo "/src/a.ts" > "$STATE_DIR/edits"
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"error in the log\"}")
assert_match "\"error in the log\" triggers" "Patrol" "$result"

# German keyword "Fehler" triggers
reset_config
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
echo "0" > "$STATE_DIR/nudge-level"
echo "/src/a.ts" > "$STATE_DIR/edits"
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"Da ist ein Fehler\"}")
assert_match "German keyword \"Fehler\" triggers" "Patrol" "$result"

# German phrase "funktioniert nicht" triggers
reset_config
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
echo "0" > "$STATE_DIR/nudge-level"
echo "/src/a.ts" > "$STATE_DIR/edits"
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"Das funktioniert nicht mehr\"}")
assert_match "German phrase \"funktioniert nicht\" triggers" "Patrol" "$result"

# French keyword "erreur" triggers
reset_config
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
echo "0" > "$STATE_DIR/nudge-level"
echo "/src/a.ts" > "$STATE_DIR/edits"
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"Il y a une erreur\"}")
assert_match "French keyword \"erreur\" triggers" "Patrol" "$result"

# Custom keywords from config
reset_config
echo '{"custom_keywords": ["regression"]}' > "$HOME/.patrol/config.json"
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
echo "0" > "$STATE_DIR/nudge-level"
echo "/src/a.ts" > "$STATE_DIR/edits"
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"there is a regression\"}")
assert_match "custom keywords from config work" "Patrol" "$result"

# ── Investigation gate ───────────────────────────────────────
printf "\n  Investigation gate:\n"

# No output when no edits (clean session)
reset_config
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
echo "0" > "$STATE_DIR/nudge-level"
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"fix the bug\"}")
assert_empty "no output when no edits (clean session)" "$result"

# Level 1 nudge when 1 file edited without reading
reset_config
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
echo "0" > "$STATE_DIR/nudge-level"
echo "/src/unread.ts" > "$STATE_DIR/edits"
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"fix the bug\"}")
assert_match "level 1 nudge when 1 file edited without reading" "edited without being read" "$result"

# Level 2 warning when 3+ edits without investigation
reset_config
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
echo "0" > "$STATE_DIR/nudge-level"
printf "/src/a.ts\n/src/b.ts\n/src/c.ts\n" > "$STATE_DIR/edits"
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"fix the bug\"}")
assert_match "level 2 warning when 3+ edits without investigation" "band-aiding" "$result"

# Level 3 STOP when 4+ patches
reset_config
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
echo "0" > "$STATE_DIR/nudge-level"
printf "/src/a.ts\n/src/b.ts\n/src/c.ts\n/src/d.ts\n" > "$STATE_DIR/edits"
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"fix the bug\"}")
assert_match "level 3 STOP when 4+ patches" "STOP" "$result"

# No warning when files were read before editing
reset_config
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
echo "0" > "$STATE_DIR/nudge-level"
printf "/src/a.ts\n/src/b.ts\n" > "$STATE_DIR/edits"
printf "/src/a.ts\n/src/b.ts\n" > "$STATE_DIR/reads"
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"fix the bug\"}")
assert_empty "no warning when files were read before editing" "$result"

# Escalation only increases (doesn't repeat same level)
reset_config
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
echo "1" > "$STATE_DIR/nudge-level"
echo "/src/a.ts" > "$STATE_DIR/edits"
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"fix the bug\"}")
# NEW_LEVEL=1 but NUDGE_LEVEL=1 already, so no output (only escalates)
assert_empty "escalation only increases (doesn't repeat same level)" "$result"

# ── Verify check ─────────────────────────────────────────────
printf "\n  Verify check:\n"

# No output when edits < 3
reset_config
echo '{"auto_detect_bugfix": false, "always_on": false}' > "$HOME/.patrol/config.json"
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
echo "0" > "$STATE_DIR/nudge-level"
printf "/src/a.ts\n/src/b.ts\n" > "$STATE_DIR/edits"
printf "/src/a.ts\n/src/b.ts\n" > "$STATE_DIR/reads"
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"add a new feature\"}")
assert_empty "no output when edits < 3" "$result"

# Reminder when 3+ edits without build/test
reset_config
echo '{"auto_detect_bugfix": false}' > "$HOME/.patrol/config.json"
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
echo "0" > "$STATE_DIR/nudge-level"
printf "/src/a.ts\n/src/b.ts\n/src/c.ts\n" > "$STATE_DIR/edits"
# Also add reads so investigation gate doesn't fire
printf "/src/a.ts\n/src/b.ts\n/src/c.ts\n" > "$STATE_DIR/reads"
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"add a new feature\"}")
assert_match "reminder when 3+ edits without build/test" "no build/test" "$result"

# No reminder after verify command detected
reset_config
echo '{"auto_detect_bugfix": false}' > "$HOME/.patrol/config.json"
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
echo "0" > "$STATE_DIR/nudge-level"
printf "/src/a.ts\n/src/b.ts\n/src/c.ts\n" > "$STATE_DIR/edits"
printf "/src/a.ts\n/src/b.ts\n/src/c.ts\n" > "$STATE_DIR/reads"
date +%s > "$STATE_DIR/verified"
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"add a new feature\"}")
assert_empty "no reminder after verify command detected" "$result"

# Verify check skipped when patrol-off
reset_config
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
echo "0" > "$STATE_DIR/nudge-level"
echo "off" > "$STATE_DIR/mode"
printf "/src/a.ts\n/src/b.ts\n/src/c.ts\n/src/d.ts\n" > "$STATE_DIR/edits"
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"add a feature\"}")
assert_empty "verify check skipped when patrol-off" "$result"

# ── Mode handling ────────────────────────────────────────────
printf "\n  Mode handling:\n"

# Manual "on" forces patrol mode
reset_config
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
echo "0" > "$STATE_DIR/nudge-level"
echo "on" > "$STATE_DIR/mode"
echo "/src/a.ts" > "$STATE_DIR/edits"
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"please add a feature\"}")
# "add a feature" has no keywords, but manual "on" forces patrol mode
assert_match "manual 'on' forces patrol mode" "edited without being read" "$result"

# Manual "off" disables all checks
reset_config
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
echo "0" > "$STATE_DIR/nudge-level"
echo "off" > "$STATE_DIR/mode"
printf "/src/a.ts\n/src/b.ts\n/src/c.ts\n/src/d.ts\n" > "$STATE_DIR/edits"
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"fix the broken bug\"}")
assert_empty "manual 'off' disables all checks" "$result"

# Auto-detect activates on keywords
reset_config
reset_state "$SID"
STATE_DIR="/tmp/patrol-${SID}"
echo "0" > "$STATE_DIR/nudge-level"
# No manual mode file
echo "/src/a.ts" > "$STATE_DIR/edits"
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"this is broken\"}")
assert_match "auto-detect activates on keywords" "Patrol" "$result"


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


# ══════════════════════════════════════════════════════════════
# 5. Cross-hook integration tests
# ══════════════════════════════════════════════════════════════
printf "\n▸ Cross-hook integration tests\n\n"

SID="cross-$$"

# Full flow: session-start -> Edit (tracked) -> prompt with "fix" -> warning fires
reset_config
reset_state "$SID"
run_hook session-start.sh "{\"session_id\":\"$SID\",\"source\":\"startup\",\"cwd\":\"$PATROL_CWD\"}" >/dev/null
run_hook tool-tracker.sh "{\"session_id\":\"$SID\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/src/main.ts\"},\"cwd\":\"$PATROL_CWD\"}" >/dev/null
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"fix the crash\"}")
assert_match "full flow: session-start -> Edit -> fix prompt -> warning" "edited without being read" "$result"

# Full flow: session-start -> Read -> Edit (same file) -> no warning (file was read)
reset_config
reset_state "$SID"
run_hook session-start.sh "{\"session_id\":\"$SID\",\"source\":\"startup\",\"cwd\":\"$PATROL_CWD\"}" >/dev/null
run_hook tool-tracker.sh "{\"session_id\":\"$SID\",\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"/src/main.ts\"},\"cwd\":\"$PATROL_CWD\"}" >/dev/null
run_hook tool-tracker.sh "{\"session_id\":\"$SID\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/src/main.ts\"},\"cwd\":\"$PATROL_CWD\"}" >/dev/null
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"fix the bug\"}")
assert_empty "full flow: Read -> Edit same file -> no warning" "$result"

# Full flow: Edit x3 -> Bash verify -> prompt -> no verify reminder
reset_config
reset_state "$SID"
VERIFY_DIR="$TMPDIR_ROOT/cross-verify"
mkdir -p "$VERIFY_DIR"
echo '{"scripts":{"test":"jest"}}' > "$VERIFY_DIR/package.json"
run_hook session-start.sh "{\"session_id\":\"$SID\",\"source\":\"startup\",\"cwd\":\"$VERIFY_DIR\"}" >/dev/null
# Read the files first to avoid investigation gate, then edit
for f in /src/a.ts /src/b.ts /src/c.ts; do
  run_hook tool-tracker.sh "{\"session_id\":\"$SID\",\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$f\"},\"cwd\":\"$VERIFY_DIR\"}" >/dev/null
  run_hook tool-tracker.sh "{\"session_id\":\"$SID\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$f\"},\"cwd\":\"$VERIFY_DIR\"}" >/dev/null
done
# Now run verify command
run_hook tool-tracker.sh "{\"session_id\":\"$SID\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"npm test\"},\"cwd\":\"$VERIFY_DIR\"}" >/dev/null
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$SID\",\"cwd\":\"$VERIFY_DIR\",\"user_message\":\"looks good\"}")
assert_empty "full flow: Edit x3 -> Bash verify -> no reminder" "$result"


# ══════════════════════════════════════════════════════════════
# 6. Rule engine tests
# ══════════════════════════════════════════════════════════════
printf "\n▸ Rule engine tests\n"

# ── Schema & validation ──────────────────────────────────────
printf "\n  Schema & validation:\n"

# Test: valid rule passes validation
VALID_RULE='{"id":"test-rule","name":"Test","category":"workflow","level":"warn","trigger":{"type":"bash_command","match":"git push"},"message":"Run tests first"}'
result=$(echo "$VALID_RULE" | run_lib patrol_validate_rule 2>&1)
ec=$?
assert_exit_code "patrol_validate_rule accepts valid rule" "0" "$ec"

# Test: rule missing required field fails
BAD_RULE='{"name":"Test","category":"workflow","level":"warn","trigger":{"type":"bash_command","match":"git push"},"message":"msg"}'
ec=0
echo "$BAD_RULE" | run_lib patrol_validate_rule 2>/dev/null || ec=$?
assert_exit_code "patrol_validate_rule rejects rule without id" "1" "$ec"

# Test: rule with invalid level fails
BAD_LEVEL='{"id":"x","name":"X","category":"workflow","level":"fatal","trigger":{"type":"bash_command","match":"x"},"message":"x"}'
ec=0
echo "$BAD_LEVEL" | run_lib patrol_validate_rule 2>/dev/null || ec=$?
assert_exit_code "patrol_validate_rule rejects invalid level" "1" "$ec"

# Test: rule with invalid category fails
BAD_CAT='{"id":"x","name":"X","category":"unknown","level":"warn","trigger":{"type":"bash_command","match":"x"},"message":"x"}'
ec=0
echo "$BAD_CAT" | run_lib patrol_validate_rule 2>/dev/null || ec=$?
assert_exit_code "patrol_validate_rule rejects invalid category" "1" "$ec"

# Test: rule with invalid trigger type fails
BAD_TRIGGER='{"id":"x","name":"X","category":"workflow","level":"warn","trigger":{"type":"magic","match":"x"},"message":"x"}'
ec=0
echo "$BAD_TRIGGER" | run_lib patrol_validate_rule 2>/dev/null || ec=$?
assert_exit_code "patrol_validate_rule rejects invalid trigger type" "1" "$ec"

# Test: rule with invalid require type fails
BAD_REQUIRE='{"id":"x","name":"X","category":"workflow","level":"warn","trigger":{"type":"bash_command","match":"x"},"require":{"type":"magic"},"message":"x"}'
ec=0
echo "$BAD_REQUIRE" | run_lib patrol_validate_rule 2>/dev/null || ec=$?
assert_exit_code "patrol_validate_rule rejects invalid require type" "1" "$ec"

# ── Loading & merging ────────────────────────────────────────
printf "\n  Loading & merging:\n"

# Test: load rules from single file
RULES_FILE="$TMPDIR_ROOT/rules-load-test.json"
cat > "$RULES_FILE" <<'REOF'
{
  "version": "3.0",
  "rules": [
    {"id":"test-rule","name":"Test","category":"workflow","level":"warn","trigger":{"type":"bash_command","match":"git push"},"message":"msg"}
  ]
}
REOF
result=$(run_lib patrol_load_rules "$RULES_FILE")
count=$(echo "$result" | jq 'length')
assert_eq "patrol_load_rules reads rules from file" "1" "$count"

# Test: load from nonexistent file returns empty array
result=$(run_lib patrol_load_rules "/nonexistent/path.json")
assert_eq "patrol_load_rules returns [] for missing file" "[]" "$result"

# Test: merge prioritizes repo over company
COMPANY='[{"id":"r1","name":"R1","category":"safety","level":"inform","trigger":{"type":"bash_command","match":"x"},"message":"company"}]'
REPO='[{"id":"r1","name":"R1","category":"safety","level":"block","trigger":{"type":"bash_command","match":"x"},"message":"repo"}]'
merged=$(run_lib patrol_merge_rules "$COMPANY" "$REPO" "[]")
level=$(echo "$merged" | jq -r '.[0].level')
assert_eq "patrol_merge_rules repo overrides company level" "block" "$level"

# Test: personal rules can add but not weaken
REPO='[{"id":"r1","name":"R1","category":"safety","level":"block","trigger":{"type":"bash_command","match":"x"},"message":"repo"}]'
PERSONAL='[{"id":"r1","name":"R1","category":"safety","level":"inform","trigger":{"type":"bash_command","match":"x"},"message":"weak"}]'
merged=$(run_lib patrol_merge_rules "[]" "$REPO" "$PERSONAL")
level=$(echo "$merged" | jq -r '.[] | select(.id=="r1") | .level')
assert_eq "patrol_merge_rules personal cannot weaken repo" "block" "$level"

# Test: personal rules can add new rules
REPO='[{"id":"r1","name":"R1","category":"safety","level":"warn","trigger":{"type":"bash_command","match":"x"},"message":"repo"}]'
PERSONAL='[{"id":"r2","name":"R2","category":"custom","level":"inform","trigger":{"type":"keyword","match":["todo"]},"message":"personal"}]'
merged=$(run_lib patrol_merge_rules "[]" "$REPO" "$PERSONAL")
count=$(echo "$merged" | jq 'length')
assert_eq "patrol_merge_rules personal can add new rules" "2" "$count"

# Test: safety rules always injected
PATROL_COMPANY_RULES="" PATROL_REPO_RULES="" PATROL_PERSONAL_RULES=""
result=$(run_lib patrol_load_all_rules)
has_safety=$(echo "$result" | jq '[.[] | select(.id | startswith("_safety-"))] | length')
assert_match "patrol_load_all_rules includes built-in safety rules" "^[1-9]" "$has_safety"

# Test: safety rules cannot be weakened by repo
REPO_WEAK='[{"id":"_safety-force-push-main","name":"Weakened","category":"safety","level":"inform","trigger":{"type":"bash_command","match":"git push"},"message":"weakened"}]'
# Create a temp rules file for repo
WEAK_FILE="$TMPDIR_ROOT/weak-rules.json"
echo "{\"version\":\"3.0\",\"rules\":$(echo "$REPO_WEAK")}" > "$WEAK_FILE"
result=$(PATROL_COMPANY_RULES="/nonexistent" PATROL_REPO_RULES="$WEAK_FILE" PATROL_PERSONAL_RULES="/nonexistent" run_lib patrol_load_all_rules)
level=$(echo "$result" | jq -r '.[] | select(.id=="_safety-force-push-main") | .level')
assert_eq "safety rules cannot be weakened by repo" "block" "$level"

# Test: enabled:false rules are filtered out
DISABLED_FILE="$TMPDIR_ROOT/rules-disabled-test.json"
cat > "$DISABLED_FILE" <<'DEOF'
{
  "version": "3.0",
  "rules": [
    {"id":"active-rule","name":"Active","category":"workflow","level":"warn","trigger":{"type":"bash_command","match":"x"},"message":"active"},
    {"id":"disabled-rule","name":"Disabled","category":"workflow","level":"warn","trigger":{"type":"bash_command","match":"y"},"message":"disabled","enabled":false}
  ]
}
DEOF
result=$(run_lib patrol_load_rules "$DISABLED_FILE")
count=$(echo "$result" | jq 'length')
assert_eq "patrol_load_rules filters out enabled:false rules" "1" "$count"
has_disabled=$(echo "$result" | jq '[.[] | select(.id=="disabled-rule")] | length')
assert_eq "patrol_load_rules excludes disabled rule" "0" "$has_disabled"


# ── Trigger evaluation ───────────────────────────────────────
printf "\n  Trigger evaluation:\n"

# Test: bash_command trigger matches
RULE='{"id":"t1","trigger":{"type":"bash_command","match":"git push"}}'
result=$(echo "$RULE" | run_lib patrol_check_trigger "Bash" "" "git push origin main" 2>&1)
ec=$?
assert_exit_code "patrol_check_trigger matches bash_command" "0" "$ec"

# Test: bash_command trigger doesn't match
RULE='{"id":"t1","trigger":{"type":"bash_command","match":"git push"}}'
ec=0
echo "$RULE" | run_lib patrol_check_trigger "Bash" "" "npm test" 2>/dev/null || ec=$?
assert_exit_code "patrol_check_trigger rejects non-matching bash" "1" "$ec"

# Test: bash_command trigger doesn't match non-Bash tool
RULE='{"id":"t1","trigger":{"type":"bash_command","match":"git push"}}'
ec=0
echo "$RULE" | run_lib patrol_check_trigger "Read" "" "git push" 2>/dev/null || ec=$?
assert_exit_code "patrol_check_trigger rejects bash_command for non-Bash tool" "1" "$ec"

# Test: tool_use trigger matches
RULE='{"id":"t1","trigger":{"type":"tool_use","tool":"Edit","glob":"src/routes/**"}}'
ec=0
echo "$RULE" | run_lib patrol_check_trigger "Edit" "src/routes/api.ts" "" 2>&1 || ec=$?
assert_exit_code "patrol_check_trigger matches tool_use with glob" "0" "$ec"

# Test: sequence — edit without read
SEQ_STATE="$TMPDIR_ROOT/seq-state"
mkdir -p "$SEQ_STATE"
echo "src/other.ts" > "$SEQ_STATE/reads"
run_lib patrol_check_sequence "$SEQ_STATE" "src/target.ts"
ec=$?
assert_exit_code "patrol_check_sequence detects edit-without-read" "0" "$ec"

# Test: sequence — edit after read
SEQ_STATE2="$TMPDIR_ROOT/seq-state2"
mkdir -p "$SEQ_STATE2"
echo "src/target.ts" > "$SEQ_STATE2/reads"
ec=0
run_lib patrol_check_sequence "$SEQ_STATE2" "src/target.ts" || ec=$?
assert_exit_code "patrol_check_sequence allows edit-after-read" "1" "$ec"

# Test: tool-tracker writes violations
reset_config
SID="trigger-test-$$"
reset_state "$SID"
TRIGGER_STATE="/tmp/patrol-${SID}"
# Set up cached rules with a bash_command rule (no require = always violates on match)
cat > "$TRIGGER_STATE/rules.json" <<'TEOF'
[{"id":"no-force-push","name":"No force push","category":"safety","level":"block","trigger":{"type":"bash_command","match":"git push.*--force"},"message":"No force push allowed"}]
TEOF
# Simulate: Bash git push --force
run_hook tool-tracker.sh "{\"session_id\":\"$SID\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push --force origin main\"},\"cwd\":\"$PATROL_CWD\"}"
assert_file_exists "tool-tracker writes violation on trigger match" "$TRIGGER_STATE/violations.jsonl"
violation_rule=$(jq -r '.rule_id' "$TRIGGER_STATE/violations.jsonl" 2>/dev/null | head -1)
assert_eq "violation has correct rule_id" "no-force-push" "$violation_rule"

# Test: tool-tracker tracks bash history
reset_config
SID2="bash-hist-$$"
reset_state "$SID2"
HIST_STATE="/tmp/patrol-${SID2}"
run_hook tool-tracker.sh "{\"session_id\":\"$SID2\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"npm test\"},\"cwd\":\"$PATROL_CWD\"}"
assert_file_exists "tool-tracker tracks bash_history" "$HIST_STATE/bash_history"
hist_content=$(cat "$HIST_STATE/bash_history" 2>/dev/null)
assert_match "bash_history contains the command" "npm test" "$hist_content"

# Test: file_changed trigger matches Edit on glob
RULE='{"id":"t1","trigger":{"type":"file_changed","glob":"src/routes/*"}}'
ec=0
echo "$RULE" | run_lib patrol_check_trigger "Edit" "src/routes/api.ts" "" 2>&1 || ec=$?
assert_exit_code "patrol_check_trigger matches file_changed" "0" "$ec"

# Test: file_changed rejects Read tool
RULE='{"id":"t1","trigger":{"type":"file_changed","glob":"src/routes/*"}}'
ec=0
echo "$RULE" | run_lib patrol_check_trigger "Read" "src/routes/api.ts" "" 2>/dev/null || ec=$?
assert_exit_code "patrol_check_trigger rejects file_changed for Read tool" "1" "$ec"

# Test: tool-tracker respects bash_ran require (no violation when test ran)
reset_config
SID3="require-test-$$"
reset_state "$SID3"
REQ_STATE="/tmp/patrol-${SID3}"
cat > "$REQ_STATE/rules.json" <<'RQEOF'
[{"id":"test-before-push","name":"Test first","category":"workflow","level":"warn","trigger":{"type":"bash_command","match":"git push"},"require":{"type":"bash_ran","match":"npm test|pnpm test"},"message":"Run tests first"}]
RQEOF
# First run npm test (satisfies require)
run_hook tool-tracker.sh "{\"session_id\":\"$SID3\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"npm test\"},\"cwd\":\"$PATROL_CWD\"}"
# Then run git push (trigger matches, but require satisfied)
run_hook tool-tracker.sh "{\"session_id\":\"$SID3\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push origin main\"},\"cwd\":\"$PATROL_CWD\"}"
# Should NOT have a violation for test-before-push
if [ -f "$REQ_STATE/violations.jsonl" ]; then
  has_violation=$(grep -c "test-before-push" "$REQ_STATE/violations.jsonl" 2>/dev/null || echo "0")
else
  has_violation="0"
fi
assert_eq "no violation when bash_ran require satisfied" "0" "$has_violation"

# ── Violation enforcement ────────────────────────────────────
printf "\n  Violation enforcement:\n"

# Test: inform level outputs message
ENF_SID="enforce-$$"
reset_config
reset_state "$ENF_SID"
ENF_STATE="/tmp/patrol-${ENF_SID}"
echo '{"rule_id":"r1","level":"inform","message":"FYI: use pnpm","timestamp":1}' > "$ENF_STATE/violations.jsonl"
echo "0" > "$ENF_STATE/nudge-level"
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$ENF_SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"do something\"}")
assert_match "prompt-monitor outputs inform violations" "FYI: use pnpm" "$result"

# Test: block level outputs block message
reset_config
reset_state "$ENF_SID"
ENF_STATE="/tmp/patrol-${ENF_SID}"
echo '{"rule_id":"r1","level":"block","message":"Cannot force push","timestamp":1}' > "$ENF_STATE/violations.jsonl"
echo "0" > "$ENF_STATE/nudge-level"
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$ENF_SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"push it\"}")
assert_match "prompt-monitor outputs block violations" "BLOCKED" "$result"
assert_match "prompt-monitor shows block message" "Cannot force push" "$result"

# Test: warn level outputs warning
reset_config
reset_state "$ENF_SID"
ENF_STATE="/tmp/patrol-${ENF_SID}"
echo '{"rule_id":"r1","level":"warn","message":"Run tests first","timestamp":1}' > "$ENF_STATE/violations.jsonl"
echo "0" > "$ENF_STATE/nudge-level"
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$ENF_SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"push\"}")
assert_match "prompt-monitor outputs warn violations" "WARNING" "$result"
assert_match "prompt-monitor shows warn message" "Run tests first" "$result"

# Test: violations cleared after processing
reset_config
reset_state "$ENF_SID"
ENF_STATE="/tmp/patrol-${ENF_SID}"
echo '{"rule_id":"r1","level":"inform","message":"msg","timestamp":1}' > "$ENF_STATE/violations.jsonl"
echo "0" > "$ENF_STATE/nudge-level"
run_hook prompt-monitor.sh "{\"session_id\":\"$ENF_SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"ok\"}" >/dev/null
violations_content=$(cat "$ENF_STATE/violations.jsonl" 2>/dev/null)
assert_empty "violations file cleared after enforcement" "$violations_content"

# Test: no violations = falls through to v2 checks (existing behavior preserved)
reset_config
reset_state "$ENF_SID"
ENF_STATE="/tmp/patrol-${ENF_SID}"
echo "0" > "$ENF_STATE/nudge-level"
echo "/src/a.ts" > "$ENF_STATE/edits"
# No violations.jsonl — should fall through to v2 investigation gate
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$ENF_SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"fix the bug\"}")
assert_match "v2 investigation gate still works when no violations" "edited without being read" "$result"


# ── Session start rule loading ───────────────────────────────
printf "\n  Session start rule loading:\n"

# Test: session-start caches merged rules to state dir
SS_SID="ss-rules-$$"
reset_config
reset_state "$SS_SID"
SS_STATE="/tmp/patrol-${SS_SID}"
# Create a repo rules file
mkdir -p "$PATROL_CWD/.patrol"
cat > "$PATROL_CWD/.patrol/rules.json" <<'SSEOF'
{"version":"3.0","rules":[{"id":"test-r","name":"T","category":"workflow","level":"warn","trigger":{"type":"bash_command","match":"git push"},"message":"m"}]}
SSEOF
run_hook session-start.sh "{\"session_id\":\"$SS_SID\",\"source\":\"startup\",\"cwd\":\"$PATROL_CWD\"}" >/dev/null
assert_file_exists "session-start caches rules.json" "$SS_STATE/rules.json"
count=$(jq 'length' "$SS_STATE/rules.json" 2>/dev/null || echo "0")
assert_match "cached rules include repo + safety rules" "^[1-9]" "$count"

# Test: rules.json includes safety rules even without repo rules
SS_SID2="ss-safety-$$"
reset_config
reset_state "$SS_SID2"
SS_STATE2="/tmp/patrol-${SS_SID2}"
rm -f "$PATROL_CWD/.patrol/rules.json" 2>/dev/null
run_hook session-start.sh "{\"session_id\":\"$SS_SID2\",\"source\":\"startup\",\"cwd\":\"$PATROL_CWD\"}" >/dev/null
assert_file_exists "rules.json exists even without repo rules" "$SS_STATE2/rules.json"
safety_count=$(jq '[.[] | select(.id | startswith("_safety-"))] | length' "$SS_STATE2/rules.json" 2>/dev/null || echo "0")
assert_match "safety rules cached by default" "^[1-9]" "$safety_count"

# Test: violations and bash_history cleared on session start
SS_SID3="ss-clear-$$"
reset_config
reset_state "$SS_SID3"
SS_STATE3="/tmp/patrol-${SS_SID3}"
echo '{"rule_id":"old","level":"warn","message":"stale"}' > "$SS_STATE3/violations.jsonl"
echo "old command" > "$SS_STATE3/bash_history"
run_hook session-start.sh "{\"session_id\":\"$SS_SID3\",\"source\":\"startup\",\"cwd\":\"$PATROL_CWD\"}" >/dev/null
assert_file_not_exists "violations cleared on session start" "$SS_STATE3/violations.jsonl"
assert_file_not_exists "bash_history cleared on session start" "$SS_STATE3/bash_history"

# Test: banner shows rule count
SS_SID4="ss-banner-$$"
reset_config
reset_state "$SS_SID4"
cat > "$PATROL_CWD/.patrol/rules.json" <<'SSEOF2'
{"version":"3.0","rules":[{"id":"test-r","name":"T","category":"workflow","level":"warn","trigger":{"type":"bash_command","match":"x"},"message":"m"}]}
SSEOF2
result=$(run_hook session-start.sh "{\"session_id\":\"$SS_SID4\",\"source\":\"startup\",\"cwd\":\"$PATROL_CWD\"}")
assert_match "banner shows rule count" "rules loaded" "$result"
# Clean up
rm -f "$PATROL_CWD/.patrol/rules.json" 2>/dev/null


# ── V2 migration as rule templates ───────────────────────────
printf "\n  V2 migration as rule templates:\n"

# Test: investigation rules loaded by default
MIG_SID="migrate-$$"
reset_config
reset_state "$MIG_SID"
MIG_STATE="/tmp/patrol-${MIG_SID}"
rm -f "$PATROL_CWD/.patrol/rules.json" 2>/dev/null
run_hook session-start.sh "{\"session_id\":\"$MIG_SID\",\"source\":\"startup\",\"cwd\":\"$PATROL_CWD\"}" >/dev/null
has_read_before_edit=$(jq '[.[] | select(.id=="read-before-edit")] | length' "$MIG_STATE/rules.json" 2>/dev/null || echo "0")
assert_eq "investigation rule 'read-before-edit' loaded" "1" "$has_read_before_edit"

has_investigate=$(jq '[.[] | select(.id=="investigate-first")] | length' "$MIG_STATE/rules.json" 2>/dev/null || echo "0")
assert_eq "investigation rule 'investigate-first' loaded" "1" "$has_investigate"

has_test_after=$(jq '[.[] | select(.id=="test-after-changes")] | length' "$MIG_STATE/rules.json" 2>/dev/null || echo "0")
assert_eq "investigation rule 'test-after-changes' loaded" "1" "$has_test_after"

# Test: investigation rules can be overridden by repo rules
MIG_SID2="migrate-override-$$"
reset_config
echo '{"adaptive": false}' > "$HOME/.patrol/config.json"
reset_state "$MIG_SID2"
MIG_STATE2="/tmp/patrol-${MIG_SID2}"
mkdir -p "$PATROL_CWD/.patrol"
cat > "$PATROL_CWD/.patrol/rules.json" <<'MIGEOF'
{"version":"3.0","rules":[{"id":"read-before-edit","name":"Custom read rule","category":"workflow","level":"block","trigger":{"type":"sequence","pattern":"edit-without-read"},"message":"Custom: must read first"}]}
MIGEOF
run_hook session-start.sh "{\"session_id\":\"$MIG_SID2\",\"source\":\"startup\",\"cwd\":\"$PATROL_CWD\"}" >/dev/null
level=$(jq -r '.[] | select(.id=="read-before-edit") | .level' "$MIG_STATE2/rules.json" 2>/dev/null)
assert_eq "repo can override investigation rule level" "block" "$level"
msg=$(jq -r '.[] | select(.id=="read-before-edit") | .message' "$MIG_STATE2/rules.json" 2>/dev/null)
assert_match "repo overrides investigation rule message" "Custom" "$msg"
rm -f "$PATROL_CWD/.patrol/rules.json" 2>/dev/null


# ══════════════════════════════════════════════════════════════
# 7. V3 integration — full rule flow
# ══════════════════════════════════════════════════════════════
printf "\n▸ V3 integration tests\n\n"

# Test: Full flow — session-start loads rules → bash triggers → prompt enforces
INT_SID="int-$$"
reset_config
reset_state "$INT_SID"
INT_STATE="/tmp/patrol-${INT_SID}"

# Create a repo rule: warn on git push without prior test
mkdir -p "$PATROL_CWD/.patrol"
cat > "$PATROL_CWD/.patrol/rules.json" <<'IEOF'
{"version":"3.0","rules":[
  {"id":"no-push-without-test","name":"Test before push","category":"workflow","level":"warn",
   "trigger":{"type":"bash_command","match":"git push"},
   "require":{"type":"bash_ran","match":"npm test|pnpm test"},
   "message":"Run tests before pushing."}
]}
IEOF

# Step 1: Session start — loads rules
run_hook session-start.sh "{\"session_id\":\"$INT_SID\",\"source\":\"startup\",\"cwd\":\"$PATROL_CWD\"}" >/dev/null
assert_file_exists "integration: rules cached after session-start" "$INT_STATE/rules.json"
# Verify our custom rule is in the cache
has_custom=$(jq '[.[] | select(.id=="no-push-without-test")] | length' "$INT_STATE/rules.json" 2>/dev/null)
assert_eq "integration: custom rule loaded" "1" "$has_custom"

# Step 2: Simulate git push WITHOUT prior test
run_hook tool-tracker.sh "{\"session_id\":\"$INT_SID\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push origin main\"},\"cwd\":\"$PATROL_CWD\"}"
assert_file_exists "integration: violation recorded" "$INT_STATE/violations.jsonl"
v_count=$(wc -l < "$INT_STATE/violations.jsonl" 2>/dev/null | tr -d ' ')
assert_eq "integration: exactly 1 violation" "1" "$v_count"

# Step 3: Prompt monitor enforces the violation
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$INT_SID\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"done\"}")
assert_match "integration: warning message shown" "Run tests before pushing" "$result"

# Step 4: Violations cleared after enforcement
v_after=$(cat "$INT_STATE/violations.jsonl" 2>/dev/null)
assert_empty "integration: violations cleared after enforcement" "$v_after"

# Test: Full flow — safety rule blocks force-push
INT_SID2="int-safety-$$"
reset_config
reset_state "$INT_SID2"
INT_STATE2="/tmp/patrol-${INT_SID2}"
rm -f "$PATROL_CWD/.patrol/rules.json" 2>/dev/null

# Step 1: Session start (only safety + investigation rules)
run_hook session-start.sh "{\"session_id\":\"$INT_SID2\",\"source\":\"startup\",\"cwd\":\"$PATROL_CWD\"}" >/dev/null

# Step 2: Simulate git push --force origin main
run_hook tool-tracker.sh "{\"session_id\":\"$INT_SID2\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push --force origin main\"},\"cwd\":\"$PATROL_CWD\"}"
assert_file_exists "integration: safety violation recorded" "$INT_STATE2/violations.jsonl"

# Step 3: Prompt monitor shows block
result=$(run_hook prompt-monitor.sh "{\"session_id\":\"$INT_SID2\",\"cwd\":\"$PATROL_CWD\",\"user_message\":\"push it\"}")
assert_match "integration: block message for force-push" "BLOCKED" "$result"
assert_match "integration: safety message shown" "Force-pushing to main" "$result"

# Test: No violation when require is satisfied
INT_SID3="int-require-$$"
reset_config
reset_state "$INT_SID3"
INT_STATE3="/tmp/patrol-${INT_SID3}"
mkdir -p "$PATROL_CWD/.patrol"
cat > "$PATROL_CWD/.patrol/rules.json" <<'IEOF2'
{"version":"3.0","rules":[
  {"id":"test-first","name":"Test first","category":"workflow","level":"warn",
   "trigger":{"type":"bash_command","match":"git push"},
   "require":{"type":"bash_ran","match":"npm test"},
   "message":"Run tests first"}
]}
IEOF2

# Session start
run_hook session-start.sh "{\"session_id\":\"$INT_SID3\",\"source\":\"startup\",\"cwd\":\"$PATROL_CWD\"}" >/dev/null

# Run npm test first (satisfies require)
run_hook tool-tracker.sh "{\"session_id\":\"$INT_SID3\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"npm test\"},\"cwd\":\"$PATROL_CWD\"}"

# Then git push (trigger matches but require satisfied)
run_hook tool-tracker.sh "{\"session_id\":\"$INT_SID3\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push origin main\"},\"cwd\":\"$PATROL_CWD\"}"

# Should NOT have violations
if [ -f "$INT_STATE3/violations.jsonl" ] && [ -s "$INT_STATE3/violations.jsonl" ]; then
  has_v=$(grep -c "test-first" "$INT_STATE3/violations.jsonl" 2>/dev/null || echo "0")
else
  has_v="0"
fi
assert_eq "integration: no violation when require satisfied" "0" "$has_v"

# Clean up
rm -f "$PATROL_CWD/.patrol/rules.json" 2>/dev/null


# ══════════════════════════════════════════════════════════════
# 8. Adaptive score engine tests
# ══════════════════════════════════════════════════════════════
printf "\n▸ Adaptive score engine tests\n"

# ── Score calculation ─────────────────────────────────────────
printf "\n  Score calculation:\n"

# Clean up history before adaptive tests
rm -f "$HOME/.patrol/history.json"

# Unknown rule returns score 0
reset_config
result=$(run_lib patrol_adaptive_get_score "unknown-rule-xyz")
assert_eq "unknown rule returns score 0" "0" "$result"

# After 1 violation, score is ~1
reset_config
rm -f "$HOME/.patrol/history.json"
run_lib patrol_adaptive_record_violation "test-rule-1"
result=$(run_lib patrol_adaptive_get_score "test-rule-1")
# Score should be ~1.0 (with possible tiny decay for near-zero elapsed time)
score_ok=$(awk -v s="$result" 'BEGIN { print (s >= 0.99 && s <= 1.01) ? "yes" : "no" }')
assert_eq "after 1 violation score is ~1" "yes" "$score_ok"

# After 2 violations (immediate), score is ~2
reset_config
rm -f "$HOME/.patrol/history.json"
run_lib patrol_adaptive_record_violation "test-rule-2"
run_lib patrol_adaptive_record_violation "test-rule-2"
result=$(run_lib patrol_adaptive_get_score "test-rule-2")
score_ok=$(awk -v s="$result" 'BEGIN { print (s >= 1.9 && s <= 2.1) ? "yes" : "no" }')
assert_eq "after 2 violations score is ~2" "yes" "$score_ok"

# total_violations increments correctly
reset_config
rm -f "$HOME/.patrol/history.json"
run_lib patrol_adaptive_record_violation "test-rule-tv"
run_lib patrol_adaptive_record_violation "test-rule-tv"
run_lib patrol_adaptive_record_violation "test-rule-tv"
history=$(run_lib patrol_adaptive_history)
total=$(echo "$history" | jq -r '.rules["test-rule-tv"].total_violations')
assert_eq "total_violations increments to 3" "3" "$total"

# ── History read/write ────────────────────────────────────────
printf "\n  History read/write:\n"

# Missing history returns default
rm -f "$HOME/.patrol/history.json"
result=$(run_lib patrol_adaptive_history)
version=$(echo "$result" | jq -r '.version')
assert_eq "missing history returns version 1.0" "1.0" "$version"
rules_empty=$(echo "$result" | jq '.rules | length')
assert_eq "missing history has empty rules" "0" "$rules_empty"

# After save, history persists
rm -f "$HOME/.patrol/history.json"
run_lib patrol_adaptive_record_violation "persist-test"
assert_file_exists "history file written" "$HOME/.patrol/history.json"
result=$(run_lib patrol_adaptive_history)
has_rule=$(echo "$result" | jq 'has("rules") and (.rules | has("persist-test"))')
assert_eq "saved history has rule entry" "true" "$has_rule"

# ── Level adjustment ──────────────────────────────────────────
printf "\n  Level adjustment:\n"

# No history → score 0 → below deescalate threshold → de-escalates
reset_config
rm -f "$HOME/.patrol/history.json"
result=$(run_lib patrol_adaptive_level "no-history-rule" "warn")
assert_eq "no history: warn de-escalates to inform" "inform" "$result"

# No history → inform stays inform (floor)
reset_config
rm -f "$HOME/.patrol/history.json"
result=$(run_lib patrol_adaptive_level "no-history-rule2" "inform")
assert_eq "de-escalation floor: inform stays inform" "inform" "$result"

# High score escalates: warn → block
reset_config
rm -f "$HOME/.patrol/history.json"
for i in 1 2 3 4 5 6 7 8; do
  run_lib patrol_adaptive_record_violation "high-score-rule"
done
result=$(run_lib patrol_adaptive_level "high-score-rule" "warn")
assert_eq "high score escalates warn to block" "block" "$result"

# High score escalates: inform → warn
reset_config
rm -f "$HOME/.patrol/history.json"
for i in 1 2 3 4 5 6 7 8; do
  run_lib patrol_adaptive_record_violation "high-score-inform"
done
result=$(run_lib patrol_adaptive_level "high-score-inform" "inform")
assert_eq "high score escalates inform to warn" "warn" "$result"

# Escalation cap: block stays block
reset_config
rm -f "$HOME/.patrol/history.json"
for i in 1 2 3 4 5 6 7 8; do
  run_lib patrol_adaptive_record_violation "cap-rule"
done
result=$(run_lib patrol_adaptive_level "cap-rule" "block")
assert_eq "escalation cap: block stays block" "block" "$result"

# De-escalation: zero score block → warn
reset_config
rm -f "$HOME/.patrol/history.json"
result=$(run_lib patrol_adaptive_level "zero-block" "block")
assert_eq "zero score de-escalates block to warn" "warn" "$result"

# ── Per-rule adaptive bounds ──────────────────────────────────
printf "\n  Per-rule adaptive bounds:\n"

# adaptive.max=warn caps escalation at warn (high score, inform → warn, not block)
reset_config
rm -f "$HOME/.patrol/history.json"
for i in 1 2 3 4 5 6 7 8; do
  run_lib patrol_adaptive_record_violation "bounded-rule-max"
done
result=$(run_lib patrol_adaptive_level_with_bounds "bounded-rule-max" "inform" "" "warn")
assert_eq "max=warn caps escalation at warn" "warn" "$result"

# adaptive.min=warn prevents de-escalation below warn
reset_config
rm -f "$HOME/.patrol/history.json"
result=$(run_lib patrol_adaptive_level_with_bounds "bounded-rule-min" "warn" "warn" "")
assert_eq "min=warn prevents de-escalation below warn" "warn" "$result"

# Empty bounds use ±1 default — high score inform → warn (default max=warn)
reset_config
rm -f "$HOME/.patrol/history.json"
for i in 1 2 3 4 5 6 7 8; do
  run_lib patrol_adaptive_record_violation "default-bounds"
done
result=$(run_lib patrol_adaptive_level_with_bounds "default-bounds" "inform" "" "")
assert_eq "empty bounds: inform escalates to warn (default max)" "warn" "$result"

# Empty bounds: zero score warn → inform (default min=inform)
reset_config
rm -f "$HOME/.patrol/history.json"
result=$(run_lib patrol_adaptive_level_with_bounds "default-deesc" "warn" "" "")
assert_eq "empty bounds: warn de-escalates to inform (default min)" "inform" "$result"

# Explicit min+max: min=inform, max=warn — high score inform → warn (not block)
reset_config
rm -f "$HOME/.patrol/history.json"
for i in 1 2 3 4 5 6 7 8; do
  run_lib patrol_adaptive_record_violation "both-bounds"
done
result=$(run_lib patrol_adaptive_level_with_bounds "both-bounds" "inform" "inform" "warn")
assert_eq "explicit min+max: inform escalates to warn, capped" "warn" "$result"

# Clean up after adaptive tests
rm -f "$HOME/.patrol/history.json"


# ══════════════════════════════════════════════════════════════
# 9. Adaptive integration tests (session-start)
# ══════════════════════════════════════════════════════════════
printf "\n▸ Adaptive integration tests (session-start)\n\n"

# ── Session start applies adaptive level (escalation) ─────────
# Create a repo rule with level=warn, record 8 violations, verify cached rules have level=block
AD_SID="ad-esc-$$"
reset_config
reset_state "$AD_SID"
rm -f "$HOME/.patrol/history.json"
rm -f "$HOME/.patrol/.adaptive-introduced"
AD_STATE="/tmp/patrol-${AD_SID}"

cat > "$PATROL_CWD/.patrol/rules.json" <<'ADEOF1'
{"version":"3.0","rules":[{"id":"test-adaptive-esc","name":"Adaptive esc test","category":"workflow","level":"warn","trigger":{"type":"bash_command","match":"git push"},"message":"no push"}]}
ADEOF1

for i in 1 2 3 4 5 6 7 8; do
  run_lib patrol_adaptive_record_violation "test-adaptive-esc"
done

run_hook session-start.sh "{\"session_id\":\"$AD_SID\",\"source\":\"startup\",\"cwd\":\"$PATROL_CWD\"}" >/dev/null
cached_level=$(jq -r '.[] | select(.id=="test-adaptive-esc") | .level' "$AD_STATE/rules.json" 2>/dev/null)
assert_eq "session start escalates warn to block with high score" "block" "$cached_level"

# ── Session start de-escalates ───────────────────────────────
# No violations in history, rule with level=warn → should de-escalate to inform
AD_SID2="ad-deesc-$$"
reset_config
reset_state "$AD_SID2"
rm -f "$HOME/.patrol/history.json"
rm -f "$HOME/.patrol/.adaptive-introduced"
AD_STATE2="/tmp/patrol-${AD_SID2}"

cat > "$PATROL_CWD/.patrol/rules.json" <<'ADEOF2'
{"version":"3.0","rules":[{"id":"test-adaptive-deesc","name":"Adaptive deesc test","category":"workflow","level":"warn","trigger":{"type":"bash_command","match":"git push"},"message":"no push"}]}
ADEOF2

run_hook session-start.sh "{\"session_id\":\"$AD_SID2\",\"source\":\"startup\",\"cwd\":\"$PATROL_CWD\"}" >/dev/null
cached_level2=$(jq -r '.[] | select(.id=="test-adaptive-deesc") | .level' "$AD_STATE2/rules.json" 2>/dev/null)
assert_eq "session start de-escalates warn to inform with no violations" "inform" "$cached_level2"

# ── Safety rules exempt ──────────────────────────────────────
# Record violations for a _safety- rule, verify cached level stays block
AD_SID3="ad-safety-$$"
reset_config
reset_state "$AD_SID3"
rm -f "$HOME/.patrol/history.json"
rm -f "$HOME/.patrol/.adaptive-introduced"
AD_STATE3="/tmp/patrol-${AD_SID3}"

# Record violations for a safety rule (shouldn't matter, level should stay unchanged)
for i in 1 2 3 4 5 6 7 8; do
  run_lib patrol_adaptive_record_violation "_safety-force-push-main"
done

run_hook session-start.sh "{\"session_id\":\"$AD_SID3\",\"source\":\"startup\",\"cwd\":\"$PATROL_CWD\"}" >/dev/null
safety_level=$(jq -r '.[] | select(.id=="_safety-force-push-main") | .level' "$AD_STATE3/rules.json" 2>/dev/null)
assert_eq "safety rule level stays block despite violations" "block" "$safety_level"

# ── Banner mentions adaptive ─────────────────────────────────
AD_SID4="ad-banner-$$"
reset_config
reset_state "$AD_SID4"
rm -f "$HOME/.patrol/history.json"
rm -f "$HOME/.patrol/.adaptive-introduced"

cat > "$PATROL_CWD/.patrol/rules.json" <<'ADEOF4'
{"version":"3.0","rules":[{"id":"test-ad-banner","name":"Banner test","category":"workflow","level":"warn","trigger":{"type":"bash_command","match":"x"},"message":"m"}]}
ADEOF4

result=$(run_hook session-start.sh "{\"session_id\":\"$AD_SID4\",\"source\":\"startup\",\"cwd\":\"$PATROL_CWD\"}")
assert_match "banner mentions adaptive" "adaptive" "$result"

# ── Adaptive disabled ────────────────────────────────────────
# Set config adaptive=false, verify levels are NOT adjusted
AD_SID5="ad-disabled-$$"
reset_config
reset_state "$AD_SID5"
rm -f "$HOME/.patrol/history.json"
rm -f "$HOME/.patrol/.adaptive-introduced"
AD_STATE5="/tmp/patrol-${AD_SID5}"

echo '{"adaptive": false}' > "$HOME/.patrol/config.json"

cat > "$PATROL_CWD/.patrol/rules.json" <<'ADEOF5'
{"version":"3.0","rules":[{"id":"test-adaptive-off","name":"Adaptive off test","category":"workflow","level":"warn","trigger":{"type":"bash_command","match":"git push"},"message":"no push"}]}
ADEOF5

# Record violations — should NOT affect level because adaptive is disabled
for i in 1 2 3 4 5 6 7 8; do
  run_lib patrol_adaptive_record_violation "test-adaptive-off"
done

run_hook session-start.sh "{\"session_id\":\"$AD_SID5\",\"source\":\"startup\",\"cwd\":\"$PATROL_CWD\"}" >/dev/null
cached_level5=$(jq -r '.[] | select(.id=="test-adaptive-off") | .level' "$AD_STATE5/rules.json" 2>/dev/null)
assert_eq "adaptive disabled: level stays warn despite violations" "warn" "$cached_level5"

# Verify banner does NOT mention adaptive when disabled
result5=$(run_hook session-start.sh "{\"session_id\":\"$AD_SID5\",\"source\":\"startup\",\"cwd\":\"$PATROL_CWD\"}")
assert_no_match "adaptive disabled: banner does not mention adaptive" "adaptive" "$result5"

# Clean up
rm -f "$PATROL_CWD/.patrol/rules.json" 2>/dev/null
rm -f "$HOME/.patrol/history.json"
rm -f "$HOME/.patrol/.adaptive-introduced"


# ══════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════
printf "\n══════════════════════════════════════════\n"
printf "  Results: %d passed, %d failed\n" "$PASS" "$FAIL"
printf "══════════════════════════════════════════\n"

if [ "$FAIL" -gt 0 ]; then
  printf "\nFailures:%b\n" "$ERRORS"
  exit 1
fi

printf "\nAll tests passed.\n"
exit 0
