# Adaptive Rules Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add decay-weighted adaptive enforcement levels to Patrol's rule engine — rules automatically escalate or de-escalate based on violation history.

**Architecture:** History stored in `~/.patrol/history.json` as scores per rule. On session start, scores decay by time elapsed and adjust cached rule levels ±1. On violation, tool-tracker updates the score. Notifications on level changes.

**Tech Stack:** Pure shell + jq (same as existing Patrol)

**Design Doc:** `docs/plans/2026-03-09-adaptive-rules-design.md`

---

### Task 1: Adaptive Score Functions in lib.sh

**Files:**
- Modify: `hooks/lib.sh` (append after rule engine section, ~line 510)
- Test: `tests/run-tests.sh` (append new test section)

**Step 1: Write failing tests for score calculation**

Append to `tests/run-tests.sh` before the final results output:

```bash
echo ""
echo "▸ Adaptive rules tests"
echo ""
echo "  Score calculation:"

# Reset state
rm -f "$HOME/.patrol/history.json"

# Test: patrol_adaptive_score returns 0 for unknown rule
source "$PATROL_ROOT/hooks/lib.sh"
SCORE=$(patrol_adaptive_get_score "unknown-rule")
assert_eq "unknown rule returns score 0" "0" "$SCORE"

# Test: patrol_adaptive_record adds 1.0 to score
patrol_adaptive_record_violation "test-rule"
SCORE=$(patrol_adaptive_get_score "test-rule")
# Score should be 1.0 (or close, as float)
assert_match "score after 1 violation is ~1" "^1" "$SCORE"

# Test: patrol_adaptive_record accumulates
patrol_adaptive_record_violation "test-rule"
SCORE=$(patrol_adaptive_get_score "test-rule")
# Score should be ~2.0 (1.0 * decay^0 + 1.0, decay negligible in same second)
assert_match "score after 2 violations is ~2" "^[12]" "$SCORE"

# Test: total_violations increments
TOTAL=$(jq -r '.rules["test-rule"].total_violations' "$HOME/.patrol/history.json")
assert_eq "total_violations is 2" "2" "$TOTAL"
```

**Step 2: Run tests to verify they fail**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`
Expected: FAIL — functions not defined

**Step 3: Implement adaptive score functions in lib.sh**

Append to `hooks/lib.sh` after the `patrol_check_sequence` function:

```bash
# ── Adaptive Rules ───────────────────────────────────────────────

PATROL_ADAPTIVE_DECAY=0.95
PATROL_ADAPTIVE_ESCALATE=5.0
PATROL_ADAPTIVE_DEESCALATE=0.5

# Get adaptive config values (with defaults)
patrol_adaptive_config() {
  local key="$1" default="$2"
  patrol_config "$key" "$default"
}

# Read the history file. Returns JSON object.
patrol_adaptive_history() {
  local history_file="$HOME/.patrol/history.json"
  if [ -f "$history_file" ]; then
    cat "$history_file"
  else
    echo '{"version":"1.0","rules":{}}'
  fi
}

# Write history atomically.
patrol_adaptive_save_history() {
  local history="$1"
  local history_file="$HOME/.patrol/history.json"
  mkdir -p "$HOME/.patrol" 2>/dev/null
  local tmp
  tmp=$(mktemp "${history_file}.XXXXXX")
  if echo "$history" | jq '.' > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    mv "$tmp" "$history_file"
  else
    rm -f "$tmp"
    patrol_debug "adaptive: failed to write history"
  fi
}

