# AMA-275: Completion Detail Standardize — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add three missing pieces to CompletionDetailView: Activity metrics card, Strava button, and Done button.

**Architecture:** Surgical additions to one view file only. All conditional logic already exists on the model/viewmodel. No new model, API, or viewmodel changes. Existing tests already cover all the logic being used.

**Tech Stack:** SwiftUI, Swift 5.9+, iOS 17+, XCTest

---

## Prerequisites

Create the feature branch before starting:

```bash
cd /Users/davidandrews/dev/AmakaFlow/amakaflow-ios-app/amakaflow-ios-app
git fetch origin
git checkout main
git pull origin main
git checkout -b feat/ama-275-completion-detail-standardize
```

**Key file:** `AmakaFlow/Views/CompletionDetail/CompletionDetailView.swift`

**Reference files (read-only):**
- `AmakaFlow/Models/WorkoutCompletionDetail.swift` — properties: `hasSummaryMetrics`, `formattedCalories`, `formattedSteps`, `formattedDistance`
- `AmakaFlowCompanion/AmakaFlowCompanionTests/CompletionDetailTests.swift` — existing tests covering all logic used

**Build command:**
```bash
xcodebuild build \
  -scheme AmakaFlowCompanion \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -quiet \
  2>&1 | grep -E "(error:|warning:|BUILD SUCCEEDED|BUILD FAILED)"
```

---

## Task 1: Add Activity Card

The Activity card shows calories, steps, and distance between the HR chart and the ExecutionLogSection. It is only rendered when `detail.hasSummaryMetrics` is true.

**File to modify:** `AmakaFlow/Views/CompletionDetail/CompletionDetailView.swift`

### Step 1: Add the `activitySection` method

Add this new method after the closing brace of `heartRateSection` (currently ends around line 166). Place it in the `// MARK: - Activity Section` block:

```swift
// MARK: - Activity Section (AMA-275)

private func activitySection(_ detail: WorkoutCompletionDetail) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text("ACTIVITY")
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)

        HStack(spacing: 0) {
            statItem(value: detail.formattedCalories ?? "—", label: "CAL", color: .primary)
            Spacer()
            statItem(value: detail.formattedSteps ?? "—", label: "STEPS", color: .primary)
            Spacer()
            statItem(value: detail.formattedDistance ?? "—", label: "DIST", color: .primary)
        }
    }
    .frame(maxWidth: .infinity)
    .padding()
    .background(Theme.Colors.surface)
    .cornerRadius(12)
}
```

### Step 2: Render it in `detailScrollView`

In `detailScrollView`, after the `heartRateSection(detail)` call (currently line 75), add:

```swift
// Activity metrics (AMA-275)
if detail.hasSummaryMetrics {
    activitySection(detail)
}
```

The relevant section should look like this after the change:

```swift
VStack(spacing: 12) {
    // Header with completion badge and stats (AMA-292)
    headerSection(detail)

    // Heart Rate Chart Section
    heartRateSection(detail)

    // Activity metrics (AMA-275)
    if detail.hasSummaryMetrics {
        activitySection(detail)
    }

    // Execution Log (AMA-292)
    ExecutionLogSection(
        intervals: detail.hasExecutionLog ? detail.executionIntervals : ExecutionLogSection.sampleIntervals,
        summary: detail.hasExecutionLog ? detail.executionSummary : ExecutionLogSection.sampleSummary
    )
    // ... rest unchanged
```

### Step 3: Build

```bash
xcodebuild build \
  -scheme AmakaFlowCompanion \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -quiet \
  2>&1 | grep -E "(error:|warning:|BUILD SUCCEEDED|BUILD FAILED)"
```

Expected: `BUILD SUCCEEDED`

### Step 4: Commit

```bash
git add AmakaFlow/Views/CompletionDetail/CompletionDetailView.swift
git commit -m "feat(AMA-275): add Activity card to completion detail"
```

---

## Task 2: Wire Strava Button

