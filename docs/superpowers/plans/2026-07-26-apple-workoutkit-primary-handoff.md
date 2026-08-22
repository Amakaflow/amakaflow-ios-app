# WorkoutKit-primary Start handoff — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Flip Library → Start → Apple so workouts always schedule into the native **Workout** app via WorkoutKit (Watch-leading copy), with no WatchConnectivity send on this path.

**Architecture:** `AppleStartHandoffService.handoff(workout:)` gates iOS 18 first, shows pending status at the call site through auth, saves via existing `WorkoutKitSaving` / `WorkoutKitConverter` / `WorkoutKitSync`, and picks success copy from a **read-only** pairing enum (`confirmedUnpaired` only when WCSession is activated and `isPaired == false`; otherwise optimistic paired-style copy). AmakaFlowWatch send is out of scope.

**Tech Stack:** Swift, SwiftUI, WorkoutKit / WorkoutKitSync (iOS 18+), WatchConnectivity (pairing read only), XCTest

**Spec:** `docs/superpowers/specs/2026-07-26-apple-fitness-workoutkit-primary-design.md`

## Global Constraints

- User-facing destination name is **Workout** / **Workout on Apple Watch** — never “Apple Fitness” / “Fitness app” in status or Start-sheet labels.
- Internal enum kind `savedToFitness` may remain; it must not appear in user strings.
- Do **not** call `sendWorkout` / `sendWorkoutWithOutcome` from the Start → Apple path.
- `watchReachable` must be **removed** from `handoff` signature, call site, and handoff tests (not kept-and-ignored).
- Pairing unknown or session not activated → **paired-style** success copy (optimistic).
- Unpaired success copy only on **confirmed** not-paired.
- No iPhone-as-run-surface copy on iOS 18–25.
- Default schedule remains package “now”; trial B (+5–10 min) is DEBUG-only and **must not ship enabled**.
- Duplicate scheduled plans are an accepted gap — document, do not implement dedupe.
- Garmin handoff / CIQ code: do not modify.
- Physical device required for WorkoutKit dogfood; no Simulator claims of save success.

---

## File Structure

| File | Responsibility |
| ---- | -------------- |
| `AmakaFlow/Services/AppleStartHandoff.swift` | Copy, pairing enum/protocol, WorkoutKit-only `handoff(workout:)` |
| `AmakaFlow/Services/WatchConnectivityManager.swift` | Add `pairingReadForCopy()` (read-only; no send changes) |
| `AmakaFlow/Views/UnifiedWorkoutDetailView.swift` | Pending status; call `handoff(workout:)` only |
| `AmakaFlow/Models/WorkoutStartSelection.swift` | Labels for Workout on Apple Watch; drop reachability gating copy |
| `AmakaFlow/Views/Components/WorkoutStartSheet.swift` | Align availability label with new defaults |
| `AmakaFlowCompanion/AmakaFlowCompanionTests/AppleStartHandoffTests.swift` | Primary-path unit tests |
| `AmakaFlowCompanion/AmakaFlowCompanionTests/WorkoutStartSelectionTests.swift` | Label assertions |
| `docs/ama-2287-visual-evidence/README.md` | Gaps + dogfood checklist (schedule A/B, duplicates, where to look) |

**Leave alone:** AmakaFlowWatch app sources, `WatchWorkoutSendOutcomeTests`, Garmin handoff, mapper-api, `workoutkit-sync` shipping default (unless dogfood A fails — then a separate commit to change default; see Task 6).

---

### Task 1: Success / failure copy + pairing read types

**Files:**
- Modify: `AmakaFlow/Services/AppleStartHandoff.swift`
- Modify: `AmakaFlow/Services/WatchConnectivityManager.swift`
- Test: `AmakaFlowCompanion/AmakaFlowCompanionTests/AppleStartHandoffTests.swift`

**Interfaces:**
- Produces:
  - `enum AppleWatchPairingRead: Equatable { case confirmedPaired, confirmedUnpaired, unknown }`
  - `protocol AppleWatchPairingReading: Sendable { func pairingReadForCopy() -> AppleWatchPairingRead }`
  - `WatchConnectivityManager.pairingReadForCopy() -> AppleWatchPairingRead`
  - `AppleStartHandoffCopy.scheduledInWorkoutMessage(workoutName:pairing:)` → `AppleStartHandoffResult`
  - Updated failure strings for `.authorizationDenied` and `.iosVersionUnsupported`

