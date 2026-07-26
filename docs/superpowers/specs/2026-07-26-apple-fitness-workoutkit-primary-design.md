# Native Workout app via WorkoutKit-primary Start handoff

**Status:** DESIGN SPEC — approved; implementation plan at `docs/superpowers/plans/2026-07-26-apple-workoutkit-primary-handoff.md`.  
**Date:** 2026-07-26  
**Linear:** [AMA-2287](https://linear.app/amakaflow/issue/AMA-2287/dd-w3-apple-workout-watch-try-secondary-non-blocking)  
**Repo:** `amakaflow-ios-app` · branch `feature/ama-2287-dd-w3-apple-try`  
**Related:** existing AMA-2287 plumbing (`AppleStartHandoffService`, `WorkoutKitConverter`, `WorkoutKitSync`); Garmin path unchanged.

## Terminology (one destination)

Apple’s native app for scheduled WorkoutKit plans is **Workout** (on Apple Watch). User-facing copy uses that name only.

| Surface | Copy |
| ------- | ---- |
| Start sheet device label | **Workout on Apple Watch** |
| Success (paired or pairing unknown) | **Scheduled in Workout — open the Workout app on your Apple Watch for "{name}".** |
| Success (confirmed unpaired) | **Scheduled in Workout — pair an Apple Watch to run "{name}".** (Dogfood may append a short note that the phone has nowhere to open the plan yet; revisit production wording when graduating.) |
| iPhone as run surface | **Omit** on iOS 18–25. Only under `#available(iOS 26, *)` (or whatever ships iPhone Workout for custom plans) may copy mention the phone. |
| Code enum | `savedToFitness` may remain as an internal kind; it must not appear in user strings. |

Do **not** mix “Apple Fitness”, “Fitness app”, and “Workout” in status or Start-sheet labels.

## Problem

Daily Driver needs Apple Watch as a secondary try path: a Library workout should become a **native** session in Apple’s **Workout** app via WorkoutKit, not primarily AmakaFlowWatch.

AMA-2287 already wired Start → Apple with WatchConnectivity first and WorkoutKit only as fallback when the Watch is unreachable. That order does not match the product goal. Strength fidelity (load/target) is incomplete; that is acceptable for this slice if the workout **shows up and is runnable** in the Watch Workout app.

## Decisions (locked)

| Topic | Choice |
| ----- | ------ |
| Success surface | Apple **Workout** app on Watch via WorkoutKit |
| Fidelity bar | Library workouts as-produced; “shows up and runnable” over perfect structure |
| Routing | Always WorkoutKit — do not send via WatchConnectivity / AmakaFlowWatch |
| Approach | Flip handoff to WorkoutKit-primary; reuse on-device converter + `workoutkit-sync` |
| `watchReachable` | **Remove** from `handoff` signature, call site, and tests |
| Pairing for copy | Read-only; unpaired copy **only** on confirmed not-paired; unknown / session not activated → **paired-style** (optimistic) copy |
| Schedule time | Dogfood test dimension (now vs +5–10 min); change default before Done if “now” no-shows |
| Duplicate plans | Accepted gap this slice; named in gaps README + follow-up |

## Goal & scope

**Goal:** From Library → Start → **Workout on Apple Watch**, schedule the workout into WorkoutKit so it appears in the native **Workout** app on the Watch and can be started there.

### In scope

- Flip `AppleStartHandoffService` to always save via WorkoutKit (no WatchConnectivity send)
- Remove `watchReachable` from `handoff` and `beginAppleTryHandoff`
- Move **iOS 18 availability check to the front** of handoff (before convert/save); return `blocked` immediately on iOS &lt; 18
- Watch-leading success / confirmed-unpaired / auth copy
- Pending status UI while `ensureAuthorization` may present the system permission dialog
- Pairing read for copy only, with optimistic default when unknown
- Unit tests for WorkoutKit-only path + `WorkoutPlanError.authorizationDenied` mapping
- Gaps note update (`docs/ama-2287-visual-evidence/README.md`)
- Physical-device dogfood with schedule-time matrix (no Simulator claim of WorkoutKit success)

### Out of scope

- AmakaFlowWatch companion send / auto-start
- Mapper-api as conversion source of truth
- Load/target / perfect strength chrome in Apple’s player
- Auto-launch of the Workout app after save
- Deduping / removing previously scheduled plans
- iOS 26+ iPhone Workout copy variants
- Blocking Garmin work (AMA-2286 / CIQ)

## Architecture & data flow

```
Library workout (phone model)
        │
        ▼
Start sheet → Workout on Apple Watch
        │
        ▼
AppleStartHandoffService.handoff(workout:)
        │
        ├─ empty intervals? → failed
        ├─ iOS < 18? → blocked          // gate FIRST
        │
        ▼
UI status → pending ("Scheduling in Workout…")
        │
        ▼
WorkoutKitConverter → WKPlanDTO
        │
        ▼
WorkoutKitSync.save(dto, scheduleAt: nil → "now" by default)
  ensureAuthorization → may show system permission sheet
  WorkoutScheduler.schedule(plan, at: components)
        │
        ▼
Native Workout app on Apple Watch
  (AmakaFlowWatch is NOT this path)
```

### Key rules

- Do **not** call WatchConnectivity send APIs on this path.
- Conversion stays on-device (`WorkoutKitConverter` + `workoutkit-sync`).
- Default `scheduleAt: nil` → package `defaultScheduleDateComponents()` = **now** (minute granularity). That is a **hypothesis to validate on device**, not a guarantee that a past-minute plan surfaces on Watch.
- If trial A (“now”) systematically no-shows and trial B (+5–10 min) works, change the package or call-site default to a small future offset on this branch before calling the slice done. Do not blame a silent no-show on “Apple sync latency” without the B control.
- Auth denial → `WorkoutPlanError.authorizationDenied` → Settings → Health → AmakaFlow copy.
- Pairing: WCSession may be read for **copy only**. `isPaired` is only trustworthy when `activationState == .activated`. If the session is unsupported, not activated, or pairing is otherwise unknown → use **paired-style** success copy. Use unpaired copy only when activated and `isPaired == false`.

## Components, UX & errors

### Touch points (iOS only)

| Piece | Change |
| ----- | ------ |
| `AppleStartHandoffService.handoff` | `handoff(workout:)` only; WorkoutKit path only; iOS 18 gate first; pairing read for copy |
| `beginAppleTryHandoff` | Stop passing `appleWatchReachable`; set pending status then await handoff |
| `AppleStartHandoffCopy` | Paired / unknown vs confirmed-unpaired messages; no iPhone run destination pre–iOS 26 |
| Start sheet / `WorkoutStartSelection` | Label **Workout on Apple Watch**; do not gate enablement on WCSession reachability |
| Status UI | Pending from tap until handoff returns (covers auth dialog) |
| Gaps README | Schedule matrix, duplicates, unpaired/unknown pairing, where to look |
| Unit tests | Always WorkoutKit; auth mapping; no `watchReachable`; pairing-unknown → paired copy |

### Leave alone

`WatchConnectivityManager` send paths, AmakaFlowWatch app code, Garmin handoff, mapper-api converters.

### Outcomes

| Outcome | Kind (internal) | User sees |
| ------- | --------------- | --------- |
| Save OK, paired **or** pairing unknown | `savedToFitness` | Scheduled in Workout — open the Workout app on your Apple Watch for "{name}". |
| Save OK, confirmed unpaired | `savedToFitness` | Scheduled in Workout — pair an Apple Watch to run "{name}". |
| Empty workout | `failed` | Workout has no steps — add exercises… |
| Auth denied | `failed` | Workout permission denied — Settings → Health → Data Access → AmakaFlow, allow Workouts. |
| Conversion/save error | `failed` | Actionable conversion/save detail |
| iOS &lt; 18 | `blocked` | Requires iOS 18 to schedule in the Workout app — update iPhone and retry. |

### Auth & pending UX

On first save, `WorkoutPlanService.ensureAuthorization` may present the system permission dialog mid-handoff. The detail status line stays **pending** until success or failure returns. Unit test: saver throws `WorkoutPlanError.authorizationDenied` → Settings-copy failure message (primary path).

## Schedule time (dogfood dimension)

| Trial | `scheduleAt` | Record |
| ----- | ------------ | ------ |
| A | now (shipping default) | Appears in Watch Workout upcoming list? Latency? |
| B | now + 5–10 minutes | Same — **experiment only; must not ship enabled** |

Document both in the gaps README. If A no-shows and B works, promote a future offset to the **shipping** default (remove any debug-only override) before Done. Do not leave a +10-min debug flag on in production builds.

## Duplicate scheduled plans (accepted gap)

Every Start schedules another plan; there is no replace-by-workout-id. WorkoutKit also caps scheduled plans.

**This slice:** accept accumulation; name it in the gaps README.

**Follow-up:** track last scheduled plan per Library workout and remove/replace before re-scheduling.

## Testing & acceptance

### Automated

- `handoff(workout:)` always invokes WorkoutKit saver when iOS 18+ and intervals non-empty → Watch-leading message (never `sentToWatch`).
- Empty → failed; iOS &lt; 18 → blocked (availability seam if needed).
- Auth: `WorkoutPlanError.authorizationDenied` → Settings copy.
- Pairing unknown / not activated → paired-style copy; confirmed unpaired → unpaired copy.
- No `watchReachable` parameter or WCSession-first tests on this service.
- Leave `WatchWorkoutSendOutcomeTests` unchanged.

### Manual (physical device — required for Done)

**Where to look:** native **Workout** app on Apple Watch. AmakaFlowWatch may be installed; it is **not** this path.

1. iPhone iOS 18+ + paired Watch; grant permission when prompted (status pending through dialog).
2. Library → workout → Start → **Workout on Apple Watch**.
3. Status shows Watch-leading scheduled copy.
4. **Schedule matrix:** trial A with shipping default (now); trial B with temporary +5–10 min override (**must not ship enabled**). Record appearance and latency for each.
5. Open **Workout** on Watch → plan appears → start it.
6. Optional: confirmed unpaired → unpaired success copy; schedule still succeeds.
7. Note duplicate accumulation after multiple Starts (expected).
8. Screenshots under `docs/ama-2287-visual-evidence/`.

### Acceptance (AMA-2287)

- [ ] Start → Workout on Apple Watch always schedules via WorkoutKit; `watchReachable` removed.
- [ ] At least one Library workout startable in native Workout on Watch after A and/or B as needed — **or** gaps note states the exact blocker (including schedule-time findings).
- [ ] Gaps note covers: schedule matrix, duplicates + follow-up, pairing-unknown optimistic copy, “look in native Workout not AmakaFlowWatch.”
- [ ] Garmin path untouched.
- [ ] No debug +N-minute schedule override left enabled in shipping code.

## Implementation outline

1. iOS 18 gate **first** in `handoff` (today availability is effectively last after fallback failure; reordering changes blocked-path behavior).
2. Remove `watchReachable` from signature, call site, tests.
3. WorkoutKit-only save; pending status; Watch-leading / confirmed-unpaired copy; pairing-unknown → optimistic paired copy.
4. Unit tests: primary-path auth, always-schedule, pairing fallback.
5. Refresh gaps README.
6. Device dogfood (A/B); if needed, change shipping schedule default; evidence + Linear.

## Follow-ups (explicitly later)

- Mapper-api `/map/to-workoutkit` as phone source of truth
- Load/target mapping in `WorkoutKitConverter`
- Deep-link into Workout after save
- AmakaFlowWatch auto-start / dual delivery
- Replace/remove prior scheduled plan per Library workout (duplicate cleanup)
- iOS 26+ success copy mentioning iPhone Workout when that surface exists
- Production polish for unpaired copy (drop internal “iOS 26” wording if still present)
- Superseding AMA-1375 (Lumiere) — only if WorkoutKit dogfood fails on device
