# Apple WorkoutKit — sets/reps fidelity (dogfood follow-up)

**Date:** 2026-07-26  
**Parent:** AMA-2287 (WorkoutKit-primary handoff)  
**Status:** Approved for planning (revised after WWDC24 / WorkoutKit review)  
**Repos:** `amakaflow-ios-app`, `workoutkit-sync`

## Problem

Device dogfood showed AmakaFlowCompanion plans in the native Workout app with correct exercise **names**, but:

1. Every exercise subtitle is **Open** (one open-ended step).
2. **Sets are dropped** — a prescription like 3×8 becomes a single step.
3. Rep count (and load) never appear in the visible title.

Duplicates / findability are **out of scope** for this slice (next follow-up).

## Constraint (Apple)

`WorkoutGoal` supports only: `open`, `time`, `distance`, `energy`, and swim variants. There is **no reps goal** and no native “3 × 8” rendering as of watchOS 11 / WWDC24. Strength work steps will still show subtitle **Open**.

WWDC24 (“Build custom swimming workouts with WorkoutKit”) documents `WorkoutStep.displayName` (watchOS 11+) for exactly this use case: exercise types, weights, reps, RPE. Fidelity therefore comes from:

- `IntervalBlock.iterations` = set count  
- `displayName` carrying compact reps (and load when available)

The Watch **step detail** UI also shows the **upcoming** step’s `displayName` while the current step is active — that preview row truncates earlier than the main card. Design titles for glanceability there.

## Success criteria

| Check | Pass looks like |
| --- | --- |
| Sets | A 3-set exercise → one `IntervalBlock` with `iterations == 3` (work + optional recovery **per iteration**) |
| Reps in title | Preview shows e.g. `Pull-Ups · 8 reps` (not bare name + Open only) |
| Load | Non-empty load appears in compact form (e.g. `Pull-Ups · 25lb · 8 reps`) |
| Rest | `restSec` nil or ≤ 0 → **no** recovery `IntervalStep` (no empty/0s recovery card) |
| Non-reps | Time / distance / warmup / cooldown / existing `.repeat` unchanged |
| Goal | Reps steps remain `.open` |
| Location | Strength `CustomWorkout` keeps **omitted** location (user picks indoor/outdoor at start) — do not force `.indoor` |
| Validation | Malformed structure (`iterations < 1`, empty block steps) fails **before** `WorkoutScheduler.schedule` with a typed error |

## Approach (chosen)

**Split conversion:**

1. **`WorkoutKitConverter` (iOS)** — stop discarding `sets` on `.reps`. Emit `.repeatSet(reps: setCount, intervals: [step])` with `setCount = max(sets ?? 1, 1)` (never 0). Step keeps exercise base `name`, `reps`, `restSec`; load folded into `name` in **compact** form (see Load). Do not emit a recovery-bearing DTO when rest is nil/≤0 (leave `restSec` nil).
2. **`WorkoutPlanConverter` (`workoutkit-sync`)** — build work-step `displayName` when `step.reps` is non-nil:

   `"{baseName} · {reps} reps"`  

   If `name` is nil/empty → `"Exercise · {reps} reps"`. Keep existing `#available(iOS 18.0, watchOS 11.0, *)` gate on every `displayName` assignment (property does not exist meaningfully for older OS; package already targets iOS 18 / watchOS 11). Do not change `makeGoal` for reps (still `.open` when no seconds/meters). Recovery only if `restSec > 0` (already the package pattern — treat as a hard requirement; add a regression test).
3. **Structure validation** — before schedule, reject `repeatSet` with `reps < 1` or empty interval steps. Map to a typed package / conversion error.  
   **Note:** Current iOS 26 SDK `CustomWorkout` / `WorkoutPlan` inits are **non-throwing** (no `CustomWorkoutComposition` / `WorkoutCompositionError` in the shipped interface). Do **not** invent a throwing composition API; validate in our converters. Revisit if Apple reintroduces composition validators.
4. **Pin bump** — tag `workoutkit-sync` release (semver tag, e.g. `1.x.y`, not bare SHA), bump SPM pin in `amakaflow-ios-app`, land converter + tests.

## Load & title length

