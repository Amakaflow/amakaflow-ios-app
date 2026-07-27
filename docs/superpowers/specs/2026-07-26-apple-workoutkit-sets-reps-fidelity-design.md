# Apple WorkoutKit — sets/reps fidelity (dogfood follow-up)

**Date:** 2026-07-26  
**Parent:** AMA-2287 (WorkoutKit-primary handoff)  
**Status:** Approved for planning  
**Repos:** `amakaflow-ios-app`, `workoutkit-sync`

## Problem

Device dogfood showed AmakaFlowCompanion plans in the native Workout app with correct exercise **names**, but:

1. Every exercise subtitle is **Open** (one open-ended step).
2. **Sets are dropped** — a prescription like 3×8 becomes a single step.
3. Rep count (and load) never appear in the visible title.

Duplicates / findability are **out of scope** for this slice (tracked as the next follow-up).

## Constraint (Apple)

`WorkoutGoal` supports only: `open`, `time`, `distance`, `energy`, and swim variants. There is **no reps goal**. Strength work steps will still show subtitle **Open**; fidelity comes from:

- `IntervalBlock.iterations` = set count  
- `displayName` carrying reps (and load when available)

## Success criteria

| Check | Pass looks like |
| --- | --- |
| Sets | A 3-set exercise becomes one IntervalBlock with `iterations == 3` (work + optional recovery per iteration) |
| Reps in title | Watch/phone preview shows e.g. `Weighted Pull-Ups · 8 reps` (not bare exercise name + Open only) |
| Load | When AmakaFlow has a non-empty load string, it appears in the title (e.g. `… · 25 lb`) |
| Non-reps intervals | Time / distance / warmup / cooldown / existing `.repeat` behavior unchanged |
| Goal | Reps steps remain `.open` (no fake timed goals) |

## Approach (chosen)

**Split conversion:**

1. **`WorkoutKitConverter` (iOS)** — stop discarding `sets` on `.reps`. Emit `.repeatSet(reps: setCount, intervals: [step])` with `setCount = max(sets ?? 1, 1)`. Step keeps raw exercise `name`, `reps`, `restSec`; load string is folded into `name` when present (see Load below) because `convertLoad` is currently a stub that always returns `nil`.
2. **`WorkoutPlanConverter` (`workoutkit-sync`)** — when building work-step `displayName`, if `step.reps` is non-nil, format:

   `"{name} · {reps} reps"`  

   If `name` is nil/empty, use `"Exercise · {reps} reps"`. Do not change `makeGoal` for reps (still `.open` when no seconds/meters).

3. **Pin bump** — ship package change first (tag/commit), then bump SPM pin in `amakaflow-ios-app` and land converter + tests.

## Load

| Source | Behavior this slice |
| --- | --- |
| `WorkoutInterval.reps` `load: String?` | If non-empty, iOS sets DTO `name` to `"\(name) · \(load)"` before package appends reps |
| `convertLoad` | Unchanged stub (`nil`) — no parser work in this slice |
| Package `Load` on step | Unused for display this slice; reserved for a later parser |

Example pipeline for `reps(sets: 3, reps: 8, name: "Pull-Ups", load: "25 lb", restSec: 90)`:

1. iOS name → `"Pull-Ups · 25 lb"`  
2. iOS interval → `.repeatSet(reps: 3, intervals: [step(reps: 8, name: …, restSec: 90)])`  
3. Package displayName → `"Pull-Ups · 25 lb · 8 reps"`  
4. Block iterations → `3`; each iteration work (open) + recovery 90s

## Data flow

```
Workout (.reps sets/reps/name/load/rest)
    → WorkoutKitConverter → WKPlanDTO (.repeatSet + Step)
    → WorkoutKitSync.WorkoutPlanConverter → CustomWorkout IntervalBlock
    → WorkoutScheduler.schedule (existing AMA-2287 handoff)
```

## Explicit non-goals

- Native “3 sets × 10 reps” Apple UI (API cannot do it)
- Timed stand-in goals for strength reps
- `removeAllWorkouts` / replace-before-schedule (duplicate cleanup)
- Findability copy / scheduling time experiments
- Full load unit parsing into `WKPlanDTO.Interval.Load`

## Testing

**`workoutkit-sync`**

- Unit: `makeIntervalSteps` / converter path — step with `reps` and name produces displayName containing `· {n} reps`
- Unit: step without `reps` keeps existing name-only / time-goal behavior

**`amakaflow-ios-app`**

- `WorkoutKitConverterTests`: `.reps(sets: 3, reps: 8, …)` → DTO `.repeatSet` with `reps == 3` and step `reps == 8`
- `sets: nil` → `repeatSet` iterations `1`
- Load non-nil → step `name` includes load substring
- Existing sport-type / smoke tests still pass

**Device dogfood (human)**

- Start a known 3×N strength workout → Workout app shows titles with reps; structure repeats (not one Open card per exercise only once)

## Rollout order

1. PR + merge `workoutkit-sync` displayName formatting  
2. PR `amakaflow-ios-app`: bump package pin + converter + tests  
3. Device verify against dogfood screenshots criteria above  

## Risks

| Risk | Mitigation |
| --- | --- |
| Long titles truncate on Watch | Keep format short: name · load · reps; no sets count in title (sets = iterations) |
| Double-encoding if name already contains “reps” | Only append when `step.reps != nil`; iOS only appends load once |
| Package pin lag | App PR must not land converter-only without pin bump if package formatting is required for pass criteria |