- [ ] **Step 1: Write failing copy / pairing tests**

Replace / add in `AppleStartHandoffCopyTests` (remove AmakaFlowWatch-success and “Apple Fitness” assertions):

```swift
func testScheduledMessagePairedOrUnknownIsWatchLeading() {
    for pairing: AppleWatchPairingRead in [.confirmedPaired, .unknown] {
        let result = AppleStartHandoffCopy.scheduledInWorkoutMessage(
            workoutName: "Easy Run",
            pairing: pairing
        )
        XCTAssertEqual(result.kind, .savedToFitness)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("Workout"))
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("Apple Watch"))
        XCTAssertTrue(result.message.contains("Easy Run"))
        XCTAssertFalse(result.message.localizedCaseInsensitiveContains("Apple Fitness"))
        XCTAssertFalse(result.message.localizedCaseInsensitiveContains("iPhone"))
        XCTAssertFalse(result.message.localizedCaseInsensitiveContains("AmakaFlowWatch"))
    }
}

func testScheduledMessageConfirmedUnpairedAsksToPair() {
    let result = AppleStartHandoffCopy.scheduledInWorkoutMessage(
        workoutName: "Push Day",
        pairing: .confirmedUnpaired
    )
    XCTAssertEqual(result.kind, .savedToFitness)
    XCTAssertTrue(result.message.localizedCaseInsensitiveContains("pair"))
    XCTAssertTrue(result.message.contains("Push Day"))
    XCTAssertFalse(result.message.localizedCaseInsensitiveContains("open the Workout app on your Apple Watch"))
}

func testAuthorizationDeniedCopyMentionsSettingsHealth() {
    let message = AppleStartHandoffCopy.failureMessage(code: .authorizationDenied)
    XCTAssertTrue(message.localizedCaseInsensitiveContains("permission denied"))
    XCTAssertTrue(message.localizedCaseInsensitiveContains("Settings"))
    XCTAssertTrue(message.localizedCaseInsensitiveContains("Health"))
    XCTAssertFalse(message.localizedCaseInsensitiveContains("Apple Fitness"))
}

func testIosUnsupportedCopyMentionsWorkoutApp() {
    let message = AppleStartHandoffCopy.failureMessage(code: .iosVersionUnsupported)
    XCTAssertTrue(message.localizedCaseInsensitiveContains("iOS 18"))
    XCTAssertTrue(message.localizedCaseInsensitiveContains("Workout"))
}
```

Add pairing-read tests (new class or extend service tests file) using `MockWatchSession`:

```swift
@MainActor
final class AppleWatchPairingReadTests: XCTestCase {
    func testNotActivatedIsUnknownEvenIfIsPairedFalse() {
        let mock = MockWatchSession()
        mock.activationState = .notActivated
        mock.isPaired = false
        let manager = WatchConnectivityManager(session: mock)
        XCTAssertEqual(manager.pairingReadForCopy(), .unknown)
    }

    func testActivatedAndNotPairedIsConfirmedUnpaired() {
        let mock = MockWatchSession()
        mock.activationState = .activated
        mock.isPaired = false
        let manager = WatchConnectivityManager(session: mock)
        XCTAssertEqual(manager.pairingReadForCopy(), .confirmedUnpaired)
    }

    func testActivatedAndPairedIsConfirmedPaired() {
        let mock = MockWatchSession()
        mock.activationState = .activated
        mock.isPaired = true
        let manager = WatchConnectivityManager(session: mock)
        XCTAssertEqual(manager.pairingReadForCopy(), .confirmedPaired)
    }
}
```

Confirm `MockWatchSession` exposes settable `isPaired` and `activationState` (it should via `WatchSessionProviding`). If properties are missing as `var`, add them on the mock only.

- [ ] **Step 2: Run tests — expect FAIL**

Run (from repo root, Xcode or xcodebuild for the Companion test target):

```bash
xcodebuild test -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:AmakaFlowCompanionTests/AppleStartHandoffCopyTests \
  -only-testing:AmakaFlowCompanionTests/AppleWatchPairingReadTests
```

