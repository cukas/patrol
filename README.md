<div align="center">
  <img src="docs/patrol-hero.png" alt="Patrol" width="600">

  *"Learn your ways, I will. Have your back, I do."*

  **ESLint for Claude Code.** Rules. Workflows. Safety. One install.

  [![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
  [![Version](https://img.shields.io/badge/version-3.0.0--alpha.1-green.svg)]()
  [![Shell](https://img.shields.io/badge/pure%20shell-zero%20deps-orange.svg)]()
</div>

---

Patrol is a **policy engine for Claude Code** — think ESLint, but for AI coding behavior. It enforces coding rules, prevents dangerous actions, and guides better workflows — all through lightweight shell hooks with zero token cost during normal coding.

```
Three layers of protection:

  Safety rules (always on)        → block force-push, rm -rf /, .env commits
  Workflow rules (per-repo)       → test before push, read before edit
  Personal rules (your own)       → can add discipline, never weaken team rules

Three enforcement levels:

  inform  → Claude mentions it, keeps working
  warn    → Claude warns, shows what's wrong
  block   → Claude refuses until the requirement is met
```

## Install

```bash
claude plugin marketplace add cukas/patrol
claude plugin install patrol@cukas
```

That's it. Patrol loads built-in safety and workflow rules automatically. Zero config needed.

---

## How It Works

Patrol uses three lightweight hooks — zero token cost during normal coding:

```
┌──────────────────────────────────────────────────────────────────────┐
│                         Claude Code Session                          │
│                                                                      │
│  SessionStart ─── session-start.sh                                   │
│       │          Load rules (safety + company + repo + personal)     │
│       │          Cache merged rules → /tmp/patrol-{sid}/rules.json   │
│       │          Reset state, show banner                            │
│                                                                      │
│  PostToolUse ─── tool-tracker.sh (async, silent)                     │
│       │          Track Read/Edit/Write/Bash → state files            │
│       │          Evaluate rule triggers against each tool use        │
│       │          Write violations → violations.jsonl                 │
│       │          (zero output, zero tokens — always)                 │
│                                                                      │
│  UserPromptSubmit ─── prompt-monitor.sh                              │
│       │          Read pending violations                             │
│       │          Enforce levels: inform / warn / block               │
│       │          Fall through to investigation gate (v2 compat)      │
│       │          Check build/test verification                       │
│       │          (silent when no violations — zero tokens)           │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

**Normal coding session with zero violations = zero tokens consumed by Patrol.**

## Rule Engine

### Three Layers, One Merged Result

```
~/.patrol/company.json         ← Company-wide. Universal across all repos.
                                 "never force-push to main"

.patrol/rules.json             ← Per repo. Tech lead commits. PR-protected.
                                 "run pnpm test before push"

~/.patrol/my-rules.json        ← Personal. Your own discipline.
                                 Can add rules, never weaken team rules.
```

Priority: company < repo (full override) < personal (can add/strengthen, cannot weaken).

Safety rules (`_safety-*`) can **never** be weakened by any layer.

### Rule Format

```json
{
  "id": "test-before-push",
  "name": "Run tests before pushing",
  "category": "workflow",
  "level": "warn",
  "trigger": {
    "type": "bash_command",
    "match": "git push"
  },
  "require": {
    "type": "bash_ran",
    "match": "pnpm test|npm test|yarn test"
  },
  "message": "Tests haven't run this session. Run your test suite first."
}
```

### Trigger Types

| Type | Fires when... | Example |
|------|--------------|---------|
| `bash_command` | Claude runs a matching command | `git push`, `rm -rf` |
| `tool_use` | Claude uses a tool on matching files | `Edit` on `src/routes/**` |
| `sequence` | A pattern of tool usage occurs | Edit without prior Read |
| `keyword` | User prompt contains keywords | "fix", "bug", "broken" |
| `file_changed` | Specific files are modified | `*.env`, `schemas/*` |
| `session_event` | Session lifecycle event | start, compact, stop |

### Require Conditions

Rules can require that something happened before the trigger fires a violation:

| Type | What it checks |
|------|---------------|
| `bash_ran` | A matching command was run this session |
| `file_read` | The file was read before being edited |

### Enforcement Levels

| Level | Behavior |
|-------|----------|
| `inform` | Claude mentions it, continues working |
| `warn` | Claude warns, shows what's wrong |
| `block` | Claude refuses until requirement is met |

---

## Built-in Rules

### Safety Rules (always active, cannot be disabled)

| Rule | Level | What it blocks |
|------|-------|---------------|
| `_safety-force-push-main` | block | `git push --force` to main/master |
| `_safety-rm-rf-critical` | block | `rm -rf /` or `rm -rf ~` |
| `_safety-env-commit` | block | `git add .env` (not .env.example) |
| `_safety-drop-database` | warn | `DROP DATABASE` / `DROP TABLE` |

### Investigation Rules (v2 behavior, can be overridden)

| Rule | Level | What it catches |
|------|-------|----------------|
| `read-before-edit` | warn | Editing a file without reading it first |
| `investigate-first` | inform | Bug keywords without investigation |
| `test-after-changes` | inform | Multiple edits without running tests |

These represent Patrol v2's investigation discipline, now expressed as rules that teams can customize.

---

## Built-in Workflow Skills

Patrol ships with three workflow skills (absorbed from `claude-workflow-skills`):

| Skill | Purpose |
|-------|---------|
| `/trace-fix` | Investigation-first bug fixing — trace the root cause before editing |
| `/build-guard` | Orchestrated multi-file changes with regression checkpoints |
| `/review-gate` | Post-implementation review before declaring done |

---

## Commands

| Command | What it does |
|---------|-------------|
| `/patrol-rules` | List active rules with source and level |
| `/patrol-rules explain <id>` | Show full rule details |
| `/patrol-rules add <id>` | Add a built-in template to personal rules |
| `/patrol-rules disable <id>` | Disable a personal rule |
| `/patrol-on` / `/patrol-off` | Toggle patrol mode for this session |
| `/patrol-status` | Dashboard: mode, tracked reads/edits, config |
| `/patrol-help` | Quick reference |

---

## For Tech Leads

### Set up a repo

```bash
# Create rules for your project
mkdir -p .patrol
cat > .patrol/rules.json << 'EOF'
{
  "version": "3.0",
  "rules": [
    {
      "id": "test-before-push",
      "name": "Run tests before pushing",
      "category": "workflow",
      "level": "warn",
      "trigger": { "type": "bash_command", "match": "git push" },
      "require": { "type": "bash_ran", "match": "pnpm test|npm test" },
      "message": "Run tests before pushing."
    }
  ]
}
EOF

# Commit — every dev with Patrol gets these rules
git add .patrol/rules.json
git commit -m "chore: add patrol rules"
```

### Company-wide rules

Drop a file on each dev's machine (or add to dotfiles):

```json
// ~/.patrol/company.json
{
  "version": "3.0",
  "rules": [
    {
      "id": "no-force-push",
      "name": "No force push anywhere",
      "category": "safety",
      "level": "block",
      "trigger": { "type": "bash_command", "match": "git push.*--force" },
      "message": "Force push is not allowed. Use a PR."
    }
  ]
}
```

### What you get

- Rules enforced without you watching
- Juniors learn conventions in context, not from wiki pages
- Safety rules can never be weakened — not by devs, not by config
- Three enforcement levels let you choose the right friction per rule

---

## Configuration

### Personal settings: `~/.patrol/config.json`

```json
{
  "enabled": true,
  "always_on": true,
  "auto_detect_bugfix": true,
  "band_aid_threshold": 3,
  "verify_commands": "auto",
  "custom_keywords": [],
  "easter_eggs": false,
  "disabled_hooks": [],
  "debug": false
}
```

| Setting | Default | Description |
|---------|---------|-------------|
| `enabled` | `true` | Enable/disable Patrol globally |
| `always_on` | `true` | Light mode enforcement even without bugfix keywords |
| `auto_detect_bugfix` | `true` | Auto-detect bug-fix sessions from keywords |
| `band_aid_threshold` | `3` | Consecutive edits before escalating to warning |
| `verify_commands` | `"auto"` | Build/test commands, or `"auto"` to detect from project files |
| `custom_keywords` | `[]` | Additional trigger keywords (extend defaults) |
| `easter_eggs` | `false` | Yoda-themed messages |
| `disabled_hooks` | `[]` | Hooks to disable: `tool-tracker`, `prompt-monitor`, `session-start` |
| `debug` | `false` | Log to `~/.patrol/debug.log` |

### Rule file locations

| File | Purpose | Override behavior |
|------|---------|-------------------|
| `~/.patrol/company.json` | Company-wide rules | Base layer |
| `.patrol/rules.json` | Per-repo rules | Overrides company |
| `~/.patrol/my-rules.json` | Personal rules | Can add/strengthen, never weaken |

Environment variables for custom paths: `PATROL_COMPANY_RULES`, `PATROL_REPO_RULES`, `PATROL_PERSONAL_RULES`.

---

## V2 Compatibility

All v2 features still work:

- **Investigation gate** — keyword-triggered bug-fix mode with escalating warnings (nudge → warning → STOP)
- **Band-aid detection** — tracks consecutive edits without reads
- **Build/test reminders** — auto-detects project type and reminds after 3+ edits
- **Two-tier enforcement** — light mode (always-on nudge) + full mode (keyword/manual escalation)
- **Status line** — real-time display of reads, edits, mode, violations

V3 adds rule-based violations as "Check 0" before v2 checks. If a v3 rule fires, it takes priority. If no v3 violations, v2 behavior runs unchanged.

---

## State Files

Per-session state in `/tmp/patrol-{session_id}/`:

```
rules.json          # cached merged rules (loaded on session start)
violations.jsonl    # pending violations (written by tool-tracker)
reads               # file paths Claude has read
edits               # file paths Claude has edited
bash_history        # bash commands run this session
verified            # timestamp of last build/test run
nudge-level         # v2 escalation level (0-3)
mode                # manual mode override ("on" or "off")
tier                # enforcement tier ("light", "full", or "off")
```

State is reset on session start. Manual mode is preserved across `/clear` and `/compact`.

## Auto-Detection

Patrol auto-detects your project's verification commands:

| File | Commands detected |
|------|-------------------|
| `package.json` + `pnpm-lock.yaml` | `pnpm test`, `pnpm run build` |
| `package.json` + `yarn.lock` | `yarn test`, `yarn run build` |
| `package.json` | `npm test`, `npm run build` |
| `Cargo.toml` | `cargo test`, `cargo build` |
| `pyproject.toml` / `setup.py` | `pytest` |
| `go.mod` | `go test ./...` |
| `Makefile` (with `test:`) | `make test` |

---

## Works With Remembrall

If [Remembrall](https://github.com/cukas/remembrall) is installed, they complement each other — Remembrall manages context lifecycle, Patrol enforces development discipline. Both display in the status line. No conflicts.

**Without Remembrall, Patrol works 100%.**

## Requirements

- Claude Code CLI with plugin support
- `jq` (JSON processor — hooks exit gracefully if missing)

| Platform | Status |
|----------|--------|
| macOS | Fully supported |
| Linux | Fully supported |
| WSL | Fully supported |
| Windows (native) | Not supported — use WSL |

## Privacy

- **Fully local.** All data in `~/.patrol/` and `/tmp/`.
- **No network requests.** No analytics. No telemetry.
- **No external dependencies.** Pure shell + jq.

## FAQ

<details>
<summary><strong>Does Patrol slow down Claude?</strong></summary>

No. The tool tracker runs async (no output, no tokens). The prompt monitor only fires when there's a pending violation. Normal coding = zero overhead.

</details>

<details>
<summary><strong>Can I disable team rules?</strong></summary>

No. Team rules (`.patrol/rules.json`) and company rules (`~/.patrol/company.json`) are always active. You can add personal rules on top, but never weaken what the team set. Safety rules can never be weakened by any layer.

</details>

<details>
<summary><strong>What if a rule is wrong for my situation?</strong></summary>

Rules with `warn` level let Claude proceed after showing the warning. Only `block` rules are absolute, and those are reserved for safety (force-push, credentials, etc.). Talk to your tech lead about adjusting rule levels.

</details>

<details>
<summary><strong>How is this different from git hooks?</strong></summary>

Git hooks check at commit time. Patrol checks during development — before you even get to a commit. It catches problems while you're still working, when fixing them is cheap.

</details>

<details>
<summary><strong>I used claude-workflow-skills. What now?</strong></summary>

Workflow skills (`/trace-fix`, `/build-guard`, `/review-gate`) are now built into Patrol v3.0. Uninstall workflow-skills and install Patrol instead. Same skills, plus the rule engine.

</details>

<details>
<summary><strong>Does Patrol work alongside Remembrall?</strong></summary>

Yes. They complement each other — Remembrall manages context lifecycle, Patrol enforces development discipline. Both use separate state directories and hooks with no conflicts.

</details>

## Roadmap: v4 — Adaptive Rules

Rules that learn from your behavior. If you haven't triggered `read-before-edit` in three weeks, Patrol drops it from `warn` to `inform`. If a team keeps hitting `test-before-push`, it escalates to `block`. Enforcement levels that adapt based on violation history — automatic, per-developer, per-rule.

Coming after v3.0 stabilizes.

## License

MIT — cukas
