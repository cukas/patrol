# Changelog

All notable changes to Patrol will be documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