Expected: FAIL — `scheduledInWorkoutMessage` / `pairingReadForCopy` missing.

- [ ] **Step 3: Implement types + copy + pairing read**

In `AppleStartHandoff.swift`, add:

```swift
enum AppleWatchPairingRead: Equatable {
    case confirmedPaired
    case confirmedUnpaired
    case unknown
}

protocol AppleWatchPairingReading: Sendable {
    func pairingReadForCopy() -> AppleWatchPairingRead
}

extension AppleStartHandoffCopy {
    static func scheduledInWorkoutMessage(
        workoutName: String,
        pairing: AppleWatchPairingRead
    ) -> AppleStartHandoffResult {
        switch pairing {
        case .confirmedUnpaired:
            return AppleStartHandoffResult(
                kind: .savedToFitness,
                message: "Scheduled in Workout — pair an Apple Watch to run \"\(workoutName)\"."
            )
        case .confirmedPaired, .unknown:
            return AppleStartHandoffResult(
                kind: .savedToFitness,
                message: "Scheduled in Workout — open the Workout app on your Apple Watch for \"\(workoutName)\"."
            )
        }
    }
}
```

Update failure dictionary entries:

```swift
.authorizationDenied: "Workout permission denied — Settings → Health → Data Access → AmakaFlow, allow Workouts.",
.iosVersionUnsupported: "Requires iOS 18 to schedule in the Workout app — update iPhone and retry.",
```

Deprecate user-facing use of `savedToFitnessMessage` / `sentToWatchMessage` for the Start path (keep `sentToWatchMessage` if other tests need it, or leave unused). Prefer deleting `savedToFitnessMessage` and migrating all call sites to `scheduledInWorkoutMessage`.

In `WatchConnectivityManager.swift`:

```swift
func pairingReadForCopy() -> AppleWatchPairingRead {
    guard let session else { return .unknown }
    guard session.activationState == .activated else { return .unknown }
    return session.isPaired ? .confirmedPaired : .confirmedUnpaired
}
```

Conform manager (or a tiny wrapper) to `AppleWatchPairingReading` if the service will depend on the protocol.

- [ ] **Step 4: Run tests — expect PASS**

Same `xcodebuild test` command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add AmakaFlow/Services/AppleStartHandoff.swift \
  AmakaFlow/Services/WatchConnectivityManager.swift \
  AmakaFlowCompanion/AmakaFlowCompanionTests/AppleStartHandoffTests.swift
git commit -m "$(cat <<'EOF'
[AMA-2287] Add Workout-leading copy and optimistic pairing read

EOF
)"
```

---

### Task 2: Rewrite `AppleStartHandoffService` to WorkoutKit-only

**Files:**
- Modify: `AmakaFlow/Services/AppleStartHandoff.swift`
- Test: `AmakaFlowCompanion/AmakaFlowCompanionTests/AppleStartHandoffTests.swift`

**Interfaces:**
- Consumes: `WorkoutKitSaving`, `AppleWatchPairingReading`, `AppleStartHandoffCopy`
- Produces: `AppleStartHandoffService.handoff(workout: Workout) async -> AppleStartHandoffResult` (no `watchReachable`)

- [ ] **Step 1: Rewrite service tests (failing against old API)**

Replace `AppleStartHandoffServiceTests` body with:

```swift
@MainActor
final class AppleStartHandoffServiceTests: XCTestCase {
    private func sampleWorkout() -> Workout {
        Workout(
            name: "Test Strength",
            sport: .strength,
            duration: 1800,
            intervals: [
                .reps(sets: 3, reps: 8, name: "Squat", load: nil, restSec: 90, followAlongUrl: nil)
            ],
            source: .manual
        )
    }

