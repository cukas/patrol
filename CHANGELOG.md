# Changelog

All notable changes to Patrol will be documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
