# Bug 4 — Watch-completed workout still doesn't reach History (build 29/30)

> **Filed:** 2026-05-06 (after TF build 29 verification attempt).
> **Reporter:** David, on-device.
> **Severity:** high — completion data loss; user gets no XP, no streak, no history record.
> **Status:** open. Bug 2 patch (PR #170) shipped but did not fully resolve.
> **Assigned:** Joshua.

---

## Symptom

1. Suggest Workout → Accept → Start workout.
2. The Watch handoff fires — "Open AmakaFlow on Apple Watch / Waiting for Watch..." sheet on iPhone, workout appears on the Watch.
3. User runs through the workout on the Watch (taps next-step until end). Watch plays the completion haptic + voice cue ("workout complete").
4. iPhone: open AmakaFlow → More → History → **empty**.
5. The Home Today card returns to its prior state (or to REST DAY).

Reproducible across TF builds 29 and 30. (Bug 3 — accepted workout vanishes — also overlaps here, but even when Bug 3 is sidestepped by completing immediately while the workout is still on Home, the History entry never lands.)

## What's been tried (didn't fix it)

### Attempt 1 — PR #170 (`fix(AMA-1751): Watch completions persist via transferUserInfo (Bug 2)`)

Changed the Watch's `StandaloneWorkoutEngine.swift` to send the completion `summary` payload via `session.transferUserInfo` instead of `session.sendMessage`. Reasoning: `sendMessage` requires `session.isReachable == true` (phone unlocked + foreground), which is almost never true when a workout finishes on the Watch with the phone in a pocket — so the completion summary was being silently dropped.

Also added a `didReceiveUserInfo` handler on the phone (`AmakaFlow/Services/WatchConnectivityManager.swift`) that mirrors the existing `didReceiveMessage` switch for `workoutSummary` / `logSet`.

Tested in TF build 29. **History is still empty after the Watch run.**

---

## Hypotheses (unverified)

1. **The Watch isn't actually emitting `workoutSummary` via `transferUserInfo`.** The path inside `StandaloneWorkoutEngine.swift` that calls `transferUserInfo` is gated by `WatchConnectivityBridge.shared.session` being non-nil. If the Bridge's session activation hasn't completed by the time the workout ends, the summary is dropped without a queue. Need to log every emit.
2. **`didReceiveUserInfo` on phone never fires.** Could be that the phone-side `WCSession` doesn't actually invoke the new delegate method. Could be:
    - The handler wasn't connected to the right WCSession instance.
    - WatchConnectivity batches userInfo deliveries until the iPhone wakes the companion app and the user actually opens it. If David tested without explicitly bringing AmakaFlow to foreground, delivery may still be pending.
    - There's a stricter delegate-protocol requirement we're missing (`@objc` on the new method?).
3. **Watch completion flow doesn't go through `StandaloneWorkoutEngine`.** Maybe the actual run path on Watch uses a different engine (e.g. WatchWorkoutManager + WorkoutKit) that has its own completion code which we didn't touch. Per `AmakaFlowCompanion/AmakaFlowWatch Watch App/StandaloneWorkoutEngine.swift:382-419` — only that file was patched. WatchWorkoutManager.swift was not.
4. **`WorkoutCompletionService.postWatchWorkoutCompletion` POST to `/workouts/completions` is failing on the backend** (404, 500, or auth issue) and the client silently swallows it. History reads via `apiService.fetchCompletions` so it depends on the POST having succeeded.

## Investigation plan

1. Print/log on Watch side: every call site that finishes a workout. Confirm `transferUserInfo` is firing with the right payload.
2. Print/log on phone side: when `didReceiveUserInfo` fires, what action was passed in.
3. Confirm by network: hit `/workouts/completions` POST manually and verify backend persists + GET returns it.
4. If the Watch is actually using a path other than `StandaloneWorkoutEngine`, find which one + patch it the same way.

## Where to start (next agent)

- Files: `AmakaFlowCompanion/AmakaFlowWatch Watch App/StandaloneWorkoutEngine.swift`, `AmakaFlowCompanion/AmakaFlowWatch Watch App/WatchWorkoutManager.swift`, `AmakaFlow/Services/WatchConnectivityManager.swift`, `AmakaFlow/Services/WorkoutCompletionService.swift`, `AmakaFlow/ViewModels/ActivityHistoryViewModel.swift`.
- Existing PR: #170 (26540ea on main) is the partial fix.

## Acceptance criteria

- Run a workout to completion on the Watch with the phone locked.
- Open AmakaFlow on iPhone within 30s → workout appears in More → History with the right name + duration + (if watch reported) HR/calories.
- Repeat with phone in airplane mode + run to completion + restore network → history entry eventually shows up.
