---
name: patrol-rules
description: List, explain, and manage active rules
---

# /patrol-rules

List all active rules with their source, level, and status.

## When invoked with no arguments

Read the cached rules from `/tmp/patrol-{session_id}/rules.json`.
Present as a table:

| # | Rule | Level | Source | Status |
|---|------|-------|--------|--------|
| 1 | test-before-push | warn | .patrol/rules.json | active |
| 2 | read-before-edit | warn | built-in | active |
| 3 | no-force-push-main | block | built-in (safety) | active |

Group by category: Safety → Workflow → Quality → Architecture → Custom

For each rule, determine source:
- IDs starting with `_safety-` → "built-in (safety)"
- IDs matching built-in investigation rules (read-before-edit, investigate-first, test-after-changes) → "built-in"
- All others → the file path they were loaded from (show as relative path)

## When invoked with `explain <rule-id>`

Show full rule details:
- ID, name, category, level
- Trigger type and match pattern
- Require conditions (if any)
- Message template
- Source file
- Tags (if any)

## When invoked with `add <template-id>`

Show available built-in rule templates that are not currently active.
If a specific template-id is given, add it to `~/.patrol/my-rules.json`.

## When invoked with `disable <rule-id>`

Disable a personal rule by setting `"enabled": false` in `~/.patrol/my-rules.json`.
Cannot disable repo or company rules — inform the user that they need to modify the source file.
Cannot disable safety rules — inform the user that safety rules are always active.
