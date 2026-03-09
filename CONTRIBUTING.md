# Contributing to Patrol

Patrol is a policy engine for Claude Code — ESLint for AI coding behavior. Contributions welcome.

## Getting Started

```bash
git clone https://github.com/cukas/patrol.git
cd patrol
bash tests/run-tests.sh   # 198 tests, should all pass
```

**Requirements:** `bash`, `jq`, macOS or Linux.

## Project Structure

```
hooks/
  lib.sh              # Core library — rule engine, adaptive scoring, config
  session-start.sh    # SessionStart hook — loads rules, applies adaptive levels
  tool-tracker.sh     # PostToolUse hook — tracks reads/edits, evaluates triggers
  prompt-monitor.sh   # UserPromptSubmit hook — enforces violations

templates/
  safety-rules.json        # Built-in safety rules (never weakened)
  investigation-rules.json # Built-in investigation rules (customizable)

commands/               # Claude Code slash commands (markdown)
skills/                 # Claude Code skills (markdown)
tests/
  run-tests.sh          # Full test suite — zero external dependencies
```

## How to Contribute

### Bug Fixes

1. Write a failing test in `tests/run-tests.sh`
2. Fix the bug
3. Verify all tests pass: `bash tests/run-tests.sh`
4. Submit a PR

### New Rules

Add rule templates to `templates/`. Follow the schema:

```json
{
  "id": "your-rule-id",
  "name": "Human-readable name",
  "category": "workflow|safety|quality|architecture|custom",
  "level": "inform|warn|block",
  "trigger": { "type": "bash_command|tool_use|sequence|file_changed", "match": "..." },
  "message": "Message shown when rule fires."
}
```

Safety rules (id starting with `_safety-`) cannot be weakened by any config layer.

### New Features

1. Open an issue first to discuss the approach
2. Write tests (TDD preferred)
3. Keep it shell — no external dependencies beyond `jq`
4. All 198+ tests must pass

## Code Style

- Pure POSIX-compatible shell where possible, bash extensions OK
- Use `jq` for all JSON operations (no `sed`/`awk` on JSON)
- Use `awk` for float math (no `bc` dependency)
- Functions prefixed with `patrol_` (public) or `_patrol_` (internal)
- Debug logging via `patrol_debug` (writes to `~/.patrol/debug.log`)
- Async hooks (tool-tracker) must NEVER produce output
- Atomic file writes: write to temp, `mv` to target

## Testing

```bash
bash tests/run-tests.sh
```

Tests run in an isolated environment (temp HOME, temp CWD). No side effects on your system.

**Test helpers available:**
- `assert_eq "label" "expected" "actual"`
- `assert_match "label" "pattern" "actual"`
- `assert_no_match "label" "pattern" "actual"`
- `assert_empty "label" "actual"`
- `assert_not_empty "label" "actual"`
- `assert_file_exists "label" "path"`
- `assert_file_not_exists "label" "path"`
- `assert_exit_code "label" "expected" "actual"`
- `run_hook <script> <json_input>` — run a hook with stdin
- `run_lib <function> [args]` — call a lib.sh function
- `reset_config` / `reset_state <sid>` — clean state between tests

Add tests to `tests/run-tests.sh` before the Summary section.

## Pull Request Guidelines

- One feature/fix per PR
- All tests pass
- No new external dependencies
- Update CHANGELOG.md for user-facing changes
- Commits follow [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:`, `test:`, `chore:`)

## Architecture Notes

### Three Hooks, Zero Token Cost

Patrol uses Claude Code's hook system:

1. **SessionStart** (sync) — loads and caches rules, resets state
2. **PostToolUse** (async, silent) — tracks tool usage, evaluates triggers, writes violations
3. **UserPromptSubmit** (sync) — reads violations, enforces levels, outputs warnings

Normal coding with zero violations = zero tokens consumed.

### Rule Merge Priority

```
Safety (built-in) → Investigation (built-in) → Company → Repo → Personal
```

Personal rules can add or strengthen, never weaken. Safety rules are re-injected after merge to prevent any layer from weakening them.

### Adaptive Scoring

```
score = previous_score * 0.95^(days_since_last) + 1.0   (on violation)
score > 5.0  → level +1
score < 0.5  → level -1
```

History stored in `~/.patrol/history.json`. Safety rules are always exempt.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