    func testHandoffAlwaysSavesViaWorkoutKit() async {
        let saver = MockWorkoutKitSaver()
        let pairing = MockPairingReader(read: .unknown)
        let service = AppleStartHandoffService(
            pairingReader: pairing,
            workoutKitSaver: saver
        )
        let result = await service.handoff(workout: sampleWorkout())
        XCTAssertEqual(result.kind, .savedToFitness)
        XCTAssertEqual(saver.savedWorkoutNames, ["Test Strength"])
        XCTAssertEqual(saver.saveCallCount, 1)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("Apple Watch"))
        XCTAssertFalse(result.message.localizedCaseInsensitiveContains("Sent to Apple Watch"))
    }

    func testHandoffConfirmedUnpairedUsesPairCopy() async {
        let saver = MockWorkoutKitSaver()
        let service = AppleStartHandoffService(
            pairingReader: MockPairingReader(read: .confirmedUnpaired),
            workoutKitSaver: saver
        )
        let result = await service.handoff(workout: sampleWorkout())
        XCTAssertEqual(result.kind, .savedToFitness)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("pair"))
    }

    func testHandoffEmptyWorkoutFailsFastWithoutSave() async {
        let empty = Workout(
            name: "Empty", sport: .strength, duration: 0, intervals: [], source: .manual
        )
        let saver = MockWorkoutKitSaver()
        let service = AppleStartHandoffService(
            pairingReader: MockPairingReader(read: .unknown),
            workoutKitSaver: saver
        )
        let result = await service.handoff(workout: empty)
        XCTAssertEqual(result.kind, .failed)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("no steps"))
        XCTAssertEqual(saver.saveCallCount, 0)
    }

    func testAuthorizationDeniedMapsToSettingsCopy() async {
        let saver = MockWorkoutKitSaver()
        saver.errorToThrow = WorkoutPlanError.authorizationDenied
        let service = AppleStartHandoffService(
            pairingReader: MockPairingReader(read: .confirmedPaired),
            workoutKitSaver: saver
        )
        let result = await service.handoff(workout: sampleWorkout())
        XCTAssertEqual(result.kind, .failed)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("permission denied"))
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("Settings"))
    }

    func testNilWorkoutKitSaverIsBlockedIosUnsupported() async {
        let service = AppleStartHandoffService(
            pairingReader: MockPairingReader(read: .unknown),
            workoutKitSaver: nil
        )
        let result = await service.handoff(workout: sampleWorkout())
        XCTAssertEqual(result.kind, .blocked)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("iOS 18"))
    }

    func testForcedFailureEnvironment() async {
        setenv("AF_FAULT_APPLE_START_FAIL", "authorization_denied", 1)
        defer { unsetenv("AF_FAULT_APPLE_START_FAIL") }
        let service = AppleStartHandoffService(
            pairingReader: MockPairingReader(read: .unknown),
            workoutKitSaver: MockWorkoutKitSaver()
        )
        let result = await service.handoff(workout: sampleWorkout())
        XCTAssertEqual(result.kind, .failed)
        XCTAssertTrue(result.message.localizedCaseInsensitiveContains("permission denied"))
    }
}

private struct MockPairingReader: AppleWatchPairingReading {
    let read: AppleWatchPairingRead
    func pairingReadForCopy() -> AppleWatchPairingRead { read }
}

private final class MockWorkoutKitSaver: WorkoutKitSaving, @unchecked Sendable {
    private(set) var savedWorkoutNames: [String] = []
    private(set) var saveCallCount = 0
    var errorToThrow: Error?

    func saveToWorkoutKit(_ workout: Workout) async throws {
        saveCallCount += 1
        if let errorToThrow { throw errorToThrow }
        savedWorkoutNames.append(workout.name)
    }
}
```

Keep `WatchWorkoutSendOutcomeTests` in this file unchanged.

- [ ] **Step 2: Run service tests — expect FAIL**

```bash
xcodebuild test -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:AmakaFlowCompanionTests/AppleStartHandoffServiceTests
```

Expected: FAIL — old `handoff(workout:watchReachable:)` / WCSession-first behavior.

- [ ] **Step 3: Implement WorkoutKit-only handoff**

Replace `AppleStartHandoffService` roughly as:

```swift
@MainActor
final class AppleStartHandoffService {
    private let pairingReader: any AppleWatchPairingReading
    private let workoutKitSaver: (any WorkoutKitSaving)?
    private let forceFailureCode: (() -> AppleStartHandoffFailureCode?)?