The `stravaButton` computed var already exists in the file (around line 464) but is not rendered in `detailScrollView`. Wire it into the action button stack.

**File to modify:** `AmakaFlow/Views/CompletionDetail/CompletionDetailView.swift`

### Step 1: Add stravaButton to detailScrollView

In `detailScrollView`, after the `runAgainButton` conditional block (currently around lines 93-95):

```swift
// Run Again Button (AMA-237)
if viewModel.canRerun {
    runAgainButton
}

// Sync to Strava Button (AMA-275)
stravaButton
```

The section should look like:

```swift
// Save to Library Button (for voice-added workouts)
if viewModel.canSaveToLibrary {
    saveToLibraryButton
}

// Run Again Button (AMA-237)
if viewModel.canRerun {
    runAgainButton
}

// Sync to Strava Button (AMA-275)
stravaButton

// Edit Workout Button
editWorkoutButton
```

**Important:** `stravaButton` is unconditional — it always shows (either "Sync to Strava" or "View on Strava" based on sync state). The button text and action are already handled by `canSyncToStrava`, `stravaButtonText`, and `syncToStrava()` on the viewmodel.

### Step 2: Build

```bash
xcodebuild build \
  -scheme AmakaFlowCompanion \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -quiet \
  2>&1 | grep -E "(error:|warning:|BUILD SUCCEEDED|BUILD FAILED)"
```

Expected: `BUILD SUCCEEDED`

### Step 3: Commit

```bash
git add AmakaFlow/Views/CompletionDetail/CompletionDetailView.swift
git commit -m "feat(AMA-275): wire Strava button into action stack"
```

---

## Task 3: Add Done Button

Add an explicit Done button as the final action button. `dismiss` is already declared via `@Environment(\.dismiss) private var dismiss` at the top of the struct.

**File to modify:** `AmakaFlow/Views/CompletionDetail/CompletionDetailView.swift`

### Step 1: Add the `doneButton` computed var

Add this after the `stravaButton` section (around line 482) and before the `stravaToast` section. Match the same `// MARK: -` pattern:

```swift
// MARK: - Done Button (AMA-275)

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

### Step 2: Render doneButton in detailScrollView

After the `stravaButton` line added in Task 2, add:

```swift
// Done Button (AMA-275)
doneButton
```

The full action button block should now read:

```swift
// Save to Library Button (for voice-added workouts)
if viewModel.canSaveToLibrary {
    saveToLibraryButton
}

// Run Again Button (AMA-237)
if viewModel.canRerun {
    runAgainButton
}

// Sync to Strava Button (AMA-275)
stravaButton

// Done Button (AMA-275)
doneButton

// Edit Workout Button
editWorkoutButton

Spacer(minLength: 20)
```

### Step 3: Build

```bash
xcodebuild build \
  -scheme AmakaFlowCompanion \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -quiet \
  2>&1 | grep -E "(error:|warning:|BUILD SUCCEEDED|BUILD FAILED)"
```

Expected: `BUILD SUCCEEDED`

### Step 4: Commit

```bash
git add AmakaFlow/Views/CompletionDetail/CompletionDetailView.swift
git commit -m "feat(AMA-275): add Done button to completion detail"
```

---

## Verification Checklist

After all three tasks:

- [ ] `BUILD SUCCEEDED` with no new errors or warnings
- [ ] Activity card renders in Xcode Preview using `.sample` data (has all metrics)
- [ ] Activity card does NOT render in Preview using `.sampleNoHR` data (calories=50 is set, so it WILL render — test with a custom sample where all three metrics are nil to confirm conditional)
- [ ] Strava button shows "Sync to Strava" for `syncedToStrava = false`
- [ ] Strava button shows "View on Strava" for `syncedToStrava = true`
- [ ] Done button appears last, tapping it dismisses the view

## Final Commit Summary

Three commits total:
1. `feat(AMA-275): add Activity card to completion detail`
2. `feat(AMA-275): wire Strava button into action stack`
3. `feat(AMA-275): add Done button to completion detail`
