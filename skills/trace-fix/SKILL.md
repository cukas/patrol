---
name: trace-fix
description: Use when fixing a bug, unexpected behavior, or test failure. Investigation-first TDD loop that traces root cause before touching code.
---

# Trace-Fix

Trace the root cause, then fix it with tests. Fully autonomous.

## Phase 1 — TRACE (do not edit any code yet)

1. **Read every file involved** — use Read, Grep, Glob to trace the full call chain from entry point to where it breaks
2. **Document the root cause** — state what is wrong, where, and why. Not symptoms — the actual cause
3. **If uncertain** — say so explicitly. Do not guess. List hypotheses ranked by likelihood

Never edit a file you haven't read. Never propose a fix before tracing.

## Phase 2 — FIX (test-driven)

4. **Write a failing test** that reproduces the exact bug. Place it adjacent to the module under test using the project's existing test framework
5. **Run the test** — confirm it fails for the right reason
6. **Implement the minimal fix** — smallest change that makes the test pass
7. **Run the full test suite + type checker**
8. **If any test fails** — analyze the failure, adjust the fix, go back to step 7
9. **If 5 iterations pass without all tests green** — STOP. Present what you've tried, what failed, and ask the user for direction. Do not spin indefinitely

Document assumptions at the top of your first response before writing test code.

## Phase 3 — VERIFY

10. **Invoke `review-gate`** — execute the review-gate skill now. Do not summarize or declare done until review-gate has completed and all findings are resolved

## Rules

- Read before edit — always. No exceptions
- If no test framework exists: state this, write the fix without TDD, but still trace first
- If no type checker exists: skip type checking, proceed with tests
- Do not ask clarifying questions — make reasonable assumptions and document them
- Do not show intermediate results — present final diff and test results when green
- If patrol plugin is active and fires a warning: comply immediately. Read the files it flags before continuing
