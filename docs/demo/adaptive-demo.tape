# Patrol v3 — Adaptive Rules Lifecycle Demo
# Record with: vhs docs/demo/adaptive-demo.tape
# Requires: https://github.com/charmbracelet/vhs

Output docs/demo/adaptive-demo.gif

Set FontSize 14
Set Width 900
Set Height 500
Set Theme "Catppuccin Mocha"
Set Padding 20

# ─── Frame 1: Session start ─────────────────────────────────────────────
Hide
Type "printf '\n  🛡️  Patrol active · 7 rules loaded · adaptive enabled\n'"
Enter
Show
Sleep 3s

Hide
Type "clear"
Enter
Show

# ─── Frame 2: First violation ───────────────────────────────────────────
Hide
Type "printf '\n  🛡️  Patrol active · 7 rules loaded · adaptive enabled\n'"
Enter
Show
Sleep 1s

Hide
Type "printf '\n  ⚠️  [read-before-edit] You edited app.ts without reading it first.\n'"
Enter
Show
Sleep 3s

Hide
Type "clear"
Enter
Show

# ─── Frame 3: Escalation after repeated violations ──────────────────────
Hide
Type "printf '\n  🛡️  Patrol active · 7 rules loaded · adaptive enabled\n'"
Enter
Show
Sleep 1s

Hide
Type "printf '\n  🚫 [read-before-edit] BLOCKED — read the file first.'"
Enter
Type "printf '\n     ↑ Escalated: score 6.1 (7 violations this week)\n'"
Enter
Show
Sleep 4s

Hide
Type "clear"
Enter
Show

# ─── Frame 4: De-escalation after clean behavior ────────────────────────
Hide
Type "printf '\n  🛡️  Patrol active · 7 rules loaded · adaptive enabled\n'"
Enter
Show
Sleep 1s

Hide
Type "printf '\n  Patrol: adaptive levels changed:'"
Enter
Type "printf '\n    read-before-edit: warn → inform (score: 0.3, no violations in 14 days)\n'"
Enter
Show
Sleep 4s

Hide
Type "clear"
Enter
Show

# ─── Frame 5: Clean session ─────────────────────────────────────────────
Hide
Type "printf '\n  🛡️  Patrol active · 7 rules loaded · 1 rule de-escalated\n'"
Enter
Show
Sleep 3s
