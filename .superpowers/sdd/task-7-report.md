# Task 7 report — iOS workout type match chip

## Status

Implemented the soft canonical workout-type chip in Editor V2, including the
candidate/catalog picker, clear behavior, title-idle/blur matching, loaded-ID
resolution, and canonical save wiring.

## Delivered

- Added `WorkoutTypeMatchChip` under the title and above the editor subtitle.
- Added `WorkoutTypeMatchSheet` with last-match candidates, full-catalog search,
  user pick, and clear actions.
- Debounced title matching by 600 ms and matched immediately on title blur.
- Kept taxonomy failures advisory so they never block workout save.
- Preserved user-picked matches across title renames and ignored stale responses.
- Decoded canonical fields on loaded workouts; unknown catalog IDs omit the chip.
- Passed canonical ID/source through `WorkoutEditorViewModel` to
  `WorkoutSaveRequest`.

## Tests

TDD red was confirmed before implementation for missing candidate state, loaded
display-name resolution, and editor save wiring.

```text
xcodebuild test ... \
  -only-testing:AmakaFlowCompanionTests/WorkoutCanonicalNamingTests \
  -only-testing:AmakaFlowCompanionTests/WorkoutEditorSaveTests

Executed 28 tests, 0 failures — TEST SUCCEEDED
```

## Remaining Task 9 dogfood

Simulator UI dogfood was not performed in this task. Verify:

- Type `Tempo Run` and pause/blur → `Matched: Tempo Run ›` appears.
- Tap the chip → top candidates and catalog search are usable.
- Clear match → chip disappears; save emits null canonical fields.
- Pick a type, rename the title → the picked chip remains.
- In airplane mode with a prior chip → save keeps the last-known match.
- Load a workout with an unknown/retired canonical ID → no chip appears.
