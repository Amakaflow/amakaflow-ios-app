# Apple WorkoutKit — scheduled plans cleanup (multi-select)

**Date:** 2026-07-27  
**Parent:** AMA-2287  
**Linear:** [AMA-2330](https://linear.app/amakaflow/issue/AMA-2330/apple-workout-manage-delete-scheduled-workoutkit-plans)  
**Status:** Final — ready for implementation  
**Repos:** `amakaflow-ios-app` (Live adapter in-app for V1; `workoutkit-sync` list/remove wrappers deferred)

## Problem

Every Start → Workout on Apple Watch **adds** another AmakaFlow-scheduled plan. The Watch Workout UI does not reliably delete those cards, so duplicates pile up under “Today.”

Users also need more than one planned workout at a time (e.g. morning + evening). Auto-`removeAllWorkouts()` on Start would break that.

## Decisions (locked)

| Decision | Choice |
| --- | --- |
| Start behavior | **Keep adding** — no automatic remove/replace |
| Cleanup | **User-initiated only** |
| V1 delete modes | Multi-select, swipe/single delete, and Clear all |
| Surface | iPhone AmakaFlow — not Watch |
| Entry | Devices → **Scheduled in Workout**, and Start success → **Manage scheduled plans** |
| Screen / VM | `WorkoutScheduleView` / `WorkoutScheduleViewModel` |
| Protocol | `WorkoutKitScheduleManaging` (mirrors `WorkoutKitSaving`) |
| Pre-iOS 18 | **Hide** Devices row and Manage link (Start already communicates the gate) |
| Completed rows | Separate **Completed** section at the bottom (muted); incomplete above, newest-first in each section |

## Success criteria

| Check | Pass looks like |
| --- | --- |
| List | Newest-first; title + relative time (“Scheduled 2h ago”); incomplete section then Completed |
| Multi-select | Select N → Delete → confirm → those N gone after re-fetch (or marked failed if still present) |
| Single | Swipe delete removes one plan |
| Clear all | Confirm → `removeAllWorkouts()` → list empty after re-fetch |
| Manual refresh | Pull-to-refresh clears selection and exits edit mode |
| Post-delete outcome | Re-fetch; still-present attempted IDs = failed; those stay selected in edit mode for retry |
| Start under cap | Still schedules without deleting others |
| Start at cap | Friendly failure pointing at this screen — not silent success |
| Auth | Inline banner with Settings action; no crash |
| Empty | “No AmakaFlow plans in Workout” |
| Loading | Progress indicator while first fetch / refresh runs |
| Error | Inline status message; list retained if previously loaded |

## UX

### Entry

1. **Devices** → **Scheduled in Workout** → `WorkoutScheduleView` (iOS 18+ only; hidden otherwise).
2. **Start success** (`kind == .savedToFitness`): **Manage scheduled plans** under the status line → same screen (push or sheet).

### Screen

Duplicates with the same title and near-identical times are **normal**. The list makes them legible; multi-select and Clear all do the cleanup.

| Element | Behavior |
| --- | --- |
| Sort | Newest-first within each section (`Date` from fetched `DateComponents`) |
| Subtitle | Relative time (`RelativeDateTimeFormatter`); absolute time in accessibility |
| Sections | **Scheduled** (incomplete), then **Completed** (muted / lower opacity) |
| Select / Done | Toggles edit mode |
| Clear all | Shown whenever the list is non-empty |
| Delete (N) | Shown only when N ≥ 1 |
| Swipe | Deletes one row when not editing |
| Footnote | Always when non-empty: “Changes may take a moment to appear on Apple Watch.” |

### Confirm copy

- Delete N: “Remove N AmakaFlow workout plan(s) from Apple Watch Workout?”
- Clear all: “Remove all AmakaFlow plans from the Workout app? This can’t be undone — you can re-schedule any workout from its Start button.”

### Auth banner

Non-modal banner above the list when authorization is denied / not usable.

- Body: same guidance as Start (*Settings → Health → Data Access → AmakaFlow, allow Workouts*).
- Primary action: open the app’s Settings page (`UIApplication.openSettingsURLString`). Do not re-run the system authorization sheet from this screen (Start remains the first-grant path).

### Loading / empty / error

- **Loading:** Progress while `isLoading` and no rows yet.
- **Empty:** “No AmakaFlow plans in Workout” when fetch succeeds with zero rows.
- **Error:** Keep prior rows if any; show inline `statusMessage`. Auth errors also set the banner.

## Architecture

```
WorkoutScheduleView + WorkoutScheduleViewModel
  → WorkoutKitScheduleManaging
       Live @available(iOS 18.0, *): WorkoutScheduler.shared
       Mock: in-memory rows for unit tests
```

### Apple APIs (verify against SDK before writing Live)

| API | Signature |
| --- | --- |
| List | `var scheduledWorkouts: [ScheduledWorkoutPlan] { get async }` |
| Remove one | `func remove(_ workout: WorkoutPlan, at: DateComponents) async` |
| Clear | `func removeAllWorkouts() async` |
| Cap | `static let maxAllowedScheduledWorkoutCount: Int` |

`remove` and `removeAllWorkouts` are **async and non-throwing**. Live remove must not invent throw-on-failure. Call site for one row:

```swift
await WorkoutScheduler.shared.remove(scheduled.plan, at: scheduled.date)
```

Use `maxAllowedScheduledWorkoutCount` in code and “Apple’s schedule limit” in copy — never hardcode `15`.

### Protocol seam

```swift
protocol WorkoutKitScheduleManaging: Sendable {
    func fetchScheduledRows() async throws -> [WorkoutScheduleRow]
    func remove(row: WorkoutScheduleRow) async throws  // throws reserved for future; Live does not throw on remove
    func removeAll() async throws                      // same
    var maxAllowedCount: Int { get }
}
```

Row model retains enough to call Apple’s API without reconstruction:

- `id: WorkoutScheduleRowID`
- `title`
- `dateComponents` (exact fetched value)
- `scheduledAt: Date?` (resolved for sort/display)
- `isComplete`
- Live-only handle sufficient to recover `WorkoutPlan` for `remove` (re-match on id after fetch, or store plan reference behind the Live adapter)

### Row identity

One helper used by production and tests:

`WorkoutScheduleRowID(planID:date:)` → `planID` + canonical serialization of `DateComponents`.

Serialize fields in fixed order (`year`, `month`, `day`, `hour`, `minute`, `second`, `nanosecond`, and `calendar` / `timeZone` **only if present** on the fetched components). Omit nils consistently so two refreshes of the same schedule hash equal.

### Selection vs refresh (normative)

1. **Successful manual refresh** (pull-to-refresh / onAppear load): `selectedIDs = []`, `isEditing = false`.
2. **Post-mutation refresh after a delete batch:** do **not** apply rule 1. Compute  
   `failedIDs = attemptedIDs ∩ idsPresentAfterRefresh`  
   then `selectedIDs = failedIDs`, `isEditing = !failedIDs.isEmpty`.  
   If `failedIDs` is empty, exit edit mode and show success.

Retry is simply `deleteSelected()` again on the surviving selection — never call `remove` for IDs absent from the current list.

## Data flow

1. Load / manual refresh → `fetchScheduledRows()` → sort → section → apply selection rule (1) or (2) above.
2. Delete selected → for each **currently listed** selected row, `remove(row:)` using stored `plan` + `dateComponents` (never recompute “now”).
3. Clear all → `removeAll()` → refresh with rule (1).
4. After delete batch → refresh → apply rule (2); status “Removed K of N; tap to retry” when `failedIDs` non-empty (K = attempted − failed, N = attempted).

Sequential `remove` in the ViewModel is fine under Apple’s cap. Protocol stays per-row so a future batch API is a ViewModel-local swap.

### Start at cap

When `scheduledWorkouts.count >= maxAllowedScheduledWorkoutCount`:

1. **Dogfood:** fill to cap, Start again, record throw vs silent no-op vs false success.
2. **Product:** preflight in handoff → failed result with Manage / Devices copy. Do **not** auto-delete to make room.
3. **Dogfood question (record in gaps README):** do `complete == true` plans count toward the cap?  
   - If **yes**, Completed-section cleanup is the primary unblock and at-cap copy should mention removing completed plans.  
   - If **no**, no copy change.
4. List load at cap → log a warning (dogfood signal).

## Non-goals

- Auto-replace / remove-before-schedule on Start  
- Deleting from Watch UI  
- Editing schedule time on this screen  
- Garmin / AmakaFlowWatch lists  
- Composition export (AMA-2329)  
- Scheduling new plans from this screen  
- Moving list/remove into `workoutkit-sync` in V1  

## Testing

### Unit

- Load: newest-first; Completed section after Scheduled  
- Delete calls `remove` once per selected id with exact stored `DateComponents`  
- Empty selection does not call `remove`  
- Clear all calls `removeAll` once  
- Manual refresh clears selection and exits edit mode  
- **Production-shaped failure:** mock `remove` is a no-op that leaves rows present → after batch + refresh, `selectedIDs == attempted ∩ stillPresent`, edit mode stays on, status invites retry  
- Retry only targets IDs still in the list  
- Cap warning when count ≥ `maxAllowedCount`  

### Dogfood

- Start 2–3 times → list shows relative times  
- Delete one / multi-select / Clear all vs Watch list  
- Watch lag: delete on iPhone → Watch may still show card ~30s (accepted)  
- At cap + whether completed counts toward cap (record in `docs/ama-2287-visual-evidence/README.md`)  

## Risks

| Risk | Mitigation |
| --- | --- |
| Watch lag | Persistent footnote; document ~30s lag as accepted |
| Wrong plan/date on remove | Retain fetched `plan` + `date`; unit-test passthrough |
| Silent remove no-op | Detect via re-fetch ∩ attempted IDs — not via throws |
| Auth denied | Inline banner → Settings deep link |
| Schedule cap | `maxAllowedScheduledWorkoutCount`; preflight + dogfood completed-vs-cap |
| Duplicate titles | Newest-first + relative times + Completed section |

## Implementation checklist

- [ ] Verify `remove(_:at:)` / `removeAllWorkouts()` / `maxAllowedScheduledWorkoutCount` against iOS 18 SDK  
- [ ] `WorkoutKitScheduleManaging` + Live (iOS 18) + Mock  
- [ ] Canonical `WorkoutScheduleRowID` helper shared by prod and tests  
- [ ] ViewModel: load, sections, selection rules (1)/(2), delete, clear, still-present failure detection  
- [ ] `WorkoutScheduleView`: UI states, confirms, footnote, auth banner → Settings  
- [ ] Devices entry (hidden pre-iOS 18)  
- [ ] Start success → Manage scheduled plans  
- [ ] Start at-cap preflight + copy  
- [ ] Unit tests for still-present-after-refetch and selection ∩ refresh  
- [ ] Update gaps README (duplicates → this screen; Watch lag; at-cap; completed-counts-toward-cap?)  
- [ ] Do **not** auto-remove on Start  

---

**Revision hygiene:** This document is a single regenerated draft. Before treating any future edit as final, rewrite conflicting sections clean and re-read top-to-bottom once — do not patch over prior wording in place.
