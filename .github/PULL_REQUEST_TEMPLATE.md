<!--
AmakaFlow PR template. See docs/testing/blueprint.md for the 4-layer testing model.

Required: Test impact + Validation summary + Merge rule sections must be filled.
-->

## Summary

<!-- 1-3 bullets on what changed and why. -->

## Test impact
- Critical journey affected:
- Layers required: <!-- L1 / L2 / L3 / L4 — pick what applies -->
- Contracts changed: <!-- Yes/No -->
- New fixtures added: <!-- Yes/No -->

## Validation summary

| Layer | Status | Link |
|---|---|---|
| L1 (FastAPI pytest) |  |  |
| L2 (XCTest) |  |  |
| L3 (XCUITest) |  |  |
| L4 (Maestro evidence) |  |  |

## Known blockers
<!-- Infrastructure blockers as separate Linear tickets — link them here, not buried in test results. -->
- 

## Verify by
<!--
AMA-1853 / Production-Readiness gap #4: every PR must tell the reviewer
exactly how to confirm the change works WITHOUT re-running it. Two-line
bullets in the form "thing to look at → expected result". The reviewer
will often be on a phone — link to GitHub artifacts, Linear tickets,
Maestro evidence dirs, or single shell commands they can paste into a
terminal. Do NOT just say "run the tests".

Example:
- `gh pr view 213 --json mergedAt` → returns non-null mergedAt
- Maestro evidence at `e2e/evidence/ama-1834-l4/run-fix6/screenshots/` → `step10a-history-row-found.png` is the load-bearing artifact
- Linear AMA-1844 → status = Done
-->
- 

## Merge rule
- [ ] This PR meets all required layers for its scope
- [ ] This PR does not rely on Maestro alone as validation
- [ ] Consolidated test report attached or linked

## Linear

- Closes:
- Refs:

🤖 Generated with [Claude Code](https://claude.com/claude-code)
