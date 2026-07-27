# Apple WorkoutKit — scheduled plans cleanup (multi-select)

**Date:** 2026-07-27  
**Parent:** AMA-2287  
**Linear:** [AMA-2330](https://linear.app/amakaflow/issue/AMA-2330/apple-workout-manage-delete-scheduled-workoutkit-plans)  
**Status:** Approved for implementation planning (review adjustments incorporated)  
**Repos:** `amakaflow-ios-app` (list/remove Live adapter in-app for V1; thin wrappers in `workoutkit-sync` deferred)

## Problem

Dogfood of WorkoutKit-primary Start works (including sets/reps fidelity), but every Start **adds** another plan. The Watch Workout UI does not give a reliable way to delete AmakaFlow-managed cards, so duplicates pile up under “Today” and bury the current workout.

Users also need **more than one** planned workout at a time (e.g. morning + evening). Auto-`removeAllWorkouts()` on every Start would break that.

## Decisions (locked)

| Decision | Choice |
| --- | --- |
| Start behavior | **Keep adding** — no automatic remove/replace |
| Cleanup | **User-initiated only** |
| V1 delete modes | **Multi-select**, **single**, and **Clear all** |
| Surface | **iPhone** AmakaFlow — not Watch |
| Entry | **Devices** + **Manage scheduled plans** link on Start success status |
| Scope of scheduler APIs | Only plans owned by this app (`WorkoutScheduler` is per-app) |
| Screen name | `WorkoutScheduleView` (matches `WorkoutScheduler`) |

## Success criteria

| Check | Pass looks like |
| --- | --- |
| List | Newest-first; title + relative time (“scheduled 2h ago”); incomplete first, completed de-emphasized / sectioned below |
| Multi-select | Select N → Delete → confirm → those N gone after refresh |
| Single | Swipe delete or select-one + Delete removes one plan |
| Clear all | Confirm → `removeAllWorkouts()` → list empty |
| Refresh | Pull-to-refresh **clears selection and exits edit mode** |
| Partial failure | “Removed K of N; tap to retry”; selection retains **only failed IDs** |
| Start unchanged (under cap) | Start still schedules without deleting others |
| Start at cap | Friendly failure (or recorded dogfood mode) that points to this screen — not silent success |
| Auth | Denied / not determined → inline banner + Settings path; no crash |
| Empty | “No AmakaFlow plans in Workout” when none scheduled |

## UX

### Entry

1. **Devices** → row **Scheduled in Workout** → `WorkoutScheduleView`
2. **Start success** (after `savedToFitness` / scheduled copy): small **Manage scheduled plans** control under the status line → same screen (sheet or push). Discoverability when duplicates hurt.

### Screen: `WorkoutScheduleView`

Duplicate rows are expected (same title, times minutes apart). Design for that:

- Sort **newest-first** by resolved schedule `Date` from `DateComponents`
- Subtitle: relative time via `RelativeDateTimeFormatter` (e.g. “scheduled 2h ago”); absolute time as secondary/accessibility
- `complete == true` rows: lower opacity / muted style, and/or a **Completed** section at the bottom
- Multi-select + Clear all remain the primary cleanup tools; labels make the list legible, not uniquely identifiable

**Toolbar / actions:**

- **Select** / **Done** toggles edit mode
- **Clear all** — visible whenever the list is non-empty (edit mode or not)
- **Delete (N)** — only when N ≥ 1 (never show disabled Delete (0))
- Non-edit: swipe-to-delete on a row
- Pull-to-refresh reloads `scheduledWorkouts`, then **clears selection and exits edit mode**

**Persistent footnote** (always under list when non-empty):

> Changes may take a moment to appear on Apple Watch.

**Auth:** non-modal inline banner above the list (same Settings → Health path as Start), not a blocking sheet.

**Confirm copy:**

- Delete N: “Remove N AmakaFlow workout plan(s) from Apple Watch Workout?”
- Clear all: “Remove all AmakaFlow plans from the Workout app? This can’t be undone — you can re-schedule any workout from its Start button.”

**After mutate:** await remove → refresh list → light inline success. On partial failure, keep failed IDs selected and stay in edit mode so Retry is one tap.

## Architecture

```
UI (WorkoutScheduleView + WorkoutScheduleViewModel)
    → WorkoutKitScheduleManaging (protocol)
         Live @available(iOS 18.0, *): WorkoutScheduler.shared
           - scheduledWorkouts (async) → [ScheduledWorkoutPlan]
           - remove(_ plan: WorkoutPlan, at: DateComponents)  // Apple API
           - removeAllWorkouts()
           - maxAllowedScheduledWorkoutCount (static)
         Tests: mock in-memory list
```

**Apple API (verify against SDK before Live adapter):**

| API | Signature / note |
| --- | --- |
| List | `var scheduledWorkouts: [ScheduledWorkoutPlan] { get async }` |
| Remove one | `func remove(_ workout: WorkoutPlan, at: DateComponents) async` — pass `scheduled.plan` + `scheduled.date` |
| Clear | `func removeAllWorkouts() async` |
| Cap | `static let maxAllowedScheduledWorkoutCount: Int` ([docs](https://developer.apple.com/documentation/workoutkit/workoutscheduler/maxallowedscheduledworkoutcount); WWDC23 also described ~15) |

Do **not** hardcode `15` in product copy; read `maxAllowedScheduledWorkoutCount` (or say “Apple’s schedule limit”). Soften risk language to “Apple caps scheduled plans.”

Optional later: extract list/remove into `workoutkit-sync` (save already lives there). V1 keeps the protocol boundary in the app; Live may call WorkoutKit directly (same pattern as `WorkoutKitSaving`).

**Identity for selection:** stable row id = `plan.id` + **canonical** serialization of `date` components (fixed field order: year, month, day, hour, minute, second, nanosecond — omit nils consistently). Selection set stores those ids.

**iOS gate:** screen, Live adapter, and actions available on iOS 18+ (match Start handoff). Older iOS: hide Devices entry / Manage link or show “Requires iOS 18”. Gate the Live adapter itself so the protocol stays honest.

## Data flow

1. `onAppear` / refresh → `await scheduler.scheduledWorkouts` → map to row models (sort + complete sectioning)  
2. **On every successful refresh:** `selectedIDs = []`, `isEditing = false` (unless mid-retry after partial failure — see below)  
3. Delete selected → for each selected row, `await scheduler.remove(row.plan, at: row.dateComponents)` using **fetched** date components only — never recompute “now”  
4. Clear all → `await scheduler.removeAllWorkouts()`  
5. Re-fetch list  

**Partial failure:** continue remaining removes; surface “Removed K of N; tap to retry”; set `selectedIDs` to **failed IDs only**; stay in edit mode. Retry re-runs delete on that selection.

**Async:** sequential `remove` in ViewModel `deleteSelected()` is fine under Apple’s cap; protocol stays single-plan so a future batch API is a one-line swap inside the ViewModel.

### Start at cap (in scope for V1 awareness)

Before or after schedule, when the scheduler is at `maxAllowedScheduledWorkoutCount`:

1. **Dogfood:** fill to cap, Start again, record failure mode (throw vs silent no-op vs success with no new card).
2. **Preferred product behavior if cryptic:** preflight `scheduledWorkouts.count >= maxAllowed…` in the save/handoff path → `AppleStartHandoffResult.failed` with copy that mentions Manage scheduled plans / Devices. Do **not** auto-delete to make room.
3. On list load, if `count >= maxAllowed…`, log a warning (dogfood signal).

## Explicit non-goals

- Auto-replace / remove-before-schedule on Start  
- Deleting from Watch UI  
- Editing schedule time from this screen  
- Garmin / AmakaFlowWatch workout lists  
- Composition export (AMA-2329)  
- Scheduling new plans from this screen (Start sheet remains the add path)  
- Moving list/remove into `workoutkit-sync` (deferred)

## Testing

**Unit (ViewModel + mock scheduler):**

- Load maps plans to rows; newest-first; completed after incomplete (or in Completed section)
- Multi-select delete calls `remove` once per selected id with **exact** stored `DateComponents`
- Clear all calls `removeAllWorkouts` once  
- Empty selection does not call remove  
- Refresh clears selection and exits edit mode  
- Mock failure mid-batch → error state; selection = failed IDs only; retry deletes those  
- Cap warning path when mock returns count at max  

**UI / dogfood:**

- Schedule 2–3 via Start → appear in list with relative times  
- Delete one → one remains on Watch “Today”  
- Multi-select two → both gone  
- Clear all → Watch AmakaFlow section empty / no leftover cards  
- **Watch lag:** delete on iPhone → open Watch immediately → card may still show → disappears within ~30s (accepted; footnote documents)  
- **At cap:** fill to `maxAllowedScheduledWorkoutCount`, Start again, record mode; confirm friendly copy / Manage link if failure is cryptic  

## Risks

| Risk | Mitigation |
| --- | --- |
| Watch list lag after remove | Pull-to-refresh; **persistent** footnote under list |
| `remove(_:at:)` date / plan mismatch | Always pass `scheduled.plan` + `scheduled.date` from list fetch; unit-test exact DateComponents round-trip |
| Wrong remove signature | Verify SDK: `remove(_ workout: WorkoutPlan, at: DateComponents)` before Live adapter |
| Auth not granted | Inline banner above list + Settings path (same as Start) |
| Apple schedule cap | Use `maxAllowedScheduledWorkoutCount`; Start at-cap dogfood + friendly handoff copy; log when at cap |
| Indistinguishable duplicates | Newest-first + relative times + de-emphasize completed; lean on multi-select / Clear all |

## Implementation checklist

- [ ] Verify `WorkoutScheduler.remove(_:at:)` signature against iOS 18 SDK  
- [ ] `WorkoutKitScheduleManaging` protocol + Live (iOS 18 gate) + Mock  
- [ ] ViewModel: load / select / deleteSelected / clearAll / refresh-clears-selection / retry-failed-IDs  
- [ ] `WorkoutScheduleView`: edit mode, swipe, Clear all, relative times, completed styling, sync footnote, auth banner  
- [ ] Wire Devices → Scheduled in Workout  
- [ ] Wire Start success → Manage scheduled plans  
- [ ] Start at-cap preflight or improved failure copy (after dogfood if needed)  
- [ ] Unit tests including selection-cleared-on-refresh, completed ordering, failed-ID retry, DateComponents passthrough  
- [ ] Update `docs/ama-2287-visual-evidence/README.md` — duplicates gap → managed via this screen; add at-cap + Watch-lag dogfood steps  
- [ ] Do **not** change Start to remove/replace before schedule  
