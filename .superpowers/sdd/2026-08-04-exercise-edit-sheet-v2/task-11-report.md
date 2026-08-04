# Task 11 report — Editor V2 edit sheet

## Delivered

- Rebuilt the focused sheet around a full-width TARGET segmented control:
  Reps, Range, Timed, Cals, and Open.
- Added a live `summaryLine` below the exercise title, a stable 1:1.35 value
  grid, 72pt cells, range min/max clamping, timed and calorie step sizes, and
  the amber open-goal card.
- Kept AMA-2368 REST Open/Timed behavior and the open-rest watch caption.
- Added the requested `af_exsheet_*` accessibility identifiers and unit
  coverage for target-memory retention, range clamping, target identifiers,
  and Open serialization clearing competing targets.

## Verification

- `git diff --check`: passed.
- Focused `EditorV2Tests` was started with `xcodebuild`, but stopped while
  resolving the remote RevenueCat package. No XCTest result is available.

## Notes

- Done applies the selected target to the draft atomically, preserving sets
  while clearing every mutually exclusive metric field (including distance).

## Review follow-up

- Fixed distance-only rows: their displayed Reps default is inert until the
  athlete selects or edits a TARGET value, so Done preserves `distanceMeters`.
- Target provenance is now stamped only when the target intent differs from
  the sheet's initial intent; edits limited to sets or rest retain existing
  target provenance.
- Added regression tests for untouched distance preservation and unchanged
  target provenance.
- The focused XCTest retry again stalled resolving the remote RevenueCat
  package, so no XCTest result is available.

## Review follow-up 2

- Tapping the already-selected TARGET kind now leaves the target dormant for a
  distance-only row; selection arms a target only when the kind actually
  changes.
- Stepper and range mutations also arm only when their clamped value changes.
- Extracted the sheet commit path into `editorV2CommitEditDraft` and added a
  regression test that changes sets after a same-kind tap, then verifies the
  committed draft retains `distanceMeters`.
