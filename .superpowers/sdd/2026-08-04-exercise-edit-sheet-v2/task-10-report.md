# Task 10 report — iOS persistence: calories + open goal

## Delivered

- Added first-class `calories` and `openGoal` fields to `SocialImportExercise`.
- Editor V2 persistence now carries both fields without encoding calories in
  freeform `notes`.
- Mapper blocks encode `calories`, hyphenated `reps_range`, and
  `goal: {"kind": "open"}`. Open goals retain `sets` but omit all competing
  metric fields (`reps`, `reps_range`, `duration_sec`, `distance_m`, and
  `calories`) even if stale values enter the mapper.
- Ingest decodes both `calories` and an open `goal.kind` back to the draft.
- Added regression coverage for Editor V2 → block → mapper persistence and
  ingest decoding.

## Verification

- `git diff --check`: passed.
- IDE diagnostics: no errors in the six changed Swift files.
- Attempted Xcode project discovery before the focused XCTest run. It stalled
  for three minutes in Swift Package dependency resolution while fetching
  remote dependencies, so it was stopped. No XCTest result is available.

## Commit

Pending.