    init(
        pairingReader: any AppleWatchPairingReading = LiveAppleWatchPairingReader(),
        workoutKitSaver: (any WorkoutKitSaving)? = nil,
        forceFailureCode: (() -> AppleStartHandoffFailureCode?)? = nil
    ) {
        self.pairingReader = pairingReader
        if #available(iOS 18.0, *) {
            self.workoutKitSaver = workoutKitSaver ?? LiveWorkoutKitSaver()
        } else {
            self.workoutKitSaver = nil
        }
        // keep existing AF_FAULT_APPLE_START_FAIL default for forceFailureCode
        self.forceFailureCode = forceFailureCode ?? { /* same as today */ }
    }

    func handoff(workout: Workout) async -> AppleStartHandoffResult {
        if let forced = forceFailureCode?() {
            return AppleStartHandoffResult(
                kind: .failed,
                message: AppleStartHandoffCopy.failureMessage(code: forced)
            )
        }

        if workout.intervals.isEmpty {
            return AppleStartHandoffResult(
                kind: .failed,
                message: AppleStartHandoffCopy.failureMessage(code: .emptyWorkout)
            )
        }

        // iOS 18 gate FIRST (availability / nil saver)
        guard let workoutKitSaver else {
            return AppleStartHandoffResult(
                kind: .blocked,
                message: AppleStartHandoffCopy.failureMessage(code: .iosVersionUnsupported)
            )
        }

        do {
            try await workoutKitSaver.saveToWorkoutKit(workout)
            return AppleStartHandoffCopy.scheduledInWorkoutMessage(
                workoutName: workout.name,
                pairing: pairingReader.pairingReadForCopy()
            )
        } catch {
            let code = AppleStartHandoffCopy.failureCode(from: error)
            return AppleStartHandoffResult(
                kind: .failed,
                message: AppleStartHandoffCopy.failureMessage(
                    code: code,
                    detail: error.localizedDescription
                )
            )
        }
    }
}

struct LiveAppleWatchPairingReader: AppleWatchPairingReading {
    func pairingReadForCopy() -> AppleWatchPairingRead {
        WatchConnectivityManager.shared.pairingReadForCopy()
    }
}
```

Delete `saveToFitnessFallback` and all `watchReachable` / `sendWorkoutWithOutcome` branches from this service. Do **not** remove `WatchConnectivityManager.sendWorkoutWithOutcome` itself.

Update file header comment to: WorkoutKit-primary Start → Workout on Apple Watch.

- [ ] **Step 4: Run service tests — expect PASS**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add AmakaFlow/Services/AppleStartHandoff.swift \
  AmakaFlowCompanion/AmakaFlowCompanionTests/AppleStartHandoffTests.swift
git commit -m "$(cat <<'EOF'
[AMA-2287] Make Start→Apple WorkoutKit-primary (drop WCSession send)

EOF
)"
```

---

### Task 3: Call site pending status + Start sheet labels

**Files:**
- Modify: `AmakaFlow/Views/UnifiedWorkoutDetailView.swift` (approx. `beginAppleTryHandoff` ~311–321)
- Modify: `AmakaFlow/Models/WorkoutStartSelection.swift`
- Modify: `AmakaFlow/Views/Components/WorkoutStartSheet.swift` (availability label usage)
- Test: `AmakaFlowCompanion/AmakaFlowCompanionTests/WorkoutStartSelectionTests.swift`

**Interfaces:**
- Consumes: `AppleStartHandoffService.handoff(workout:)`
- Produces: pending `"Scheduling in Workout…"` then result message; Start device title/subtitle per spec

- [ ] **Step 1: Update Start selection tests**

```swift
func testAppleDeviceLabelIsWorkoutOnAppleWatch() {
    XCTAssertEqual(WorkoutStartDevice.apple.title, "Workout on Apple Watch")
    XCTAssertFalse(WorkoutStartDevice.apple.subtitle.localizedCaseInsensitiveContains("AMA-2287"))
    XCTAssertFalse(WorkoutStartDevice.apple.subtitle.localizedCaseInsensitiveContains("Fitness"))
}

func testAppleAvailabilityLabelDoesNotDependOnReachability() {
    XCTAssertEqual(
        WorkoutStartDefaults.appleAvailabilityLabel(watchReachable: true),
        WorkoutStartDefaults.appleAvailabilityLabel(watchReachable: false)
    )
    XCTAssertFalse(
        WorkoutStartDefaults.appleAvailabilityLabel(watchReachable: false)
            .localizedCaseInsensitiveContains("not reachable")
    )
}
```

