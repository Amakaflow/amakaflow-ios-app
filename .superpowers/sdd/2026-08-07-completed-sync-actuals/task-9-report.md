# AMA-2387 — Task 9 report: Verified card + editor ghost feed

**Status: CODE DONE**

## Built
- `ActualsVerifiedCard` / `ActualsVerifiedView` — callout + `WHAT YOU DID · VS PLAN` deltas (`+N KG VS PLAN` / `AS PLANNED`)
- `ActualsGhostFeed` — last verified actual precedes prescription; `showsLastTime` on editor drafts
- `ActualsRepository.latestActual(exerciseKey:)` for ghost lookup
- `DDEditorSeed.initialState` applies ghosts for `.edit` / `.backfill`
- Fill-in save → verified payoff screen
- Tests: `ActualsVerifiedGhostTests`

## Verify
- `xcodebuild build-for-testing` → **TEST BUILD SUCCEEDED** (`/tmp/ama-2387-t9-dd`)
- `test-without-building` hung on CoreSimulator boot (same env note as Tasks 1–8)