# Get current score for a rule (applies decay since last update).
patrol_adaptive_get_score() {
  local rule_id="$1"
  local history
  history=$(patrol_adaptive_history)
  local decay
  decay=$(patrol_adaptive_config "adaptive_decay" "$PATROL_ADAPTIVE_DECAY")

  local entry
  entry=$(echo "$history" | jq -r --arg id "$rule_id" '.rules[$id] // empty')
  [ -z "$entry" ] && echo "0" && return 0

  local score last_updated
  score=$(echo "$entry" | jq -r '.score // 0')
  last_updated=$(echo "$entry" | jq -r '.last_updated // 0')

  # Calculate days since last update
  local now days
  now=$(date +%s)
  last_epoch=$(echo "$last_updated" | jq -r 'if test("^[0-9]+$") then . else 0 end' 2>/dev/null || echo "0")
  if [ "$last_epoch" = "0" ] && [ "$last_updated" != "0" ]; then
    last_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$last_updated" +%s 2>/dev/null || date -d "$last_updated" +%s 2>/dev/null || echo "$now")
  fi
  days=$(echo "$now $last_epoch" | awk '{d=($1-$2)/86400; if(d<0) d=0; print d}')

  # Apply decay: score * decay^days
  local effective
  effective=$(echo "$score $decay $days" | awk '{printf "%.2f", $1 * ($2 ^ $3)}')
  echo "$effective"
}

# Record a violation — update score in history.
patrol_adaptive_record_violation() {
  local rule_id="$1"
  local history
  history=$(patrol_adaptive_history)
  local decay
  decay=$(patrol_adaptive_config "adaptive_decay" "$PATROL_ADAPTIVE_DECAY")

  local now_iso now_epoch
  now_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  now_epoch=$(date +%s)

  # Get existing entry or create new
  local current_score="0" last_epoch="$now_epoch" total="0" level_changes="0"
  local entry
  entry=$(echo "$history" | jq -r --arg id "$rule_id" '.rules[$id] // empty')
  if [ -n "$entry" ]; then
    current_score=$(echo "$entry" | jq -r '.score // 0')
    total=$(echo "$entry" | jq -r '.total_violations // 0')
    level_changes=$(echo "$entry" | jq -r '.level_changes // 0')
    local lu
    lu=$(echo "$entry" | jq -r '.last_updated // empty')
    if [ -n "$lu" ]; then
      last_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$lu" +%s 2>/dev/null || date -d "$lu" +%s 2>/dev/null || echo "$now_epoch")
    fi
  fi

  # Apply decay since last update, then add 1.0
  local days new_score
  days=$(echo "$now_epoch $last_epoch" | awk '{d=($1-$2)/86400; if(d<0) d=0; print d}')
  new_score=$(echo "$current_score $decay $days" | awk '{printf "%.2f", $1 * ($2 ^ $3) + 1.0}')
  total=$((total + 1))

  # Update history
  history=$(echo "$history" | jq --arg id "$rule_id" \
    --argjson score "$new_score" \
    --arg ts "$now_iso" \
    --argjson total "$total" \
    --argjson lc "$level_changes" \
    '.rules[$id] = {score: $score, last_updated: $ts, last_violation: $ts, total_violations: $total, level_changes: $lc}')

  patrol_adaptive_save_history "$history"
  patrol_debug "adaptive: recorded violation for $rule_id, score=$new_score, total=$total"
}

# Calculate the adaptive level for a rule.
# Args: rule_id, configured_level
# Returns: adjusted level (inform/warn/block)
patrol_adaptive_level() {
  local rule_id="$1" configured_level="$2"
  local score
  score=$(patrol_adaptive_get_score "$rule_id")

  local escalate_threshold deescalate_threshold
  escalate_threshold=$(patrol_adaptive_config "adaptive_escalate_threshold" "$PATROL_ADAPTIVE_ESCALATE")
  deescalate_threshold=$(patrol_adaptive_config "adaptive_deescalate_threshold" "$PATROL_ADAPTIVE_DEESCALATE")

  # Determine direction
  local direction="none"
  if echo "$score $escalate_threshold" | awk '{exit ($1 > $2) ? 0 : 1}'; then
    direction="up"
  elif echo "$score $deescalate_threshold" | awk '{exit ($1 < $2) ? 0 : 1}'; then
    direction="down"
  fi

  # Apply ±1 shift
  case "$direction" in
    up)
      case "$configured_level" in
        inform) echo "warn" ;;
        warn)   echo "block" ;;
        block)  echo "block" ;;
      esac
      ;;
    down)
      case "$configured_level" in
        inform) echo "inform" ;;
        warn)   echo "inform" ;;
        block)  echo "warn" ;;
      esac
      ;;
    *)
      echo "$configured_level"
      ;;
  esac
}
```

**Step 4: Run tests to verify they pass**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`
Expected: All PASS

