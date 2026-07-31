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

## Important review fixes

- Clear now obtains the server-normalized title before removing a loaded
  `user_pick` chip. Online save therefore keeps the cleared canonical fields
  null instead of reapplying the same match.
- If the clear-time lookup soft-fails, the next successful match for that same
  title establishes suppression before it can apply; save remains non-blocking.
- A successful no-match response now removes a stale `.auto` chip while leaving
  `user_pick` and `preset` ownership locks unchanged.

## Review-fix verification

TDD red was confirmed for both review regressions: the loaded `user_pick` clear
test failed by restoring `tempo_run` as `.auto`, and the no-match test failed by
retaining the prior auto chip.

```text
xcodebuild test \
  -project AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj \
  -scheme AmakaFlowCompanion \
  -destination 'platform=iOS Simulator,id=CC96CAB1-5E7D-4FE6-8559-23809EBEB86E' \
  -only-testing:AmakaFlowCompanionTests/WorkoutCanonicalNamingTests \
  -only-testing:AmakaFlowCompanionTests/WorkoutEditorSaveTests \
  -skip-testing:AmakaFlowCompanionUITests \
  -parallel-testing-enabled NO

Executed 30 tests, 0 failures — TEST SUCCEEDED
```