Remove assertions that expect `"Try"` / `"Try — Watch not reachable"`.

- [ ] **Step 2: Run — expect FAIL**

```bash
xcodebuild test -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:AmakaFlowCompanionTests/WorkoutStartSelectionTests
```

- [ ] **Step 3: Implement labels + call site**

`WorkoutStartSelection.swift`:

```swift
case .apple: return "Workout on Apple Watch"  // title
// subtitle:
case .apple: return "Native Workout app via WorkoutKit"

static func appleAvailabilityLabel(watchReachable: Bool) -> String {
    _ = watchReachable
    return "Schedule"
}
```

`UnifiedWorkoutDetailView.beginAppleTryHandoff`:

```swift
fileprivate func beginAppleTryHandoff() {
    handoffStatus = "Scheduling in Workout…"
    Task {
        let result = await AppleStartHandoffService().handoff(workout: workout)
        handoffStatus = result.message
    }
}
```

Stop passing `watchReachable`. You may leave `appleWatchReachable` / Start sheet parameter for other UI (Connections-style badges) but it must not drive handoff. If Start sheet still shows “not reachable” via old label, the new `appleAvailabilityLabel` removes that.

Previews that used `appleWatchReachableOverride` for handoff behavior can keep the property for sheet chrome only.

- [ ] **Step 4: Run selection + handoff tests — expect PASS**

```bash
xcodebuild test -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:AmakaFlowCompanionTests/WorkoutStartSelectionTests \
  -only-testing:AmakaFlowCompanionTests/AppleStartHandoffServiceTests \
  -only-testing:AmakaFlowCompanionTests/AppleStartHandoffCopyTests
```

- [ ] **Step 5: Commit**

```bash
git add AmakaFlow/Views/UnifiedWorkoutDetailView.swift \
  AmakaFlow/Models/WorkoutStartSelection.swift \
  AmakaFlow/Views/Components/WorkoutStartSheet.swift \
  AmakaFlowCompanion/AmakaFlowCompanionTests/WorkoutStartSelectionTests.swift
git commit -m "$(cat <<'EOF'
[AMA-2287] Pending Workout status + Start sheet Workout labels

EOF
)"
```

---

### Task 4: Gaps README + schedule-matrix dogfood notes

**Files:**
- Modify: `docs/ama-2287-visual-evidence/README.md`

- [ ] **Step 1: Replace README content** with a single coherent doc (no old WCSession-first paths as the primary story). Required sections:

1. **Where to look** — native Workout app on Apple Watch; AmakaFlowWatch is **not** this path.
2. **Primary path** — Start → Workout on Apple Watch → WorkoutKit schedule.
3. **Schedule matrix** — Trial A = shipping default (`now`); Trial B = +5–10 min **DEBUG-only, must not ship enabled**. Record appearance + latency; if A no-shows and B works, change shipping default before Done.
4. **Duplicates** — accepted gap; multiple Starts accumulate plans; follow-up = track + replace per Library workout.
5. **Pairing copy** — unknown/not activated → optimistic Watch copy; unpaired only when confirmed.
6. **Auth** — first run may show system sheet; UI pending through it.
7. **Strength fidelity** — load/target still weak (known).
8. **Device evidence checklist** — the 8 manual steps from the spec.
9. **Garmin unaffected**.

Do not leave the old “Watch reachable → AmakaFlowWatch” table as the current design.

Optional DEBUG override for Trial B (only if useful during dogfood) — add to `WorkoutKitConverter.saveToWorkoutKit` or a DEBUG-only wrapper:

```swift
#if DEBUG
if let raw = ProcessInfo.processInfo.environment["AMA2287_SCHEDULE_OFFSET_MINUTES"],
   let minutes = Int(raw), minutes > 0 {
    var comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
    // apply offset via Date then re-extract — pass scheduleAt into WorkoutKitSync.save
}
#endif
```

**Release builds must ignore this env var.** Document the env name in the README. Prefer call-site `scheduleAt` over changing `workoutkit-sync` package default until Trial A fails.

If you add the DEBUG override, cover with a unit test that the production path (no env) still uses `scheduleAt: nil` / now — and never enable a default offset in `#else`.

