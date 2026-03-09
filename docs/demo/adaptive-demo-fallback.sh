#!/usr/bin/env bash
# Adaptive rules demo — prints frames for manual recording
# Usage: bash docs/demo/adaptive-demo-fallback.sh
#
# Prints the 5 frames of the adaptive rules lifecycle, each separated
# by a label and a pause. Use a terminal screen recorder or take
# screenshots of each frame.

set -euo pipefail

CYAN='\033[0;36m'
RESET='\033[0m'

frame() {
  clear
  printf "${CYAN}── Frame %s: %s ──${RESET}\n\n" "$1" "$2"
}

# ─── Frame 1: Session start ─────────────────────────────────────────────
frame 1 "Session start"
printf "  🛡️  Patrol active · 7 rules loaded · adaptive enabled\n"
sleep 3

# ─── Frame 2: First violation ───────────────────────────────────────────
frame 2 "First violation"
printf "  🛡️  Patrol active · 7 rules loaded · adaptive enabled\n\n"
printf "  ⚠️  [read-before-edit] You edited app.ts without reading it first.\n"
sleep 3

# ─── Frame 3: Escalation after repeated violations ──────────────────────
frame 3 "Escalation (repeated violations)"
printf "  🛡️  Patrol active · 7 rules loaded · adaptive enabled\n\n"
printf "  🚫 [read-before-edit] BLOCKED — read the file first.\n"
printf "     ↑ Escalated: score 6.1 (7 violations this week)\n"
sleep 3

# ─── Frame 4: De-escalation after clean behavior ────────────────────────
frame 4 "De-escalation (clean behavior)"
printf "  🛡️  Patrol active · 7 rules loaded · adaptive enabled\n\n"
printf "  Patrol: adaptive levels changed:\n"
printf "    read-before-edit: warn → inform (score: 0.3, no violations in 14 days)\n"
sleep 3

# ─── Frame 5: Clean session ─────────────────────────────────────────────
frame 5 "Clean session"
printf "  🛡️  Patrol active · 7 rules loaded · 1 rule de-escalated\n"
sleep 2

printf "\n${CYAN}── Demo complete ──${RESET}\n"