**Step 5: Commit**

```bash
git add hooks/lib.sh tests/run-tests.sh
git commit -m "feat: add adaptive score functions — decay model, history read/write"
```

---

### Task 2: Adaptive Level Tests

**Files:**
- Test: `tests/run-tests.sh` (append more tests)

**Step 1: Write failing tests for level adjustment**

Append to tests after Task 1's tests:

```bash
echo ""
echo "  Level adjustment:"

# Reset history
rm -f "$HOME/.patrol/history.json"
source "$PATROL_ROOT/hooks/lib.sh"

# Test: no history → level unchanged
LEVEL=$(patrol_adaptive_level "no-history-rule" "warn")
assert_eq "no history keeps configured level" "warn" "$LEVEL"

# Test: high score → escalate
# Simulate high score by recording many violations
for i in $(seq 1 8); do
  patrol_adaptive_record_violation "hot-rule"
done
LEVEL=$(patrol_adaptive_level "hot-rule" "warn")
assert_eq "high score escalates warn to block" "block" "$LEVEL"

# Test: escalation cap — block stays block
LEVEL=$(patrol_adaptive_level "hot-rule" "block")
assert_eq "block cannot escalate further" "block" "$LEVEL"

# Test: inform escalates to warn
rm -f "$HOME/.patrol/history.json"
for i in $(seq 1 8); do
  patrol_adaptive_record_violation "mild-rule"
done
LEVEL=$(patrol_adaptive_level "mild-rule" "inform")
assert_eq "high score escalates inform to warn" "warn" "$LEVEL"

# Test: zero score → de-escalate
rm -f "$HOME/.patrol/history.json"
LEVEL=$(patrol_adaptive_level "clean-rule" "warn")
assert_eq "zero score de-escalates warn to inform" "inform" "$LEVEL"

# Test: de-escalation floor — inform stays inform
LEVEL=$(patrol_adaptive_level "clean-rule" "inform")
assert_eq "inform cannot de-escalate further" "inform" "$LEVEL"

# Test: block de-escalates to warn
LEVEL=$(patrol_adaptive_level "clean-rule" "block")
assert_eq "zero score de-escalates block to warn" "warn" "$LEVEL"

echo ""
echo "  Safety exemption:"

# Test: safety rules are never adapted
rm -f "$HOME/.patrol/history.json"
for i in $(seq 1 8); do
  patrol_adaptive_record_violation "_safety-force-push"
done
# Even with high score, safety rules should not be adapted
# (This is checked at call site, not in patrol_adaptive_level itself)
# patrol_adaptive_level itself doesn't know about safety — caller checks
LEVEL=$(patrol_adaptive_level "_safety-force-push" "block")
assert_eq "patrol_adaptive_level returns block for safety (caller must guard)" "block" "$LEVEL"
```

**Step 2: Run tests — they should pass (functions exist from Task 1)**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`
Expected: All PASS

**Step 3: Commit**

```bash
git add tests/run-tests.sh
git commit -m "test: add adaptive level adjustment and safety exemption tests"
```

---

### Task 3: Per-Rule Adaptive Override

**Files:**
- Modify: `hooks/lib.sh` — update `patrol_adaptive_level` to check rule's `adaptive.min/max`
- Test: `tests/run-tests.sh`

**Step 1: Write failing tests**

```bash
echo ""
echo "  Per-rule adaptive override:"

rm -f "$HOME/.patrol/history.json"
source "$PATROL_ROOT/hooks/lib.sh"

# Test: rule with adaptive.max=warn caps escalation
for i in $(seq 1 8); do
  patrol_adaptive_record_violation "capped-rule"
done
LEVEL=$(patrol_adaptive_level_with_bounds "capped-rule" "inform" "inform" "warn")
assert_eq "adaptive.max=warn caps escalation" "warn" "$LEVEL"

# Test: rule with adaptive.min=warn prevents de-escalation
rm -f "$HOME/.patrol/history.json"
LEVEL=$(patrol_adaptive_level_with_bounds "floor-rule" "block" "warn" "block")
assert_eq "adaptive.min=warn prevents de-escalation below warn" "warn" "$LEVEL"

