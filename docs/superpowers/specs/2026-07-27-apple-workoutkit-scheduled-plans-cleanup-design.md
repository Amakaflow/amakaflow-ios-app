# Apple WorkoutKit — scheduled plans cleanup (multi-select)

**Date:** 2026-07-27  
**Parent:** AMA-2287  
**Linear:** [AMA-2330](https://linear.app/amakaflow/issue/AMA-2330/apple-workout-manage-delete-scheduled-workoutkit-plans)  
**Status:** Final — ready to implement  
**Repos:** `amakaflow-ios-app` (Live adapter in-app for V1; `workoutkit-sync` list/remove wrappers deferred)

## Problem

Every Start → Workout on Apple Watch **adds** another AmakaFlow-scheduled plan. The Watch Workout UI does not reliably delete those cards, so duplicates pile up under “Today.”

Users also need more than one planned workout at a time. Auto-`removeAllWorkouts()` on Start would break that.

## Decisions (locked)

| Decision | Choice |
| --- | --- |
| Start behavior | **Keep adding** — no automatic remove/replace |
| Cleanup | **User-initiated only** |
| V1 delete modes | Multi-select, swipe/single delete, Clear all |
| Surface | iPhone AmakaFlow — not Watch |
| Entry | Devices → **Scheduled in Workout**; Start success → **Manage scheduled plans** |
| Screen / VM | `WorkoutScheduleView` / `WorkoutScheduleViewModel` |
| Protocol | `WorkoutKitScheduleManaging` (app-shaped; mirrors `WorkoutKitSaving`) |
| Pre-iOS 18 | **Hide** Devices row and Manage link |
| Completed rows | Dedicated **Completed** section (muted), below **Scheduled** |

## Success criteria

| Check | Pass looks like |
| --- | --- |
| List | Newest-first; title + relative time; Scheduled then Completed |
| Multi-select / swipe / Clear all | Targeted plans gone after re-fetch (or still-present after refresh → retry) |
| Manual refresh | Clears selection and exits edit mode |
| Post-delete | `failedIDs = attempted ∩ stillPresent`; those stay selected for retry |
| Start under cap | Schedules without deleting others |
| Start at cap | Friendly failure pointing at this screen |
| Auth denied | Banner (not empty state) |
| Authorized + empty | “No AmakaFlow plans in Workout” |
| Loading / error | Progress on first load; inline error keeps prior rows if any |

## UX

**Entry**

1. Devices → **Scheduled in Workout** → `WorkoutScheduleView` (iOS 18+ only; hidden otherwise).
2. Start success (`kind == .savedToFitness`) → **Manage scheduled plans** under status (push or sheet).

**List** — Duplicate titles with near-identical times are normal. Newest-first within each section; relative subtitle (`RelativeDateTimeFormatter`); absolute time in accessibility. **Scheduled** (incomplete) then **Completed** (muted).

**Toolbar** — Select / Done; Clear all when list non-empty; Delete (N) only when N ≥ 1; swipe-to-delete when not editing.

**Footnote** (when non-empty): “Changes may take a moment to appear on Apple Watch.”

**Confirms**

- Delete N: “Remove N AmakaFlow workout plan(s) from Apple Watch Workout?”
- Clear all: “Remove all AmakaFlow plans from the Workout app? This can’t be undone — you can re-schedule any workout from its Start button.”

**Auth** — Driven by protocol `authorizationState`, not by empty fetch:

| State | UI |
| --- | --- |
| `.denied` | Banner + **Open Settings** (`UIApplication.openSettingsURLString`) |
| `.notDetermined` | Request authorization on appear (same pattern as Start) |
| `.authorized` + empty rows | Empty state copy |
| `.authorized` + rows | List |

**Loading / empty / error** — Progress while loading with no rows; empty copy only when authorized and zero rows; errors show inline `statusMessage` and keep prior rows if any.

## Architecture

```
WorkoutScheduleView + WorkoutScheduleViewModel
  → WorkoutKitScheduleManaging
       Live @available(iOS 18.0, *): WorkoutScheduler.shared
       Mock: in-memory for unit tests
```

### Apple APIs (verify against SDK before Live)

| API | Signature |
| --- | --- |
| List | `var scheduledWorkouts: [ScheduledWorkoutPlan] { get async }` |
| Remove one | `func remove(_ workout: WorkoutPlan, at: DateComponents) async` |
| Clear | `func removeAllWorkouts() async` |
| Cap | `static let maxAllowedScheduledWorkoutCount: Int` |
| Auth | `var authorizationState: AuthorizationState { get async }` (+ `requestAuthorization()`) |

`remove` / `removeAllWorkouts` / `scheduledWorkouts` are async and **non-throwing**. Do not invent throw-on-remove. Cap copy says “Apple’s schedule limit” — never hardcode `15`.

### Protocol (app-shaped)

```swift
enum ScheduleAuthState: Sendable {
    case authorized, denied, notDetermined
}

protocol WorkoutKitScheduleManaging: Sendable {
    var authorizationState: ScheduleAuthState { get async }
    var maxAllowedCount: Int { get }
    func requestAuthorization() async -> ScheduleAuthState
    func fetchScheduledRows() async throws -> [WorkoutScheduleRow]
    func remove(row: WorkoutScheduleRow) async
    func removeAll() async
}
```

- `fetchScheduledRows()` may throw for app-level mapping / unexpected failures; Apple’s list itself does not throw.
- `remove` / `removeAll` are **non-throwing**, matching Apple. Failure is observed only as **still present after refresh**.

### Row model + Live cache

`WorkoutScheduleRow`: `id`, `title`, `dateComponents` (exact fetched), `scheduledAt`, `isComplete`.

**Live plan lookup (locked):** On each successful `fetchScheduledRows()`, Live caches `WorkoutPlan` by `WorkoutScheduleRowID`. `remove(row:)` looks up that cache and calls `remove(cachedPlan, at: row.dateComponents)`. Missing cache entry → no-op (composes with still-present detection). Do **not** re-fetch inside every `remove` (avoids N+1).

### Row identity

One helper for prod and tests: `WorkoutScheduleRowID(planID:date:)`. Canonical serialization in fixed field order; include `calendar` / `timeZone` only when present on the fetched components; omit nils consistently.

### Selection vs refresh (normative — single source of truth)

1. **Successful manual refresh** (pull-to-refresh / onAppear after auth): `selectedIDs = []`, `isEditing = false`.
2. **Post-mutation refresh after a delete batch:** `failedIDs = attemptedIDs ∩ idsPresentAfterRefresh`; `selectedIDs = failedIDs`; `isEditing = !failedIDs.isEmpty`. Empty failed → exit edit + success status.

Retry = `deleteSelected()` on the current selection only (IDs absent from the list are never removed).

## Data flow

1. Read `authorizationState` → banner / request / proceed.
2. `fetchScheduledRows()` → sort → section → apply selection rule (1) or (2).
3. Delete selected → for each currently listed selected row, `await remove(row:)` using cached plan + stored `dateComponents`.
4. After batch → refresh with rule (2); status “Removed K of N; tap to retry” when failed non-empty.
5. Clear all → `await removeAll()` → refresh with rule (1).

### Start at cap

When count ≥ `maxAllowedCount`: preflight in handoff → failed copy pointing at Manage / Devices. Never auto-delete to make room.

**Dogfood:** fill to cap; record Start failure mode; record whether `complete == true` plans count toward the cap. If yes, amend at-cap copy to mention clearing Completed.

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

- Newest-first; Completed section after Scheduled  
- Delete calls `remove` once per selected id with exact stored row / `DateComponents` (**mock-level**; Live `plan + date` → `remove(_:at:)` verified by code review + dogfood — unit tests cannot link WorkoutKit)  
- Empty selection does not call `remove`  
- Clear all calls `removeAll` once  
- Manual refresh clears selection / exits edit  
- Silent no-op remove → still-present IDs stay selected; retry only those  
- Auth: denied → banner path; authorized + empty → empty state (not banner)  
- Cap warning when count ≥ `maxAllowedCount`  

### Dogfood

- Start 2–3 → list + relative times  
- Delete / multi-select / Clear all vs Watch  
- Watch lag ~30s accepted  
- At cap + whether completed counts toward cap (record in gaps README)  

## Risks

| Risk | Mitigation |
| --- | --- |
| Watch lag | Persistent footnote; ~30s accepted |
| Wrong plan/date | Live cache from last fetch + stored `dateComponents` |
| Silent remove no-op | Still-present after refresh |
| Empty vs denied | `authorizationState` on protocol |
| Schedule cap | `maxAllowedCount`; preflight; completed-vs-cap dogfood |
| Duplicate titles | Newest-first + relative times + Completed section |

## Implementation checklist

1. Verify SDK signatures (list / remove / clear / cap / auth)  
2. Protocol + Live (cache rule) + Mock  
3. Canonical `WorkoutScheduleRowID`  
4. ViewModel (auth branch, selection rules, still-present detection)  
5. `WorkoutScheduleView`  
6. Devices entry (hidden pre-iOS 18)  
7. Start success → Manage scheduled plans  
8. Start at-cap preflight + copy  
9. Unit tests (incl. auth vs empty, still-present retry)  
10. Gaps README (duplicates → screen; Watch lag; at-cap; completed-vs-cap?)  
11. Do **not** auto-remove on Start  

---

**Revision hygiene:** Before treating any future edit as final, regenerate conflicting sections into a single clean draft and re-read the document top-to-bottom once — do not patch over prior wording in place.
