# AMA-275: Standardize Workout Completion/Details Screen

**Date:** 2026-02-18
**Linear:** AMA-275
**Approach:** Surgical additions (Option A)

## Goal

Add three missing pieces to `CompletionDetailView` without reordering existing sections:
1. Activity card (calories, steps, distance) — new section after HR chart
2. Strava button — wire up existing dead-code button into the action stack
3. Done button — explicit dismiss, needed for sheet presentation contexts

## What Is NOT Changing

- Section ordering stays the same
- ExecutionLogSection is kept (not replaced by WorkoutStepsSection)
- ViewModel is untouched — all needed data already exists
- No new models, no API changes
- editWorkoutButton stays (out of scope)

## Design

### Section order after this change

```
Header card          (unchanged)
HR chart card        (unchanged)
Activity card        ← NEW (conditional: only if hasSummaryMetrics)
ExecutionLogSection  (unchanged)
Source info card     (unchanged)
saveToLibraryButton  (unchanged, conditional)
runAgainButton       (unchanged, conditional)
stravaButton         ← NOW RENDERED (was dead code in the file, now in stack)
doneButton           ← NEW
```

### Activity card

New private method `activitySection(_ detail: WorkoutCompletionDetail) -> some View`.

Displayed as a surface card (same style as other cards: `Theme.Colors.surface`, `cornerRadius(12)`).

Shows three stat items in a horizontal row using the existing `statItem(value:label:color:)` helper:
- Calories: `detail.formattedCalories ?? "—"`, label `"CAL"`, color `.primary`
- Steps: `detail.formattedSteps ?? "—"`, label `"STEPS"`, color `.primary`
- Distance: `detail.formattedDistance ?? "—"`, label `"DIST"`, color `.primary`

Only rendered when `detail.hasSummaryMetrics` is `true` (existing property on `WorkoutCompletionDetail`).

### Strava button (wired)

`stravaButton` computed var already exists — just add it to `detailScrollView` after `runAgainButton`.

No logic changes: `canSyncToStrava`, `stravaButtonText`, `syncToStrava()` are all implemented.

### Done button

New private computed var `doneButton`:

```swift
private var doneButton: some View {
    Button("Done") {
        dismiss()
    }
    .font(.headline)
    .foregroundColor(.primary)
    .frame(maxWidth: .infinity)
    .padding()
    .background(Theme.Colors.surface)
    .cornerRadius(12)
}
```

`dismiss` is already imported via `@Environment(\.dismiss) private var dismiss`.

## Files Changed

- **Modify:** `AmakaFlow/Views/CompletionDetail/CompletionDetailView.swift`
  - Add `activitySection` method (~20 lines)
  - Add `doneButton` computed var (~15 lines)
  - Update `detailScrollView` to render activity card, stravaButton, doneButton

## Files NOT Changed

- `CompletionDetailViewModel.swift` — no changes
- `WorkoutCompletionDetail.swift` — no changes
- `ExecutionLogSection.swift` — no changes
- Any other subviews or models

## Acceptance Criteria

- [ ] Activity card appears between HR chart and ExecutionLogSection when calories/steps/distance are present
- [ ] Activity card does NOT appear when `hasSummaryMetrics` is false (e.g. `sampleNoHR` fixture)
- [ ] Strava button appears below Run Again button, showing "Sync to Strava" or "View on Strava" based on sync state
- [ ] Done button appears as the last item, calls dismiss()
- [ ] `#Preview` renders correctly with `.sample` data (all metrics present)
- [ ] No compiler warnings introduced
