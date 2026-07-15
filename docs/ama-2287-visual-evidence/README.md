# AMA-2287 — Apple Workout / Watch try (visual evidence + gaps)

Secondary spike for Daily Driver Week 3. Garmin path (AMA-2286) unchanged.

## What we tested

| Path | Trigger | Expected surface |
|------|---------|------------------|
| Watch reachable | Library → Start → Apple (Watch paired + reachable) | `sendWorkoutWithOutcome` → AmakaFlowWatch receives workout |
| Watch unreachable | Same, Watch asleep / out of range | `WorkoutKitSync.save` → Apple Fitness / Workout app |
| Blocked | iOS &lt; 18, Watch unreachable | Honest blocked status (no stub strings) |

## Code touched (reuse, not rebuild)

- `UnifiedWorkoutDetailView.beginAppleTryHandoff` → `AppleStartHandoffService`
- `WatchConnectivityManager.sendWorkoutWithOutcome` (honest reply handling)
- `WorkoutKitConverter` + `WorkoutKitSync` (existing package)

## Gaps note (acceptance: documented block)

### What works (unit + architecture)

- Library → Start sheet → Apple device routes to `AppleStartHandoffService`.
- Watch reachable: WCSession `receiveWorkout` with reply `status=received` → user sees **Sent to Apple Watch**.
- Watch unreachable / send failure: automatic **WorkoutKit fallback** on iOS 18+ → **Saved to Apple Fitness**.
- Status strings are actionable (pairing, permissions, empty workout) — no "stub" or issue-id suffixes.
- `WorkoutKitConverter` maps sport types + interval shapes; golden tests already cover conversion smoke.

### What does **not** work yet (dogfood blockers)

1. **No auto-start in native Workout app** — push adds workout to AmakaFlowWatch list (`WatchWorkoutManager.addWorkout`) but does not launch Apple’s Workout/Fitness session. User must open AmakaFlowWatch or Fitness app manually.
2. **Physical device required** — WorkoutKit + HealthKit authorization do not run in Simulator; dogfood needs paired iPhone (iOS 18+) + Watch (watchOS 11+).
3. **WorkoutScheduler authorization** — first save triggers system permission; denial surfaces as recoverable copy but blocks save until user grants in Settings → Health.
4. **Strength fidelity** — `WorkoutKitConverter` drops load/target parsing (TODO in converter); rep-based gym workouts may appear as generic steps in Fitness.
5. **Unreachable Watch without iOS 18** — blocked with explicit message; no Lumiere/OpenClaw fallback in this spike.
6. **Sync latency** — WorkoutKit schedule time is “now”; appearance in Watch Workout app depends on Apple sync (not observable from app code).

### Missing API / capability (vs Garmin W2 bar)

| Capability | Garmin (AMA-2286) | Apple try (AMA-2287) |
|------------|-------------------|----------------------|
| One-tap delivery status | CIQ queue + delivery state poll | WCSession reply only; no server-side delivery ledger |
| Native player start | CIQ widget download → native player | Manual open AmakaFlowWatch or Fitness |
| Offline queue | Backend `watch_delivery` | `transferUserInfo` exists but not wired for Start handoff |
| Structured strength on device | FIT export | WorkoutKit custom plan; load/target not mapped |

### Recommendation

- **Do not block Garmin W2** on Apple — keep Apple as opt-in “Try” on Start sheet.
- **Next increment (if pursued):** wire `WatchWorkoutManager.startWorkout` after receive + deep link to Fitness scheduled plan; or supersede AMA-1375 Lumiere only if WorkoutKit path fails dogfood on device.
- **Supersede AMA-1375?** Not yet — this spike proves plumbing + honest UX; Lumiere remains optional if WorkoutKit dogfood fails on strength workouts.

## Device evidence

_Dogfood on physical iPhone + Watch required. Attach screenshots here after manual run:_

1. Start sheet → Apple → status line under detail actions
2. AmakaFlowWatch workout list OR Fitness app scheduled workout

Unit evidence: `AppleStartHandoffTests`, `WatchWorkoutSendOutcomeTests` (CI).

## Garmin unaffected

No edits to `GarminStartHandoffService`, CIQ push APIs, or Garmin Start sheet defaulting.