| Source | Behavior this slice |
| --- | --- |
| `load: String?` | If non-empty, iOS compact-folds into DTO `name`: strip spaces in the load token (`"25 lb"` → `"25lb"`), then `"\(name) · \(compactLoad)"` |
| `convertLoad` | Unchanged stub (`nil`) — no unit parser |
| Package | Appends ` · {reps} reps` only; does not re-parse load |

**Length targets (dogfood):**

- Prefer **≤ ~30 characters** total `displayName` when practical (upcoming-step preview truncates sooner, ~24 visible).
- Prefer short exercise names in fixtures used for Watch truncation checks.
- Never put set count in the title (sets = `iterations` only).

Example: `reps(sets: 3, reps: 8, name: "Pull-Ups", load: "25 lb", restSec: 90)`:

1. iOS name → `"Pull-Ups · 25lb"`  
2. iOS → `.repeatSet(reps: 3, intervals: [step(reps: 8, restSec: 90)])`  
3. Package `displayName` → `"Pull-Ups · 25lb · 8 reps"`  
4. Block `iterations` → `3`; each iteration: work (open) + recovery 90s  

If `restSec` nil: block steps = `[work]` only.

## Data flow

```
Workout (.reps sets/reps/name/load/rest)
    → WorkoutKitConverter → WKPlanDTO (.repeatSet + Step)
    → WorkoutKitSync.WorkoutPlanConverter → CustomWorkout IntervalBlock
         (validate iterations ≥ 1; displayName behind watchOS 11 gate)
    → WorkoutScheduler.schedule (existing AMA-2287 handoff)
```

## Explicit non-goals

- Native “3 sets × 10 reps” Apple UI (API cannot do it as of watchOS 11)
- Timed stand-in goals for strength reps
- `removeAllWorkouts` / replace-before-schedule (duplicate cleanup)
- Findability copy / schedule-time experiments
- Full load unit parsing into `WKPlanDTO.Interval.Load`
- **`WorkoutComposition` binary export / AirDrop `.workout` sharing** — useful coach→athlete vector; separate follow-up
- HR / pace / power alerts on strength or Hyrox hybrid blocks — note for later training paths only

## Testing

**`workoutkit-sync`**

- Step with `reps` + name → `displayName` contains `· {n} reps`
- Step without `reps` → existing name-only / time-goal behavior
- `restSec` nil or 0 → no recovery step in the block
- `repeatSet(reps: 0, …)` or empty steps → throws before schedule
- Strength conversion does not set an explicit indoor/outdoor location

**`amakaflow-ios-app`**

- `.reps(sets: 3, reps: 8, …)` → DTO `.repeatSet` with `reps == 3`, step `reps == 8`
- `sets: nil` → iterations `1`
- Load `"25 lb"` → name contains `25lb`
- Existing sport-type / smoke tests still pass

**Device / Simulator dogfood**

- Start a known 3×N strength workout → titles include reps; block repeats
- Truncation check: a **≥35 character** `displayName` in the **upcoming step** preview row (document what truncates; shorten format if unreadable)

## Rollout order

1. PR + merge `workoutkit-sync` (displayName + rest/validation + tests); **git tag** release  
2. PR `amakaflow-ios-app`: bump SPM to that **tag**, converter + tests  
3. Device verify against success criteria  

## Risks

| Risk | Mitigation |
| --- | --- |
| Long titles truncate (upcoming preview ~24 chars, main card ~35–40) | Compact load (`25lb`); prefer short names; dogfood a 35+ char title on Watch |
| `displayName` pre–watchOS 11 | Keep `#available(iOS 18.0, watchOS 11.0, *)` on every assignment (already in package) |
| Inventing removed Composition APIs | Validate in our code; don’t call non-existent throwing composition types |
| Package pin lag | Tag first; app PR must include pin bump with converter |
| 0-iteration / empty blocks | Reject in converter; never call `schedule` with them |

## Implementation checklist (delta)

- [ ] Package: format `displayName` with reps; keep availability guard  
- [ ] Package: no recovery step when `restSec` nil/≤0 (regression test)  
- [ ] Package: validate `iterations >= 1` / non-empty steps; typed throw before schedule  
- [ ] Package: leave strength location unspecified (current `CustomWorkout(activity:)` — confirm no regression)  
- [ ] iOS: emit `repeatSet` from `.reps` sets; compact-fold load into name  
- [ ] iOS: bump SPM to **semver tag**  
- [ ] Tests as above + Watch truncation note in dogfood / gaps README  