# Test: default bounds (±1) when no override
rm -f "$HOME/.patrol/history.json"
LEVEL=$(patrol_adaptive_level_with_bounds "normal-rule" "warn" "" "")
assert_eq "empty bounds use ±1 default" "inform" "$LEVEL"
```

**Step 2: Implement `patrol_adaptive_level_with_bounds`**

Add to `hooks/lib.sh` after `patrol_adaptive_level`:

```bash
# Adaptive level with optional min/max bounds from rule config.
# Args: rule_id, configured_level, min_level (or ""), max_level (or "")
patrol_adaptive_level_with_bounds() {
  local rule_id="$1" configured_level="$2" min_level="$3" max_level="$4"
  local level_order='{"inform":1,"warn":2,"block":3}'

  # Get the adaptive level (±1 default)
  local adaptive_level
  adaptive_level=$(patrol_adaptive_level "$rule_id" "$configured_level")

  # Apply bounds if set
  if [ -n "$min_level" ]; then
    local min_ord adaptive_ord
    min_ord=$(echo "$level_order" | jq -r --arg l "$min_level" '.[$l] // 0')
    adaptive_ord=$(echo "$level_order" | jq -r --arg l "$adaptive_level" '.[$l] // 0')
    if [ "$adaptive_ord" -lt "$min_ord" ]; then
      adaptive_level="$min_level"
    fi
  fi

  if [ -n "$max_level" ]; then
    local max_ord adaptive_ord
    max_ord=$(echo "$level_order" | jq -r --arg l "$max_level" '.[$l] // 0')
    adaptive_ord=$(echo "$level_order" | jq -r --arg l "$adaptive_level" '.[$l] // 0')
    if [ "$adaptive_ord" -gt "$max_ord" ]; then
      adaptive_level="$max_level"
    fi
  fi

  echo "$adaptive_level"
}
```

**Step 3: Run tests**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`
Expected: All PASS

**Step 4: Commit**

```bash
git add hooks/lib.sh tests/run-tests.sh
git commit -m "feat: add per-rule adaptive bounds (min/max override)"
```

---

### Task 4: Integrate Adaptive into Session Start

**Files:**
- Modify: `hooks/session-start.sh:37-41` — apply adaptive levels after loading rules
- Test: `tests/run-tests.sh`

**Step 1: Write failing test**

```bash
echo ""
echo "▸ Adaptive integration tests"
echo ""
echo "  Session start with adaptive:"

# Reset
rm -f "$HOME/.patrol/history.json"
rm -rf /tmp/patrol-test-adaptive-*
local_sid="test-adaptive-session-$$"
local_state=$(patrol_state_dir "$local_sid")

# Create a repo rule
cat > "$PATROL_CWD/.patrol/rules.json" <<'RULES'
{
  "version": "3.0",
  "rules": [{
    "id": "test-rule-adapt",
    "name": "Test adaptive",
    "category": "workflow",
    "level": "warn",
    "trigger": {"type": "bash_command", "match": "echo hello"},
    "message": "test"
  }]
}
RULES

# Record enough violations to escalate
source "$PATROL_ROOT/hooks/lib.sh"
for i in $(seq 1 8); do
  patrol_adaptive_record_violation "test-rule-adapt"
done

# Run session-start
OUTPUT=$(echo '{"session_id":"'"$local_sid"'","source":"startup","cwd":"'"$PATROL_CWD"'"}' | bash "$PATROL_ROOT/hooks/session-start.sh" 2>/dev/null)

# Check that the cached rules have the adapted level
CACHED_LEVEL=$(jq -r '.[] | select(.id=="test-rule-adapt") | .level' "$local_state/rules.json" 2>/dev/null)
assert_eq "session-start applies adaptive level" "block" "$CACHED_LEVEL"

# Check notification mentions the change
assert_match "banner mentions adaptive" "adaptive" "$OUTPUT"
```

**Step 2: Implement adaptive integration in session-start.sh**

Modify `hooks/session-start.sh` after the rules are loaded and cached (after line 41). Replace lines 37-41:

