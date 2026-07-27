# Apple WorkoutKit — scheduled plans cleanup (multi-select)

**Date:** 2026-07-27  
**Parent:** AMA-2287  
**Linear:** AMA-2330 (filed with this spec)  
**Status:** Approved for planning  
**Repos:** `amakaflow-ios-app` (optionally thin wrappers in `workoutkit-sync`)

## Problem

Dogfood of WorkoutKit-primary Start works (including sets/reps fidelity), but every Start **adds** another plan. The Watch Workout UI does not give a reliable way to delete AmakaFlowCompanion-managed cards, so duplicates pile up under “Today” and bury the current workout.

Users also need **more than one** planned workout at a time (e.g. morning + evening). Auto-`removeAllWorkouts()` on every Start would break that.

## Decisions (locked)

| Decision | Choice |
| --- | --- |
| Start behavior | **Keep adding** — no automatic remove/replace |
| Cleanup | **User-initiated only** |
| V1 delete modes | **Multi-select**, **single**, and **Clear all** |
| Surface | **iPhone** AmakaFlowCompanion — not Watch |
| Scope of scheduler APIs | Only plans owned by this app (`WorkoutScheduler` is per-app) |

## Success criteria

| Check | Pass looks like |
| --- | --- |
| List | Shows AmakaFlow-scheduled plans with title + date/time (and complete if set) |
| Multi-select | Select N → Delete → confirm → those N gone after refresh |
| Single | Swipe delete or select-one + Delete removes one plan |
| Clear all | Confirm → `removeAllWorkouts()` → list empty |
| Start unchanged | Start → Workout on Apple Watch still schedules without deleting others |
| Auth | Denied / not determined → clear copy + path to Settings; no crash |
| Empty | “No AmakaFlow plans in Workout” when none scheduled |

## UX

**Entry:** Devices (or Apple Workout subsection) → **Scheduled in Workout**

**Screen:** `ScheduledWorkoutPlansView` (name flexible)

- Toolbar: **Select** / **Done**, **Clear all** (always available when list non-empty or while editing)
- Edit mode: checkmarks per row; trailing **Delete (N)** enabled when N ≥ 1
- Non-edit: swipe-to-delete on a row
- Pull-to-refresh reloads `scheduledWorkouts`

**Confirm copy:**

- Delete N: “Remove N workout(s) from the Workout app on Apple Watch?”
- Clear all: “Remove all AmakaFlowCompanion plans from the Workout app? This cannot be undone from the Watch.”

**After mutate:** await remove → refresh list → toast or inline success (light).

## Architecture

```
UI (ScheduledWorkoutPlansView + ViewModel)
    → WorkoutKitScheduleManaging (protocol)
         Live: WorkoutScheduler.shared
           - scheduledWorkouts (async)
           - remove(plan, at: dateComponents)
           - removeAllWorkouts()
         Tests: mock in-memory list
```

Optional: add list/remove helpers to `workoutkit-sync` so iOS stays thin; V1 may call WorkoutKit directly from the Live adapter behind the protocol (same pattern as `WorkoutKitSaving`).

**Identity for selection:** stable row id = `plan.id` + serialized `date` components (ScheduledWorkoutPlan equality). Selection set stores those ids.

**iOS gate:** screen / actions available on iOS 18+ (match Start handoff). Older iOS: hide entry or show “Requires iOS 18”.

## Data flow

1. `onAppear` / refresh → `await scheduler.scheduledWorkouts` → map to row models  
2. Delete selected → for each `ScheduledWorkoutPlan`: `await scheduler.remove(plan, at: date)`  
3. Clear all → `await scheduler.removeAllWorkouts()`  
4. Re-fetch list  

Partial failure: continue remaining removes; surface “Removed K of N; tap to retry” + refresh.

## Explicit non-goals

- Auto-replace / remove-before-schedule on Start  
- Deleting from Watch UI  
- Editing schedule time from this screen  
- Garmin / AmakaFlowWatch workout lists  
- Composition export (AMA-2329)  
- Scheduling new plans from this screen (Start sheet remains the add path)

## Testing

**Unit (ViewModel + mock scheduler):**

- Load maps plans to rows  
- Multi-select delete calls `remove` once per selected id  
- Clear all calls `removeAllWorkouts` once  
- Empty selection does not call remove  
- Mock failure mid-batch → error state + partial refresh  

**UI / dogfood:**

- Schedule 2–3 via Start → appear in list  
- Delete one → one remains on Watch “Today”  
- Multi-select two → both gone  
- Clear all → Watch AmakaFlow section empty / no leftover cards  

## Risks

| Risk | Mitigation |
| --- | --- |
| Watch list lag after remove | Pull-to-refresh; copy “may take a moment to sync to Watch” |
| `remove(plan, at:)` date mismatch | Always use `ScheduledWorkoutPlan.date` from the list fetch, never recompute “now” |
| Auth not granted | Same pattern as Start: request or direct to Settings |
| Large lists (≤15 Apple cap) | Fine for V1; no pagination |

## Implementation checklist

- [ ] `WorkoutKitScheduleManaging` protocol + Live + Mock  
- [ ] ViewModel: load / select / deleteSelected / clearAll  
- [ ] SwiftUI list with edit mode + swipe + Clear all confirms  
- [ ] Wire navigation from Devices / Apple  
- [ ] Unit tests with mock  
- [ ] Update `docs/ama-2287-visual-evidence/README.md` — duplicates gap → managed via this screen  
- [ ] Do **not** change `AppleStartHandoffService` schedule path  