- [ ] **Step 2: Commit**

```bash
git add docs/ama-2287-visual-evidence/README.md
# and any DEBUG schedule helper files if added
git commit -m "$(cat <<'EOF'
[AMA-2287] Document WorkoutKit-primary gaps and schedule A/B dogfood

EOF
)"
```

---

### Task 5: Full unit suite + Linear note

**Files:** none required if green; fix only regressions from Tasks 1–4.

- [ ] **Step 1: Run focused + broader handoff-related tests**

```bash
xcodebuild test -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:AmakaFlowCompanionTests/AppleStartHandoffCopyTests \
  -only-testing:AmakaFlowCompanionTests/AppleStartHandoffServiceTests \
  -only-testing:AmakaFlowCompanionTests/AppleWatchPairingReadTests \
  -only-testing:AmakaFlowCompanionTests/WorkoutStartSelectionTests \
  -only-testing:AmakaFlowCompanionTests/WatchWorkoutSendOutcomeTests
```

Expected: all PASS. `WatchWorkoutSendOutcomeTests` still pass (WCSession send API retained for later).

- [ ] **Step 2: Grep for regressions**

```bash
rg -n "handoff\(workout:.*watchReachable|Saved to Apple Fitness|Sent to Apple Watch — open AmakaFlowWatch|Try — Watch / WorkoutKit" \
  AmakaFlow AmakaFlowCompanion/AmakaFlowCompanionTests
```

Expected: no matches in Start/handoff paths (failure-code leftovers for old WCSession codes may remain in the enum for now — OK if unused by handoff).

- [ ] **Step 3: Commit only if Step 2 required fixes**

---

### Task 6: Physical-device dogfood (human) + optional schedule default fix

**Files:**
- Possibly modify: `workoutkit-sync` default or iOS `scheduleAt` call site — **only if Trial A fails and B works**
- Update: `docs/ama-2287-visual-evidence/README.md` with findings + screenshots
- Linear: AMA-2287 comment

- [ ] **Step 1: Device checklist** (human)

Follow spec manual steps 1–8. For Trial B set `AMA2287_SCHEDULE_OFFSET_MINUTES=10` in the Debug scheme **only**; clear it before any TestFlight/Release archive.

- [ ] **Step 2: If A no-shows and B works — change shipping default**

Pass an explicit future `scheduleAt` (e.g. now + 5 minutes) from the production save path (not DEBUG-only). Remove reliance on the env var. Document the new default in the gaps README. Commit:

```bash
git commit -m "$(cat <<'EOF'
[AMA-2287] Schedule WorkoutKit plans slightly in the future after dogfood

EOF
)"
```

- [ ] **Step 3: Confirm no debug override ships**

```bash
rg -n "AMA2287_SCHEDULE_OFFSET" AmakaFlow
```

Ensure any remaining reference is inside `#if DEBUG`.

- [ ] **Step 4: Attach screenshots + Linear update**

Comment on AMA-2287 with: schedule A/B results, whether default changed, unpaired/pending auth notes, link to gaps README. Mark acceptance checkboxes when met.

---

## Spec coverage checklist

| Spec requirement | Task |
| ---------------- | ---- |
| WorkoutKit-only handoff; remove `watchReachable` | 2, 3 |
| iOS 18 gate first | 2 |
| Watch-leading / unpaired / auth copy | 1, 2 |
| Pairing unknown → optimistic paired copy | 1, 2 |
| Pending status through auth | 3 |
| Start label Workout on Apple Watch | 3 |
| Gaps: schedule matrix, duplicates, where to look | 4, 6 |
| Trial B must not ship enabled | 4, 6 |
| Unit tests primary-path auth | 2 |
| Device dogfood / escape-hatch gaps note | 6 |
| Garmin untouched | (constraint — no tasks touch Garmin) |
| No AmakaFlowWatch send | 2 |
| Dedupe follow-up documented not built | 4 |

## Self-review notes

- No TBD/placeholder steps; signatures and copy strings are concrete.
- `savedToFitness` kind name kept internally per spec.
- WCSession send tests retained; handoff no longer depends on them.
- Schedule default change is gated on dogfood evidence (Task 6), not assumed upfront.
