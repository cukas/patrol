---
name: review-gate
description: Use after completing any code implementation, bug fix, or refactor. Structured review with pass/fail verification before declaring done.
---

# Review-Gate

Structured post-implementation review. Nothing passes without evidence.

## 1. Trace affected code paths

Use Read, Grep, and Glob to trace the call chain from each changed function to its callers and dependents. For changes that touch multiple files or cross API boundaries, trace both directions.

## 2. Bug pattern scan

Check every changed file for:
- **Null safety:** optional chaining gaps, unchecked nullable values, NonNullable casts without guards
- **Async errors:** missing await, unhandled promise rejections, race conditions
- **Stale data:** old values in caches, persisted state, or UI that survive restarts
- **Off-by-one:** index boundaries, array length vs last index, loop bounds
- **Import errors:** missing imports, circular dependencies, wrong paths
- **Security:** unsanitized input, eval usage, SQL/command injection, hardcoded secrets
- **Error handling:** swallowed exceptions, missing catch blocks, generic error responses

## 3. Build verification

Discover and run the project's build command:
- Check `package.json` scripts, `Makefile`, `Cargo.toml`, `pyproject.toml`, or README
- Run the build — confirm it succeeds
- If multiple build targets exist (e.g., plugin + shared types), rebuild all

## 4. Type and test verification

- Run the type checker (e.g., `npx tsc --noEmit`, `pyright`, `cargo check`)
- Run the test suite (e.g., `npm test`, `pytest`, `cargo test`)
- Fix all failures before proceeding
- If no type checker or test suite exists: state this explicitly in the report

## 5. Architectural check

Find 2-3 examples of the same pattern used elsewhere in the codebase. Confirm the change is consistent with them. Flag if:
- The change introduces a pattern not used anywhere else
- A simpler approach already exists in the codebase
- Unnecessary abstractions or over-engineering were added

## 6. Report

Present findings in this format:

```
## Review-Gate Report

| Check | Status | Notes |
|-------|--------|-------|
| Code path trace | PASS/FAIL | [what was traced] |
| Bug pattern scan | PASS/FAIL | [issues found or clean] |
| Build | PASS/FAIL | [command run + result] |
| Type check | PASS/FAIL/SKIP | [command run + result] |
| Tests | PASS/FAIL/SKIP | [command run + result] |
| Architecture | PASS/FAIL | [consistency notes] |

### Issues Found
- [list each issue and the fix applied, or "None"]

### Final Status: PASS / FAIL
```

Do not declare done until all checks PASS or are explicitly SKIP with reason.
