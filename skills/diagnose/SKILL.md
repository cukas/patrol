---
name: diagnose
description: Use when investigating a bug or unexpected behavior. Forces structured root-cause investigation before any code changes. Trace the call chain, document hypotheses, confirm the root cause, then fix.
---

# Structured Root-Cause Investigation

**You are in investigation mode.** Do NOT edit any code until you complete the protocol below.

## Protocol

### Step 1: Understand the symptom
- What exactly is the user reporting?
- What is the expected behavior vs actual behavior?
- Can you reproduce it? Under what conditions?

### Step 2: Trace the code path
- Read all files in the call chain from entry point to where the bug manifests
- For each file, note: what it does, what it passes to the next layer, where it could go wrong
- Do NOT skip files — read every file in the path

### Step 3: Form a hypothesis
- Based on the code you've read, what is the most likely root cause?
- What evidence supports this hypothesis?
- What would disprove it?
- Rate your confidence: LOW / MEDIUM / HIGH

### Step 4: Verify the hypothesis
- If confidence is LOW: read more files, check related tests, grep for similar patterns
- If confidence is MEDIUM: check edge cases and error handling in the suspected area
- If confidence is HIGH: proceed to Step 5

### Step 5: Present analysis
Before writing ANY code, present to the user:
1. **Root cause:** One sentence explaining what's broken and why
2. **Evidence:** Which files/lines confirmed this
3. **Proposed fix:** What you'll change and why
4. **Risk:** What else could this fix affect?

### Step 6: Implement and verify
- Apply the minimal fix
- Run build and tests
- Confirm the fix addresses the symptom

## Example Investigation

**Symptom:** "The sidebar counter shows 0 items even after adding tasks."

**Step 1 — Understand:** Expected: counter increments when a task is added. Actual: always shows 0. Reproducible on every add.

**Step 2 — Trace:** Read `TaskList.tsx` (renders counter) → `useTaskStore.ts` (Zustand store) → `addTask()` action → `Sidebar.tsx` (subscribes to `tasks.length`).

**Step 3 — Hypothesis:** `Sidebar.tsx` subscribes to `store.tasks` but `addTask()` mutates the array in place instead of creating a new reference. Zustand's shallow comparison doesn't detect the change. Confidence: HIGH — the `push()` call on line 42 of `useTaskStore.ts` is the smoking gun.

**Step 4 — Verify:** Confirmed: `addTask` does `state.tasks.push(task)` instead of `tasks: [...state.tasks, task]`. Zustand docs confirm shallow equality check requires new references.

**Step 5 — Present:** Root cause: in-place mutation. Fix: spread into new array. Risk: low — only changes the add path, existing reads unaffected.

**Step 6 — Implement:** Change `push()` to spread, run `pnpm test`, verify counter updates.

## Anti-Patterns to Avoid
- Editing a file you haven't read
- Trying a fix "to see if it works"
- Changing thresholds or config values as a first fix
- Adding try/catch blocks around the symptom instead of fixing the cause
- Declaring "this might be a platform limitation" without evidence
