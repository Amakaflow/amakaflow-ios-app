# AMA-2287 — WorkoutKit-primary gaps & device dogfood

Secondary spike for Daily Driver Week 3. **Garmin path (AMA-2286) is unchanged.**

Design spec: [`docs/superpowers/specs/2026-07-26-apple-fitness-workoutkit-primary-design.md`](../superpowers/specs/2026-07-26-apple-fitness-workoutkit-primary-design.md)

## Where to look

The success surface is Apple’s native **Workout** app on **Apple Watch** (scheduled WorkoutKit plans appear in the upcoming list there).

**AmakaFlowWatch is not this path.** Do not use the AmakaFlowWatch workout list to validate AMA-2287. WatchConnectivity send to the companion app is out of scope for Start → Workout on Apple Watch.

## Primary path

```
Library → Start → Workout on Apple Watch
        → AppleStartHandoffService.handoff(workout:)
        → WorkoutKitConverter → WKPlanDTO
        → WorkoutKitSync.save(dto, scheduleAt: nil → "now")
        → native Workout app on Apple Watch
```

- **Always WorkoutKit** — no WCSession-first routing, no `watchReachable` gate.
- iOS 18+ required; blocked immediately on older iOS.
- Status stays **pending** (`Scheduling in Workout…`) through conversion, authorization, and save.
- Success copy is Watch-leading: *Scheduled in Workout — open the Workout app on your Apple Watch for "{name}".*

Code touch points: `AppleStartHandoffService`, `WorkoutKitConverter`, `WorkoutKitSync` (existing package). Leave `WatchConnectivityManager` send paths and AmakaFlowWatch unchanged.

## Schedule matrix (dogfood)

Default shipping behavior schedules at **now** (`scheduleAt: nil` → package minute-granularity “now”). That is a **hypothesis to validate on device**, not a guarantee the plan surfaces immediately on Watch.

| Trial | `scheduleAt` | Purpose |
| ----- | ------------ | ------- |
| **A** | now (shipping default) | Does the plan appear in Watch Workout upcoming? How long until visible? |
| **B** | now + 5–10 minutes | Control: if A no-shows and B works, promote a small future offset to the **shipping** default before Done |

**Trial B must not ship enabled.** Use one of:

1. **Preferred (when wired):** Xcode Debug scheme environment variable `AMA2287_SCHEDULE_OFFSET_MINUTES=10` (positive integer minutes). Release builds ignore this var; clear it before TestFlight or Release archives.
2. **Local-only fallback:** temporary DEBUG-only change at the `WorkoutKitSync.save` call site in `WorkoutKitConverter.saveToWorkoutKit` — pass explicit future `scheduleAt` date components, revert before merge. Do not commit a permanent default offset.

Record for each trial: appeared (Y/N), latency (rough), runnable (Y/N). If A fails and B succeeds, change the production `scheduleAt` default (not DEBUG-only) before calling the slice done.

## Duplicate scheduled plans (accepted gap)

Every Start schedules **another** WorkoutKit plan. There is no replace-by-workout-id; WorkoutKit also caps total scheduled plans. Multiple Starts on the same Library workout **accumulate** plans — expected this slice.

**Follow-up:** track last scheduled plan per Library workout and remove/replace before re-scheduling.

## Pairing copy

Pairing is read-only for success messaging (`AppleWatchPairingRead` via WCSession):

| Session state | Copy |
| ------------- | ---- |
| Paired, or pairing **unknown** / session **not activated** | Optimistic paired-style: open Workout on Watch |
| **Confirmed unpaired** (`activationState == .activated` and `isPaired == false`) | Unpaired: pair a Watch to run "{name}" |

Schedule still succeeds when unpaired; the phone has nowhere to open the plan yet.

## Auth

First save may present the system **WorkoutScheduler** permission sheet (`ensureAuthorization`). UI remains **pending** through the dialog. Denial maps to `WorkoutPlanError.authorizationDenied` → *Settings → Health → Data Access → AmakaFlow, allow Workouts.*

WorkoutKit + HealthKit authorization do not run in Simulator; dogfood requires a physical iPhone (iOS 18+) and paired Watch (watchOS 11+).

## Strength fidelity (known gap)

`WorkoutKitConverter` maps sport types and interval shapes but **load/target parsing is still weak** (TODO in converter). Rep-based gym workouts may appear as generic steps in Apple’s player. Acceptable for this slice if the workout **shows up and is runnable** in native Workout.

## Sets/reps fidelity follow-up (dogfood)

Spec: [`docs/superpowers/specs/2026-07-26-apple-workoutkit-sets-reps-fidelity-design.md`](../superpowers/specs/2026-07-26-apple-workoutkit-sets-reps-fidelity-design.md)

**Simulator floor:** Apple Watch Series 9 (45mm).

| Fixture `displayName` | Chars | Record result |
| --- | ---: | --- |
| `Pull-Ups · 25lb · 8 reps` | 26 | Fits preview + main? |
| `Weighted Pull-Ups · 25lb · 8 reps` | 34 | Preview truncates? Main OK? |
| `Romanian Deadlift · 135lb · 10 reps` | 36 | Exact truncation point |

Also verify: 3-set exercise → IntervalBlock repeats (not one Open step only).

**Device Trial A/B (founder — still open):** simulator/unit tests do not close AMA-2287 Apple surface. Record on a physical iPhone + paired Watch: appearance, latency, runnability in native Workout for Trial A (schedule now) and Trial B (+5–10 min DEBUG only). Keep Garmin unblocked.

## Device evidence checklist

Physical device required. Attach screenshots under this folder after manual runs.

1. iPhone iOS 18+ and paired Watch; grant Workout permission when prompted (status pending through dialog).
2. Library → workout → Start → **Workout on Apple Watch**.
3. Status shows Watch-leading scheduled copy (not “Sent to Apple Watch”).
4. **Schedule matrix:** run trial A (shipping default, now); run trial B with +5–10 min override (**DEBUG only — must not ship enabled**). Record appearance and latency for each.
5. Open native **Workout** on Watch → plan appears in upcoming → start it.
6. Optional: confirmed unpaired device → unpaired success copy; schedule still succeeds.
7. Note duplicate accumulation after multiple Starts (expected).
8. Save screenshots here: Start sheet status line + Watch Workout upcoming list (or blocker note if plan never appears).

Unit evidence (CI): `AppleStartHandoffTests`, `WorkoutKitConverterTests`, `WatchWorkoutSendOutcomeTests` (unchanged WCSession tests).

## Garmin unaffected

No edits to `GarminStartHandoffService`, CIQ push APIs, or Garmin Start sheet defaulting.
