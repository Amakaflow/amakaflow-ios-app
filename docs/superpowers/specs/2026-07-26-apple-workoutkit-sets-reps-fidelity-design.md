# Apple WorkoutKit — sets/reps fidelity (dogfood follow-up)

**Date:** 2026-07-26  
**Parent:** AMA-2287 (WorkoutKit-primary handoff)  
**Status:** Locked for implementation  
**Repos:** `amakaflow-ios-app`, `workoutkit-sync`  
**Related:** [AMA-2329](https://linear.app/amakaflow/issue/AMA-2329) — WorkoutComposition export / AirDrop (non-goal here)

## Problem

Device dogfood showed AmakaFlowCompanion plans in the native Workout app with correct exercise **names**, but:

1. Every exercise subtitle is **Open** (one open-ended step).
2. **Sets are dropped** — a prescription like 3×8 becomes a single step.
3. Rep count (and load) never appear in the visible title.

Duplicates / findability are **out of scope** for this slice (next follow-up).

## Constraint (Apple)

`WorkoutGoal` supports only: `open`, `time`, `distance`, `energy`, and swim variants. There is **no reps goal** and no native “3 × 8” rendering as of watchOS 11 / WWDC24. Strength work steps will still show subtitle **Open**.

WWDC24 documents `WorkoutStep.displayName` (watchOS 11+) for exercise types, weights, reps, RPE. Fidelity comes from:

- `IntervalBlock.iterations` = set count  
- `displayName` carrying compact reps (and load when available)

The Watch **step detail** UI also shows the **upcoming** step’s `displayName` while the current step is active — that preview row truncates earlier than the main card.

## Success criteria

| Check | Pass looks like |
| --- | --- |
| Sets | A 3-set exercise → one `IntervalBlock` with `iterations == 3` (work + optional recovery **per iteration**) |
| Reps in title | Preview shows e.g. `Pull-Ups · 8 reps` |
| Load | Numeric+unit loads compact (`25 lb` → `25lb`); phrase loads like `body weight` stay unmangled |
| Rest | `restSec` nil or ≤ 0 → **no** recovery `IntervalStep` |
| Non-reps | Time / distance / warmup / cooldown / existing `.repeat` unchanged |
| Goal | Reps steps remain `.open` |
| Location | Strength `CustomWorkout(activity:)` — do not force indoor/outdoor |
| Validation | Malformed structure fails **before** `schedule` with `WorkoutPlanConversionError` |

## Approach (chosen)

**Split conversion:**

1. **`WorkoutKitConverter` (iOS)** — emit `.repeatSet(reps: setCount, intervals: [step])` with `setCount = max(sets ?? 1, 1)`. When `sets == 0` (or `< 1`), log a **warning** then clamp. Compact-fold load into `name` (see Load). Leave `restSec` nil when rest is nil/≤0.
2. **`WorkoutPlanConverter` (`workoutkit-sync`)** — build `displayName` when `step.reps != nil`: `"{baseName} · {reps} reps"` (fallback base `"Exercise"`). Gate **at the assignment site** inside `makeWorkoutStep` via `#available(iOS 18.0, watchOS 11.0, *)` (already the helper — keep it; do not set `displayName` on any other code path without the same gate). Recovery only if `restSec > 0`.
3. **Typed validation** — before building / scheduling, throw:

```swift
public enum WorkoutPlanConversionError: Error, LocalizedError, Sendable {
    case zeroIterations(exerciseName: String?)
    case emptyBlockSteps(exerciseName: String?)
}
```

   Do **not** invent removed `CustomWorkoutComposition` / `WorkoutCompositionError` APIs.
4. **Pin bump** — tag `workoutkit-sync` semver (e.g. `1.4.0`), bump SPM in app to that **tag**.

## Load compacting

| Input | Output in DTO `name` prefix |
| --- | --- |
| Matches `#^\d+\s+[A-Za-z%]+$#` (e.g. `25 lb`, `135 lbs`) | Strip spaces → `25lb`, then `"\(exercise) · \(compact)"` |
| Already compact (`25lb`) | Unchanged token |
| Phrase / other (`body weight`, `RPE 7`) | **Do not** strip spaces — `"\(exercise) · \(load)"` as-is |

Package then appends ` · {reps} reps` when `step.reps != nil`.

## Dogfood truncation fixtures

Commit this table into `docs/ama-2287-visual-evidence/README.md` **before** device verify. Run on **Series 9 45mm** Simulator (truncation floor).

| Fixture `displayName` | Chars | Expected |
| --- | ---: | --- |
| `Pull-Ups · 25lb · 8 reps` | 26 | Fits upcoming preview + main card |
| `Weighted Pull-Ups · 25lb · 8 reps` | 34 | Main card OK; note if upcoming preview truncates |
| `Romanian Deadlift · 135lb · 10 reps` | 36 | Document exact truncation on upcoming preview |

## Data flow

```
Workout (.reps)
  → WorkoutKitConverter (clamp sets; compact load; repeatSet)
  → WKPlanDTO
  → WorkoutPlanConverter (displayName @ assignment gate; validate; IntervalBlock)
  → WorkoutScheduler.schedule
```

## Explicit non-goals

- Native “3 × 10” Apple UI  
- Timed stand-in goals for strength reps  
- Duplicate cleanup / replace-before-schedule  
- Findability copy / schedule-time experiments  
- Full `Load` value/unit parser  
- **Composition binary export / AirDrop** → [AMA-2329](https://linear.app/amakaflow/issue/AMA-2329)  
- HR/pace/power alerts on strength / Hyrox hybrids  

## Testing

**Package:** reps → displayName; no reps unchanged; rest nil/0 → no recovery; zero iterations / empty steps → `WorkoutPlanConversionError`; strength location not forced indoor.

**App:** sets 3 → repeatSet 3; sets nil → 1; sets 0 → 1 (warning logged); load `25 lb` → `25lb` in name; `body weight` unmangled; existing smokes pass.

**Note:** Asserting `WorkoutStep.displayName` requires a **watchOS 11+ / iOS 18+** sim or device (package platforms already require that). Comment in `WorkoutPlanConverterTests` that displayName assertions need watchOS 11+ runtime.

## Rollout

1. `workoutkit-sync` PR → merge → **git tag**  
2. App PR: pin to tag + converter + gaps README fixtures + tests  
3. Device/sim dogfood with truncation table  

## Implementation checklist

- [ ] Compact load: numeric+unit strip only; leave phrase loads alone  
- [ ] Warn + clamp when `sets < 1`  
- [ ] Add `WorkoutPlanConversionError` in package before parallel PRs diverge  
- [ ] Truncation fixture table in gaps README before device verify  
- [ ] `#available` only at `makeWorkoutStep` assignment site; test comment for watchOS 11+  
- [ ] Comment in package near scheduler: `// Follow-up AMA-2329: WorkoutComposition export`  
