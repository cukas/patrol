# Changelog

All notable changes to Patrol will be documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v3.0.0 — 2026-03-09

### Added
- **Rule engine** — policy enforcement with 3-layer rule loading (safety < company < repo < personal)
- **Trigger evaluation** — `bash_command`, `tool_use`, `sequence`, `file_changed` trigger types
- **Violation enforcement** — three levels: `inform`, `warn`, `block`
- **Adaptive enforcement** — decay-weighted scoring adjusts rule levels based on violation history (±1 from anchor, safety exempt)
- **Per-rule adaptive bounds** — `adaptive: { min, max }` for tech leads to control adaptation range
- **`/patrol-rules`** — list, explain, add, and disable rules
- **Absorbed workflow skills** — `/trace-fix`, `/build-guard`, `/review-gate` now built into Patrol
- **Investigation rules as templates** — v2 behavior (`read-before-edit`, `investigate-first`, `test-after-changes`) now expressed as customizable rules
- **Safety rules** — `_safety-force-push-main`, `_safety-rm-rf-critical`, `_safety-env-commit`, `_safety-drop-database` (always active, cannot be disabled)
- **Adaptive history** — persistent violation scores in `~/.patrol/history.json`
- **Level change notifications** — one-time notification at session start when adaptive adjusts a level
- **Demo recording scripts** — VHS tape file and fallback shell script for terminal GIF
- **198 passing tests** — comprehensive coverage including adaptive end-to-end lifecycle

### Changed
- README repositioned as "ESLint for Claude Code"
- `/patrol-status` dashboard now shows adaptive scores and level adjustments
- Session-start banner shows rule count and adaptive status
- Tool-tracker records violations in persistent history for adaptive scoring

### Migration from v2.x
- No breaking changes. All v2 features preserved.
- Adaptive enforcement is **on by default** — set `"adaptive": false` to disable.
- Previous investigation gate behavior now expressed as rule templates (customizable per-repo).
- `claude-workflow-skills` users: uninstall workflow-skills, install Patrol v3. Same skills, plus rule engine.

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

## [1.1.0] - 2026-03-09

### Added
- State file size caps (max 500 lines per file) to prevent unbounded growth in long sessions
- GitHub Actions CI running tests on push and PR (ubuntu + macOS)
- Multilingual default keywords: German (Fehler, kaputt, Absturz, funktioniert nicht) and French (erreur, plantage, cassé, ne marche pas)
- Example investigation walkthrough in `/diagnose` skill
- This CHANGELOG

## [1.0.0] - 2026-03-09

### Added
- Investigation gate: auto-detects bug-fix sessions from keywords, tracks reads vs edits
- Band-aid detector: escalating warnings (nudge, warning, STOP) for consecutive patches without investigation
- Build/test reminder: auto-detects project type and reminds when 3+ files changed without verification
- Three hooks: session-start, tool-tracker (async/silent), prompt-monitor
- Five commands: /patrol-on, /patrol-off, /patrol-status, /patrol-config, /patrol-help
- /diagnose skill: structured 6-step root-cause investigation protocol
- Two-layer config: global (~/.patrol/config.json) and per-project (.patrol/config.json)
- Auto-detection for package managers (pnpm, yarn, npm) and project types (Node.js, Rust, Python, Go, Make)
- Debug logging with auto-rotation at 1MB
- Comprehensive test suite (50+ assertions)