```bash
  # V3: Load and cache merged rules
  RULES=$(patrol_load_all_rules 2>/dev/null) || RULES="[]"

  # Apply adaptive levels (if enabled)
  ADAPTIVE_ENABLED=$(patrol_config "adaptive" "true")
  ADAPTIVE_CHANGES=""
  if [ "$ADAPTIVE_ENABLED" = "true" ]; then
    ADAPTED_RULES="[]"
    while IFS= read -r rule; do
      rule_id=$(echo "$rule" | jq -r '.id')
      configured_level=$(echo "$rule" | jq -r '.level')

      # Safety rules are exempt
      case "$rule_id" in _safety-*)
        ADAPTED_RULES=$(echo "$ADAPTED_RULES" | jq --argjson r "$rule" '. + [$r]')
        continue
        ;;
      esac

      # Check for per-rule adaptive bounds
      adaptive_min=$(echo "$rule" | jq -r '.adaptive.min // empty')
      adaptive_max=$(echo "$rule" | jq -r '.adaptive.max // empty')

      local new_level
      new_level=$(patrol_adaptive_level_with_bounds "$rule_id" "$configured_level" "$adaptive_min" "$adaptive_max")

      if [ "$new_level" != "$configured_level" ]; then
        rule=$(echo "$rule" | jq --arg l "$new_level" '.level = $l')
        ADAPTIVE_CHANGES="${ADAPTIVE_CHANGES}  ${rule_id}: ${configured_level} → ${new_level}\n"
        patrol_debug "adaptive: $rule_id $configured_level → $new_level"
      fi

      ADAPTED_RULES=$(echo "$ADAPTED_RULES" | jq --argjson r "$rule" '. + [$r]')
    done < <(echo "$RULES" | jq -c '.[]')
    RULES="$ADAPTED_RULES"
  fi

  echo "$RULES" > "$STATE_DIR/rules.json"
  RULE_COUNT=$(echo "$RULES" | jq 'length' 2>/dev/null || echo "0")
  patrol_debug "loaded $RULE_COUNT rules to cache"
```

Then update the banner (after line 57) to include adaptive info:

```bash
if [ "$RULE_COUNT" -gt 0 ] 2>/dev/null; then
  INTRO="🛡️ Patrol active · ${RULE_COUNT} rules loaded"
  if [ "$ADAPTIVE_ENABLED" = "true" ]; then
    INTRO="${INTRO} · adaptive enabled"
  fi
  if [ -n "$ADAPTIVE_CHANGES" ]; then
    INTRO="${INTRO}\\nPatrol: adaptive levels changed this session:\\n${ADAPTIVE_CHANGES}"
  fi
  INTRO="${INTRO} · /patrol-help for commands"
else
  INTRO="🛡️ Patrol active · /patrol-help for commands"
fi
```

**Step 3: Run tests**

Run: `bash tests/run-tests.sh 2>&1 | tail -30`
Expected: All PASS

**Step 4: Commit**

```bash
git add hooks/session-start.sh tests/run-tests.sh
git commit -m "feat: integrate adaptive levels into session-start rule loading"
```

---

### Task 5: Integrate Adaptive into Tool Tracker

**Files:**
- Modify: `hooks/tool-tracker.sh:109-113` — record violation in history after writing to violations.jsonl
- Test: `tests/run-tests.sh`

**Step 1: Write failing test**

```bash
echo ""
echo "  Tool tracker records adaptive history:"

rm -f "$HOME/.patrol/history.json"
local_sid="test-adapt-tracker-$$"
local_state=$(patrol_state_dir "$local_sid")

# Set up a rule
cat > "$PATROL_CWD/.patrol/rules.json" <<'RULES'
{
  "version": "3.0",
  "rules": [{
    "id": "track-adapt-test",
    "name": "Test tracking",
    "category": "workflow",
    "level": "warn",
    "trigger": {"type": "bash_command", "match": "rm -rf"},
    "message": "dangerous"
  }]
}
RULES

# Load rules into cache
source "$PATROL_ROOT/hooks/lib.sh"
RULES=$(patrol_load_all_rules)
echo "$RULES" > "$local_state/rules.json"

# Trigger the rule via tool-tracker
echo '{"session_id":"'"$local_sid"'","tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/foo"},"cwd":"'"$PATROL_CWD"'"}' | bash "$PATROL_ROOT/hooks/tool-tracker.sh" 2>/dev/null

# Check history was updated
SCORE=$(patrol_adaptive_get_score "track-adapt-test")
assert_match "tool-tracker records adaptive score" "^1" "$SCORE"
```

