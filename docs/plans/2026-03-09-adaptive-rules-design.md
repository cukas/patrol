# Patrol v3.1 — Adaptive Rules Design

## One-Liner

Rules that learn from your behavior. Decay-weighted scoring adjusts enforcement levels automatically — like loss signals training a model.

## Core Concept

Every rule has a **violation score** per developer. Violations increase the score, time decays it. The score determines whether the enforcement level shifts ±1 from its configured anchor point.

The developer is the "model". Violations are loss signals. Patrol optimizes enforcement levels to match actual behavior.

## Algorithm: Exponential Decay Scoring

```
On violation:
  score = score * decay^(days_since_last_update) + 1.0

On rule load (session start):
  effective_score = score * decay^(days_since_last_update)

Level adjustment:
  effective_score > escalate_threshold  → level + 1 (stricter)
  effective_score < deescalate_threshold → level - 1 (milder)
  otherwise                             → configured level (anchor)
```

### Default Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `decay` | `0.95` | Daily decay factor. Score halves in ~14 days. |
| `escalate_threshold` | `5.0` | Score above this → level +1 |
| `deescalate_threshold` | `0.5` | Score below this → level -1 |

### How It Feels

| Scenario | Score trajectory | Result |
|----------|-----------------|--------|
| 3 violations in 2 days | ~3.0 → stays at anchor | No change yet |
| 8 violations in 5 days | ~6.2 → exceeds 5.0 | Escalates: warn → block |
| 0 violations for 3 weeks | ~0.35 → below 0.5 | De-escalates: warn → inform |
| 1 violation after 2 weeks of silence | ~1.0 → between thresholds | Back to anchor |

### Why Decay, Not Fixed Windows

- No arbitrary "21 days" cutoff — behavior change is detected organically
- A single bad day doesn't flip a level (needs sustained pattern)
- Recovery is natural — stop violating, score drops on its own
- One number per rule — simple to store, explain, and debug

## Storage

### File: `~/.patrol/history.json`

```json
{
  "version": "1.0",
  "rules": {
    "read-before-edit": {
      "score": 2.85,
      "last_updated": "2026-03-07T14:30:00Z",
      "last_violation": "2026-03-07T14:30:00Z",
      "total_violations": 12,
      "level_changes": 3
    },
    "test-before-push": {
      "score": 0.12,
      "last_updated": "2026-02-15T09:00:00Z",
      "last_violation": "2026-02-15T09:00:00Z",
      "total_violations": 4,
      "level_changes": 1
    }
  }
}
```

- Global per developer (not per-repo)
- `total_violations` and `level_changes` are for stats/dashboard only
- `score` + `last_updated` are the only fields needed for the algorithm

## Level Boundaries

### Default: ±1 Stufe

| Configured Level | Can become |
|-------------------|-----------|
| `inform` | `inform` or `warn` |
| `warn` | `inform`, `warn`, or `block` |
| `block` | `warn` or `block` |

### Optional per-rule override

```json
{
  "id": "test-before-push",
  "level": "warn",
  "adaptive": {
    "min": "inform",
    "max": "block"
  }
}
```

When `adaptive` is set on a rule, it overrides the ±1 default. Tech leads can widen or narrow the range.

### Safety Rules: Always Exempt

Rules with `_safety-` prefix are never adapted. `block` stays `block`. No exceptions.

## Integration Points

### 1. Session Start (`session-start.sh`)

After loading and merging rules, apply adaptive adjustments:

```
load rules (existing v3 flow)
  → load history.json
  → for each non-safety rule:
      calculate effective_score
      adjust level if threshold crossed
      if level changed from last session:
        queue notification
  → cache adjusted rules to rules.json
```

### 2. Tool Tracker (`tool-tracker.sh`)

After writing a violation to `violations.jsonl`, also update history:

```
write violation (existing v3 flow)
  → update history.json:
      apply decay since last_updated
      add 1.0 to score
      update timestamp
      increment total_violations
```

### 3. Prompt Monitor (`prompt-monitor.sh`)

No changes needed — it already reads violations with their level from the cached rules. The adaptive level is baked in at load time.

### 4. Level Change Notification

On session start, if any rule's effective level differs from last session:

```
"Patrol: adaptive levels changed this session:
  read-before-edit: warn → inform (score: 0.3, no violations in 18 days)
  test-before-push: warn → block (score: 6.1, 7 violations this week)"
```

Shown once per session via `additionalContext` in the session-start hook output.

### 5. Status Dashboard (`/patrol-status`)

Add adaptive section:

```
Adaptive Rules:
  read-before-edit    warn → inform  ▁▂▃▅▇ score: 0.3  ↓ de-escalated
  test-before-push    warn → block   ▇▇▅▃▁ score: 6.1  ↑ escalated
  no-force-push       block          (safety, exempt)
```

Sparkline shows score trend direction. Arrow shows current adjustment.

## Configuration

### `~/.patrol/config.json` additions

```json
{
  "adaptive": true,
  "adaptive_decay": 0.95,
  "adaptive_escalate_threshold": 5.0,
  "adaptive_deescalate_threshold": 0.5
}
```

| Setting | Default | Description |
|---------|---------|-------------|
| `adaptive` | `true` | Enable adaptive level adjustment |
| `adaptive_decay` | `0.95` | Daily decay factor |
| `adaptive_escalate_threshold` | `5.0` | Score to escalate |
| `adaptive_deescalate_threshold` | `0.5` | Score to de-escalate |

### Opt-out

Default **on**. First session after install shows:

```
Patrol: adaptive rules active — enforcement levels adjust based on your behavior.
  Disable with: /patrol-config adaptive false
```

Disabling requires explicit `"adaptive": false`. No silent opt-out.

## README Concept

The README needs to sell this feature properly. Structure:

### Hero Section (top)

```
**ESLint for Claude Code — now with adaptive enforcement.**

Rules that learn. Levels that adjust. A policy engine that gets smarter over time.
```

### Section 1: "What is Adaptive?" (short, visual)

Side-by-side before/after showing static vs adaptive behavior.
2-3 sentences max, then a terminal GIF showing it in action.

### Section 2: "How It Works" (the algorithm, explained simply)

Decay scoring explained without math. Use the "model training" analogy:
- Violations = loss signals
- Score = accumulated loss with time decay
- Thresholds = when to adjust

Show the score trajectory table from above.

### Section 3: "What You Control"

Config options, per-rule overrides, safety exemptions.
Make it clear: you're always in control, Patrol just suggests better defaults.

### Section 4: "For Tech Leads"

How to set adaptive ranges per rule, how to see team-wide patterns.
The `adaptive: { min, max }` override.

### Fake GIF Plan

Create an SVG or terminal recording (asciinema/VHS) showing:

```
Frame 1: Session start
  🛡️ Patrol active · 7 rules loaded · adaptive enabled

Frame 2: Dev edits without reading (3 times over a week)
  ⚠️ [read-before-edit] You edited app.ts without reading it first.

Frame 3: Next session, same pattern continues
  🚫 [read-before-edit] BLOCKED — read the file first (escalated: 6 violations this week)

Frame 4: Dev starts reading before editing consistently (2 weeks later)
  ℹ️ Patrol: read-before-edit de-escalated to inform (no violations in 14 days)

Frame 5: Clean session
  🛡️ Patrol active · 7 rules loaded · adaptive: 1 rule de-escalated
```

Tool: Use `vhs` (Charm CLI) to script a fake terminal session, or create an SVG animation manually. The recording should be ~15 seconds, looping.

## Edge Cases

### First-time user (no history)

All scores start at 0. No de-escalation happens (already at anchor). First violation starts tracking. Natural ramp-up.

### Rule ID changes between versions

History keyed by rule ID. If a rule ID changes, the old history is orphaned (ignored). New ID starts fresh. This is correct — if the rule changed, past behavior may not be relevant.

### Multiple violations in one session

Each violation adds 1.0 to the score independently. Three violations in one session = score +3.0 (minus decay). This is intentional — a bad session should have proportional impact.

### Config changes the anchor level

If a tech lead changes a rule from `warn` to `block`, the adaptive system uses the new anchor. History score stays the same, but the ±1 range shifts. A rule that was de-escalated from `warn` to `inform` would now be de-escalated from `block` to `warn`.

### Concurrent sessions

`history.json` could be written by multiple sessions. Use atomic write (write to temp, mv) to prevent corruption. Last-write-wins is acceptable — scores are approximate by nature.
