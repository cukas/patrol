# v3.0.0 — ESLint for Claude Code

Policy engine with adaptive enforcement. Rules that learn from your behavior.

## Highlights

- **Rule Engine** — 3-layer loading (safety < company < repo < personal), 6 trigger types, 3 enforcement levels
- **Adaptive Enforcement** — decay-weighted scoring auto-adjusts rule levels based on violation history
- **Safety Rules** — force-push, rm -rf, .env commits blocked by default (cannot be disabled)
- **Absorbed Workflow Skills** — `/trace-fix`, `/build-guard`, `/review-gate` built in
- **198 passing tests** across macOS and Linux

## Adaptive Enforcement

Rules learn from your behavior:
- 8 violations in 5 days → `warn` escalates to `block`
- 0 violations for 3 weeks → `warn` de-escalates to `inform`
- Safety rules always exempt

## Install

```bash
claude plugin marketplace add cukas/patrol
claude plugin install patrol@cukas
```

## What's New (from v2.0.0)

- Rule engine with JSON-based rule definitions
- Trigger types: `bash_command`, `tool_use`, `sequence`, `file_changed`
- Violation enforcement: `inform`, `warn`, `block`
- Adaptive enforcement with decay scoring (on by default)
- Per-rule adaptive bounds (`adaptive: { min, max }`)
- `/patrol-rules` command for managing active rules
- V2 investigation gate preserved as customizable rule templates
- Contributor docs (CONTRIBUTING.md, issue & PR templates)

**Full Changelog:** https://github.com/cukas/patrol/blob/main/CHANGELOG.md