**Step 2: Add adaptive recording to tool-tracker.sh**

After line 113 in `hooks/tool-tracker.sh` (inside the `if [ "$violated" = "true" ]` block), add:

```bash
      # Record in adaptive history (if enabled)
      ADAPTIVE_ENABLED=$(patrol_config "adaptive" "true")
      if [ "$ADAPTIVE_ENABLED" = "true" ]; then
        case "$rule_id" in _safety-*) ;; *)
          patrol_adaptive_record_violation "$rule_id"
          ;;
        esac
      fi
```

**Step 3: Run tests**

Run: `bash tests/run-tests.sh 2>&1 | tail -20`
Expected: All PASS

**Step 4: Commit**

```bash
git add hooks/tool-tracker.sh tests/run-tests.sh
git commit -m "feat: tool-tracker records violations in adaptive history"
```

---

### Task 6: Update /patrol-status Dashboard

**Files:**
- Modify: `commands/patrol-status.md`

**Step 1: Add adaptive section to the dashboard command**

After the config section in `commands/patrol-status.md`, add script to read adaptive data:

```bash
# Adaptive
ADAPTIVE=$(jq -r '.adaptive // true' "$HOME/.patrol/config.json" 2>/dev/null || echo "true")
ADAPTIVE_RULES=""
if [ "$ADAPTIVE" = "true" ] && [ -f "$HOME/.patrol/history.json" ]; then
  ADAPTIVE_RULES=$(jq -r '.rules | to_entries[] | "\(.key) \(.value.score) \(.value.total_violations)"' "$HOME/.patrol/history.json" 2>/dev/null)
fi
echo "ADAPTIVE=$ADAPTIVE"
echo "ADAPTIVE_RULES=$ADAPTIVE_RULES"
```

Add to the dashboard template:

```
├─────────────────────────────────────────────────┤
│  Adaptive: {on/off}                             │
│  {rule_id}  score: {score}  total: {violations} │
╰─────────────────────────────────────────────────╯
```

Show adaptive section only when `ADAPTIVE=true` and history exists. For each rule in history, show:
- Rule ID
- Current effective score (with decay applied)
- Arrow: `↑ escalated` / `↓ de-escalated` / `→ anchor` based on current level vs configured
- Total violations all-time

**Step 2: Commit**

```bash
git add commands/patrol-status.md
git commit -m "feat: add adaptive rules section to /patrol-status dashboard"
```

---

### Task 7: Update README with Adaptive Rules

**Files:**
- Modify: `README.md`

**Step 1: Replace the roadmap section with full documentation**

Remove the "Roadmap: v4 — Adaptive Rules" section. Replace with a full section after "Rule Engine":

```markdown
## Adaptive Enforcement

Patrol learns from your behavior. Every rule tracks a **violation score** — violations increase it, time decays it. When the score crosses a threshold, the enforcement level shifts.

> Think of it like model training: violations are loss signals, the score is accumulated loss
> with time decay, and thresholds determine when to adjust.

### How It Works

```
Score = previous_score × 0.95^(days_since_last) + 1.0  (on violation)
Score = previous_score × 0.95^(days_since_last)         (on load)

Score > 5.0  → enforcement +1 level (stricter)
Score < 0.5  → enforcement -1 level (milder)
Otherwise    → stays at configured level
```

| Scenario | Score | Result |
|----------|-------|--------|
| 8 violations in 5 days | ~6.2 | warn → block |
| 0 violations for 3 weeks | ~0.35 | warn → inform |
| 1 violation after 2 weeks silence | ~1.0 | stays at anchor |

### Boundaries

- Default: **±1 level** from configured anchor
- Safety rules (`_safety-*`): **always exempt**, never adapted
- Per-rule override:

```json
{
  "id": "test-before-push",
  "level": "warn",
  "adaptive": { "min": "inform", "max": "block" }
}
```

### Notifications

When a level changes, Patrol tells you once at session start:

```
Patrol: adaptive levels changed this session:
  read-before-edit: warn → inform (no violations in 18 days)
  test-before-push: warn → block (7 violations this week)
