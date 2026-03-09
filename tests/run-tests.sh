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
