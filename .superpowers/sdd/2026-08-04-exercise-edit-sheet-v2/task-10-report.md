# Task 10 report — iOS persistence: calories + open goal

## Delivered

- Added first-class `calories` and `openGoal` fields to `SocialImportExercise`.
- Editor V2 persistence now carries both fields without encoding calories in
  freeform `notes`.
- Mapper blocks encode `calories`, hyphenated `reps_range`, and
  `goal: {"kind": "open"}`. Open goals retain `sets` but omit all competing
  metric fields (`reps`, `reps_range`, `duration_sec`, `distance_m`, and
  `calories`) even if stale values enter the mapper.
- Mapper now emits `sets` with every target kind, including calories, timed,
  distance, and open goals.
- Ingest decodes both `calories` and an open `goal.kind` back to the draft.
- Added regression coverage for Editor V2 → block → mapper persistence,
  ingest decoding, and the closed mapper → ingest → mapper round trip.

## Verification

- `git diff --check`: passed.
- IDE diagnostics: no errors in the six changed Swift files.
- Focused XCTest was attempted for the persistence regressions. It stalled
  during Swift Package dependency resolution while fetching remote
  dependencies, so it was stopped. No XCTest result is available.

## Commit

`607db0d feat(AMA-2379): persist calories + goal.kind=open on exercise wire`