```

Check anytime with `/patrol-status`.

### Configuration

| Setting | Default | Description |
|---------|---------|-------------|
| `adaptive` | `true` | Enable adaptive enforcement |
| `adaptive_decay` | `0.95` | Daily decay factor (score halves in ~14 days) |
| `adaptive_escalate_threshold` | `5.0` | Score above this → stricter |
| `adaptive_deescalate_threshold` | `0.5` | Score below this → milder |

Disable with `"adaptive": false` in `~/.patrol/config.json`.
```

Also update the config table in the Configuration section to include the adaptive settings.

Update the hero section version badge from `3.0.0-alpha.1` to `3.0.0`.

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add adaptive enforcement documentation to README"
```

---

### Task 8: Fake GIF — Terminal Recording Script

**Files:**
- Create: `docs/demo/adaptive-demo.tape` (VHS tape file for Charm's `vhs`)
- Create: `docs/demo/adaptive-demo-fallback.sh` (pure shell fallback if vhs not installed)

**Step 1: Create the VHS tape file**

```tape
Output docs/demo/adaptive-demo.gif

Set FontSize 14
Set Width 900
Set Height 500
Set Theme "Catppuccin Mocha"
Set TypingSpeed 50ms

# Frame 1: Session start with adaptive
Type "claude"
Enter
Sleep 1s
Type "# Session start"
Sleep 500ms

# Simulated Patrol banner
Type@0ms ""
Sleep 200ms
Hide
Type "printf '🛡️ Patrol active · 7 rules loaded · adaptive enabled · /patrol-help for commands\n'"
Enter
Show
Sleep 2s

# Frame 2: Developer edits without reading
Hide
Type "printf '⚠️ [read-before-edit] You edited app.ts without reading it first.\n'"
Enter
Show
Sleep 2s

# Frame 3: Escalation after pattern
Hide
Type "printf '🚫 [read-before-edit] BLOCKED — read the file first.\n   ↑ Escalated: score 6.1 (7 violations this week)\n'"
Enter
Show
Sleep 3s

# Frame 4: Two weeks later, clean behavior
Hide
Type "printf '🛡️ Patrol active · 7 rules loaded · adaptive enabled\n   Patrol: adaptive levels changed:\n     read-before-edit: warn → inform (score: 0.3, no violations in 14 days)\n'"
Enter
Show
Sleep 3s

# Frame 5: Clean session
Hide
Type "printf '🛡️ Patrol active · 7 rules loaded · 1 rule de-escalated\n'"
Enter
Show
Sleep 2s
```

**Step 2: Create fallback shell script for manual GIF creation**

```bash
#!/usr/bin/env bash
# Fallback: prints the demo frames for manual screenshot/recording
# Usage: bash docs/demo/adaptive-demo-fallback.sh

echo ""
echo "═══ Frame 1: Session Start ═══"
echo "🛡️ Patrol active · 7 rules loaded · adaptive enabled · /patrol-help for commands"
echo ""
sleep 1

echo "═══ Frame 2: Violation Detected ═══"
echo "⚠️ [read-before-edit] You edited app.ts without reading it first."
echo ""
sleep 1

echo "═══ Frame 3: Escalation (after repeated violations) ═══"
echo "🚫 [read-before-edit] BLOCKED — read the file first."
echo "   ↑ Escalated: score 6.1 (7 violations this week)"
echo ""
sleep 1

echo "═══ Frame 4: De-escalation (2 weeks of clean behavior) ═══"
echo "🛡️ Patrol active · 7 rules loaded · adaptive enabled"
echo "   Patrol: adaptive levels changed this session:"
echo "     read-before-edit: warn → inform (score: 0.3, no violations in 14 days)"
echo ""
sleep 1

echo "═══ Frame 5: Clean Session ═══"
echo "🛡️ Patrol active · 7 rules loaded · 1 rule de-escalated"
echo ""
```

**Step 3: Commit**

```bash
mkdir -p docs/demo
git add docs/demo/adaptive-demo.tape docs/demo/adaptive-demo-fallback.sh
git commit -m "feat: add adaptive rules demo recording script"
```

---

### Task 9: End-to-End Integration Test

**Files:**
- Test: `tests/run-tests.sh` (append full lifecycle test)

**Step 1: Write the full lifecycle test**

```bash
echo ""
echo "▸ Adaptive end-to-end tests"

