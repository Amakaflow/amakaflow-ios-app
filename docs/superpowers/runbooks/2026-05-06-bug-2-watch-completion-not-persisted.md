# Bug 2 — Watch-completed workouts never reach History

> **Surfaced:** 2026-05-06 real-device test pass (AMA-1751 v2 runbook).
> **Reporter:** David, on-device.
> **Symptom:** User starts a workout from Home, Watch picks it up, user runs it through to completion on Watch. Phone Home returns to "Rest Day" and More → History is empty. No record on backend either.

---

## Root cause

The Watch app already sends a full completion summary, and the phone already has a handler that posts it to the backend. The problem is the *transport*.

**Watch side** (`AmakaFlowCompanion/AmakaFlowWatch Watch App/StandaloneWorkoutEngine.swift:395`):

```swift
guard let session = WatchConnectivityBridge.shared.session, session.isReachable else {
    print("⌚️ Phone not reachable, can't send summary")
    return
}
// ... encodes summary ...
session.sendMessage(
    ["action": "workoutSummary", "summary": dict],
    replyHandler: ...,
    errorHandler: ...
)
```

`sendMessage` requires `session.isReachable == true`. From the Apple docs:

> `isReachable` is true only when the counterpart app is reachable. On
> watchOS, the iPhone app is reachable when the iPhone is unlocked AND
> the companion iOS app is running in the foreground (or has an active
> background session).

In practice the user finishes a workout on the watch with the iPhone in their pocket, screen locked. `isReachable` returns `false`, the early-return branch fires, the summary is silently discarded, and the message is **never queued for retry.**

**Phone side** (`AmakaFlow/Services/WatchConnectivityManager.swift:344-347`):

```swift
case "workoutSummary":
    handleWorkoutSummary(message)
    replyHandler(["status": "received"])
```

This handler is correct and would post to `/workouts/completions` if it ever ran — but it never gets a chance because the watch never sent.

---

## Fix

Switch the completion path from `sendMessage` (foreground-only, fire-and-forget) to `transferUserInfo` (queues to disk on the watch, delivered next time the iPhone wakes the companion app — survives reboots, locks, and airplane mode).

### Change 1 — Watch (`StandaloneWorkoutEngine.swift:394-419`)

Replace the reachability gate + `sendMessage` block with:

```swift
guard let session = WatchConnectivityBridge.shared.session else {
    print("⌚️ No WCSession available, can't queue summary")
    return
}

do {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(summary)
    guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return
    }
    // transferUserInfo persists across phone-locked / app-not-running
    // states, unlike sendMessage which silently drops when isReachable
    // is false. Workout completions must never be lost.
    session.transferUserInfo(["action": "workoutSummary", "summary": dict])
    print("⌚️ Workout summary queued via transferUserInfo")
} catch {
    print("⌚️ Failed to encode workout summary: \(error)")
}
```

### Change 2 — Phone (`AmakaFlow/Services/WatchConnectivityManager.swift`)

Add a `didReceiveUserInfo` handler that mirrors the existing `didReceiveMessage` switch:

```swift
func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
    print("⌚️ Received userInfo from watch: \(userInfo)")
    guard let action = userInfo["action"] as? String else { return }

    switch action {
    case "workoutSummary":
        handleWorkoutSummary(userInfo)

    case "logSet":
        handleSetLog(userInfo)

    // Add other queued-delivery actions here as needed.

    default:
        print("⌚️ Unknown userInfo action: \(action)")
    }
}
```

(The existing `case "workoutCompleted"` in `didReceiveMessage` can stay as a no-op ack — it's separate from the summary path and serves as a "user pressed end" signal.)

### Change 3 — Tests

- `AmakaFlowWatch Watch AppTests`: assert `transferUserInfo` is called with the right payload when a workout completes (via a fake `WCSession`).
- `AmakaFlowCompanionTests/WatchConnectivityTests`: assert `didReceiveUserInfo` with `action: "workoutSummary"` results in a `WorkoutCompletionService.postWatchWorkoutCompletion` call.

---

## Acceptance criteria

- Complete a workout on Watch with phone locked / in pocket. Within ~30s of unlocking the phone, the workout shows up in More → History and an XP/streak event fires.
- Airplane-mode the phone, complete a workout on Watch, re-enable connectivity. Workout shows up in History (transferUserInfo guarantees delivery).
- Existing `sendMessage`-based paths (state requests, command, healthMetrics streaming) continue working — only the *completion summary* moves to userInfo.

---

## Out of scope (file separately)

- Backend-side dedup if the same workoutId arrives via both `sendMessage` (when reachable) and `transferUserInfo` (queued). Pick one transport per action.
- Watch app local fallback if the user wipes the iPhone before delivery — userInfo queues are tied to the watch, but persist for ~7 days in practice.
- HealthKit-based completion path (when the Watch app uses `HKWorkoutSession` directly, completions also flow through HealthKit and may double-count). This is its own deduplication ticket.