echo ""
echo "  Full lifecycle:"

rm -f "$HOME/.patrol/history.json"
rm -rf /tmp/patrol-test-e2e-*

# Create repo rule
cat > "$PATROL_CWD/.patrol/rules.json" <<'RULES'
{
  "version": "3.0",
  "rules": [{
    "id": "e2e-adaptive",
    "name": "E2E test rule",
    "category": "workflow",
    "level": "warn",
    "trigger": {"type": "bash_command", "match": "deploy"},
    "message": "Run tests before deploying."
  }]
}
RULES

source "$PATROL_ROOT/hooks/lib.sh"

# Phase 1: Fresh start — no history, level stays at configured
local_sid="e2e-adapt-$$"
OUTPUT=$(echo '{"session_id":"'"$local_sid"'","source":"startup","cwd":"'"$PATROL_CWD"'"}' | bash "$PATROL_ROOT/hooks/session-start.sh" 2>/dev/null)
local_state="/tmp/patrol-$local_sid"
LEVEL=$(jq -r '.[] | select(.id=="e2e-adaptive") | .level' "$local_state/rules.json")
assert_eq "e2e: fresh start, level=inform (de-escalated, score=0)" "inform" "$LEVEL"

# Phase 2: Accumulate violations
for i in $(seq 1 8); do
  patrol_adaptive_record_violation "e2e-adaptive"
done

# Reload session
rm -rf "$local_state"
OUTPUT=$(echo '{"session_id":"'"$local_sid"'","source":"startup","cwd":"'"$PATROL_CWD"'"}' | bash "$PATROL_ROOT/hooks/session-start.sh" 2>/dev/null)
LEVEL=$(jq -r '.[] | select(.id=="e2e-adaptive") | .level' "$local_state/rules.json")
assert_eq "e2e: after 8 violations, level=block (escalated)" "block" "$LEVEL"
assert_match "e2e: banner shows adaptive change" "adaptive" "$OUTPUT"

# Phase 3: Safety rules stay exempt
cat > "$PATROL_CWD/.patrol/rules.json" <<'RULES'
{
  "version": "3.0",
  "rules": []
}
RULES
rm -f "$HOME/.patrol/history.json"
for i in $(seq 1 8); do
  patrol_adaptive_record_violation "_safety-force-push-main"
done
rm -rf "$local_state"
OUTPUT=$(echo '{"session_id":"'"$local_sid"'","source":"startup","cwd":"'"$PATROL_CWD"'"}' | bash "$PATROL_ROOT/hooks/session-start.sh" 2>/dev/null)
SAFETY_LEVEL=$(jq -r '.[] | select(.id=="_safety-force-push-main") | .level' "$local_state/rules.json")
assert_eq "e2e: safety rule stays block despite high score" "block" "$SAFETY_LEVEL"
```

**Step 2: Run full test suite**

Run: `bash tests/run-tests.sh 2>&1`
Expected: All tests pass, including new adaptive tests

**Step 3: Commit**

```bash
git add tests/run-tests.sh
git commit -m "test: add adaptive rules end-to-end lifecycle test"
```

---

### Task 10: Final — Version Bump and Push

**Files:**
- Modify: `README.md` — version badge to `3.0.0`
- Modify: `CHANGELOG.md` — add v3.0.0 entry

**Step 1: Update version badge**

In `README.md`, change:
```
version-3.0.0--alpha.1-green
```
to:
```
version-3.0.0-green
```

**Step 2: Update CHANGELOG.md**

Add v3.0.0 entry at top with all features:
- Rule engine with 3-layer loading
- Trigger evaluation and violation enforcement
- Absorbed workflow skills
- Adaptive enforcement with decay scoring
- /patrol-rules command
- 165+ tests

**Step 3: Commit and push**

```bash
git add README.md CHANGELOG.md
git commit -m "chore: bump version to 3.0.0, update changelog"
git push origin main
```
