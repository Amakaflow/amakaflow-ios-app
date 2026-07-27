# WorkoutKit Sets/Reps Fidelity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Strength prescriptions schedule into Apple Workout with set count via `IntervalBlock.iterations` and reps/load via `WorkoutStep.displayName` (still `.open` goals).

**Architecture:** Split conversion — iOS `WorkoutKitConverter` emits `.repeatSet` and compact-folds load into DTO `name`; `workoutkit-sync` `WorkoutPlanConverter` formats `displayName`, validates structure with `WorkoutPlanConversionError`, then existing `WorkoutScheduler.schedule` path runs.

**Tech Stack:** Swift, WorkoutKit (iOS 18+ / watchOS 11+), SPM package `Amakaflow/workoutkit-sync`, XCTest.

**Spec:** `docs/superpowers/specs/2026-07-26-apple-workoutkit-sets-reps-fidelity-design.md`  
**Parent:** AMA-2287 · Export follow-up: AMA-2329

## Global Constraints

- No native reps `WorkoutGoal` — keep strength work steps `.open`
- Never force strength `location` to indoor/outdoor
- No recovery step when `restSec` is nil or ≤ 0
- `displayName` only assigned inside `makeWorkoutStep` behind `#available(iOS 18.0, watchOS 11.0, *)`
- Package release must be a **semver git tag** before the app pin bump
- Out of scope: duplicates, composition export (AMA-2329), timed stand-in goals

## File map

| File | Responsibility |
| --- | --- |
| `workoutkit-sync/.../WorkoutPlanConversionError.swift` (create) | Typed conversion errors |
| `workoutkit-sync/.../WorkoutPlanConverter.swift` | displayName, validation, rest rule |
| `workoutkit-sync/.../WorkoutPlanService.swift` | AMA-2329 comment near schedule |
| `workoutkit-sync/.../WKPlanDTO.swift` | Public `intervals` / Step getters for app tests |
| `workoutkit-sync/Tests/.../WorkoutPlanConverterTests.swift` | Package unit tests |
| `amakaflow-ios-app/.../WorkoutKitConverter.swift` | repeatSet + load compact + sets clamp/warn |
| `amakaflow-ios-app/.../WorkoutKitConverterTests.swift` | App DTO structure tests |
| `amakaflow-ios-app/docs/ama-2287-visual-evidence/README.md` | Truncation fixtures |

---

### Task 1: `WorkoutPlanConversionError` + failing package tests

**Files:**
- Create: `Sources/WorkoutKitSync/UseCases/WorkoutPlanConversionError.swift`
- Modify: `Tests/WorkoutKitSyncTests/WorkoutPlanConverterTests.swift`
- Modify: `Sources/WorkoutKitSync/Data/DTOs/WKPlanDTO.swift` (public `intervals` + Step property access if tests need them from app later — do public `intervals` now)

**Interfaces:**
- Produces: `public enum WorkoutPlanConversionError: Error, LocalizedError, Sendable` with `.zeroIterations(exerciseName:)` and `.emptyBlockSteps(exerciseName:)`

- [ ] **Step 1: Add error type**

```swift
import Foundation

public enum WorkoutPlanConversionError: Error, LocalizedError, Sendable {
    case zeroIterations(exerciseName: String?)
    case emptyBlockSteps(exerciseName: String?)

    public var errorDescription: String? {
        switch self {
        case .zeroIterations(let name):
            return "WorkoutKit interval block has zero iterations\(name.map { " (\($0))" } ?? "")"
        case .emptyBlockSteps(let name):
            return "WorkoutKit interval block has no steps\(name.map { " (\($0))" } ?? "")"
        }
    }
}
```

- [ ] **Step 2: Make DTO intervals readable from other modules**

In `WKPlanDTO.swift`, change `let intervals` to `public let intervals` and make `Step` stored properties `public let` (same for nested types used in assertions).

- [ ] **Step 3: Write failing tests** (append to `WorkoutPlanConverterTests.swift`)

```swift
    // displayName assertions require iOS 18 / watchOS 11+ runtime (package platform floor).

    func testRepsStepSetsDisplayNameWithRepCount() throws {
        let dto = WKPlanDTO(
            title: "Upper",
            sportType: "strengthTraining",
            intervals: [
                .repeatSet(reps: 3, intervals: [
                    .init(kind: "reps", reps: 8, name: "Pull-Ups · 25lb", restSec: 90)
                ])
            ]
        )
        let plan = try WorkoutPlanConverter().convert(dto)
        guard case .custom(let workout) = plan.workout else {
            return XCTFail("Expected custom workout")
        }
        XCTAssertEqual(workout.blocks.count, 1)
        XCTAssertEqual(workout.blocks[0].iterations, 3)
        let work = workout.blocks[0].steps.first { $0.purpose == .work }
        XCTAssertEqual(work?.step.displayName, "Pull-Ups · 25lb · 8 reps")
        XCTAssertEqual(workout.blocks[0].steps.filter { $0.purpose == .recovery }.count, 1)
    }

    func testNilRestSecOmitsRecoveryStep() throws {
        let dto = WKPlanDTO(
            title: "Upper",
            sportType: "strengthTraining",
            intervals: [
                .repeatSet(reps: 2, intervals: [
                    .init(kind: "reps", reps: 10, name: "Curl", restSec: nil)
                ])
            ]
        )
        let plan = try WorkoutPlanConverter().convert(dto)
        guard case .custom(let workout) = plan.workout else {
            return XCTFail("Expected custom workout")
        }
        XCTAssertEqual(workout.blocks[0].steps.count, 1)
        XCTAssertEqual(workout.blocks[0].steps[0].purpose, .work)
    }

    func testZeroIterationsThrowsConversionError() throws {
        let dto = WKPlanDTO(
            title: "Bad",
            sportType: "strengthTraining",
            intervals: [
                .repeatSet(reps: 0, intervals: [
                    .init(kind: "reps", reps: 8, name: "Pull-Ups")
                ])
            ]
        )
        XCTAssertThrowsError(try WorkoutPlanConverter().convert(dto)) { error in
            guard case WorkoutPlanConversionError.zeroIterations = error else {
                return XCTFail("Expected zeroIterations, got \(error)")
            }
        }
    }
```

- [ ] **Step 4: Run package tests — expect new tests FAIL**

```bash
cd /Users/davidandrews/dev/amakaflow-workspace/workoutkit-sync
swift test --filter WorkoutPlanConverterTests
```

Expected: `testRepsStepSetsDisplayNameWithRepCount` fails (displayName is bare name); `testZeroIterationsThrowsConversionError` fails (no throw).

- [ ] **Step 5: Commit**

```bash
git add Sources/WorkoutKitSync/UseCases/WorkoutPlanConversionError.swift \
  Sources/WorkoutKitSync/Data/DTOs/WKPlanDTO.swift \
  Tests/WorkoutKitSyncTests/WorkoutPlanConverterTests.swift
git commit -m "test: failing coverage for reps displayName and conversion errors"
```

---

### Task 2: Implement package converter (displayName + validation)

**Files:**
- Modify: `Sources/WorkoutKitSync/UseCases/WorkoutPlanConverter.swift`
- Modify: `Sources/WorkoutKitSync/Services/WorkoutPlanService.swift` (AMA-2329 comment)

**Interfaces:**
- Consumes: `WorkoutPlanConversionError`
- Produces: `convert(_:)` throws on invalid repeatSet; work steps get formatted `displayName`

- [ ] **Step 1: Format display name helper + use in `makeIntervalSteps`**

Replace `let displayName = step.name` with:

```swift
let displayName = Self.strengthDisplayName(name: step.name, reps: step.reps)
```

Add:

```swift
static func strengthDisplayName(name: String?, reps: Int?) -> String? {
    guard let reps else { return name }
    let base = (name?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "Exercise"
    return "\(base) · \(reps) reps"
}
```

Keep recovery gate:

```swift
if let restSec = step.restSec, restSec > 0 {
```

- [ ] **Step 2: Validate `repeatSet` before appending block**

In `case .repeatSet(let repetitions, let steps):` after building `intervalSteps`:

```swift
guard repetitions >= 1 else {
    let name = steps.first?.name
    throw WorkoutPlanConversionError.zeroIterations(exerciseName: name)
}
guard !intervalSteps.isEmpty else {
    let name = steps.first?.name
    throw WorkoutPlanConversionError.emptyBlockSteps(exerciseName: name)
}
```

Do **not** change `CustomWorkout(activity: activity)` to pass a location.

Confirm `makeWorkoutStep` remains the **only** place that constructs `WorkoutStep(..., displayName:)` behind `#available(iOS 18.0, watchOS 11.0, *)`.

- [ ] **Step 3: AMA-2329 breadcrumb** in `WorkoutPlanService.save` just above `scheduler.schedule`:

```swift
// Follow-up AMA-2329: WorkoutComposition export / AirDrop .workout share
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
cd /Users/davidandrews/dev/amakaflow-workspace/workoutkit-sync
swift test --filter WorkoutPlanConverterTests
```

- [ ] **Step 5: Commit, open PR, merge, tag**

```bash
git add Sources/WorkoutKitSync/UseCases/WorkoutPlanConverter.swift \
  Sources/WorkoutKitSync/Services/WorkoutPlanService.swift
git commit -m "feat: format reps displayName and validate IntervalBlock structure"

# After merge to main:
git checkout main && git pull
git tag -a 1.4.0 -m "1.4.0: strength displayName + WorkoutPlanConversionError"
git push origin 1.4.0
```

Use the next unused semver if `1.4.0` is taken; record the tag in the app PR description.

---

### Task 3: Gaps README truncation fixtures (app repo)

**Files:**
- Modify: `docs/ama-2287-visual-evidence/README.md`
- Spec already locked: `docs/superpowers/specs/2026-07-26-apple-workoutkit-sets-reps-fidelity-design.md`

- [ ] **Step 1: Append section** before device verify

```markdown
## Sets/reps fidelity follow-up (dogfood)

Spec: [`docs/superpowers/specs/2026-07-26-apple-workoutkit-sets-reps-fidelity-design.md`](../superpowers/specs/2026-07-26-apple-workoutkit-sets-reps-fidelity-design.md)

**Simulator floor:** Apple Watch Series 9 (45mm).

| Fixture `displayName` | Chars | Record result |
| --- | ---: | --- |
| `Pull-Ups · 25lb · 8 reps` | 26 | Fits preview + main? |
| `Weighted Pull-Ups · 25lb · 8 reps` | 34 | Preview truncates? Main OK? |
| `Romanian Deadlift · 135lb · 10 reps` | 36 | Exact truncation point |

Also verify: 3-set exercise → IntervalBlock repeats (not one Open step only).
```

- [ ] **Step 2: Commit**

```bash
cd /Users/davidandrews/dev/amakaflow-workspace/amakaflow-ios-app-ama-2287
git add docs/ama-2287-visual-evidence/README.md \
  docs/superpowers/specs/2026-07-26-apple-workoutkit-sets-reps-fidelity-design.md
git commit -m "[AMA-2287] Document sets/reps dogfood truncation fixtures"
```

---

### Task 4: Failing iOS converter tests

**Files:**
- Modify: `AmakaFlowCompanion/AmakaFlowCompanionTests/WorkoutKitConverterTests.swift`

**Interfaces:**
- Consumes: public `WKPlanDTO.intervals` from Task 1 tag (local path override OK for TDD before pin)

- [ ] **Step 1: Point SPM at local package OR wait for tag**

For TDD before tag exists, temporarily set Xcode SPM to local `workoutkit-sync` path. Revert to version tag in Task 6.

- [ ] **Step 2: Add failing tests**

```swift
    func testRepsWithSetsEmitsRepeatSet() throws {
        let workout = Workout(
            name: "Push",
            sport: .strength,
            duration: 1800,
            intervals: [
                .reps(sets: 3, reps: 8, name: "Pull-Ups", load: "25 lb", restSec: 90, followAlongUrl: nil)
            ],
            source: .coach
        )
        let dto = try converter.convertToWKPlanDTO(workout)
        guard case .repeatSet(let iterations, let steps) = dto.intervals.first else {
            return XCTFail("Expected repeatSet, got \(dto.intervals)")
        }
        XCTAssertEqual(iterations, 3)
        XCTAssertEqual(steps.first?.reps, 8)
        XCTAssertEqual(steps.first?.name, "Pull-Ups · 25lb")
        XCTAssertEqual(steps.first?.restSec, 90)
    }

    func testNilSetsDefaultsToOneIteration() throws {
        let workout = Workout(
            name: "Push",
            sport: .strength,
            duration: 600,
            intervals: [
                .reps(sets: nil, reps: 10, name: "Curl", load: nil, restSec: nil, followAlongUrl: nil)
            ],
            source: .coach
        )
        let dto = try converter.convertToWKPlanDTO(workout)
        guard case .repeatSet(let iterations, _) = dto.intervals.first else {
            return XCTFail("Expected repeatSet")
        }
        XCTAssertEqual(iterations, 1)
    }

    func testZeroSetsClampsToOne() throws {
        let workout = Workout(
            name: "Push",
            sport: .strength,
            duration: 600,
            intervals: [
                .reps(sets: 0, reps: 10, name: "Curl", load: nil, restSec: nil, followAlongUrl: nil)
            ],
            source: .coach
        )
        let dto = try converter.convertToWKPlanDTO(workout)
        guard case .repeatSet(let iterations, _) = dto.intervals.first else {
            return XCTFail("Expected repeatSet")
        }
        XCTAssertEqual(iterations, 1)
    }

    func testBodyWeightLoadIsNotSpaceStripped() throws {
        let workout = Workout(
            name: "Push",
            sport: .strength,
            duration: 600,
            intervals: [
                .reps(sets: 1, reps: 12, name: "Push-Up", load: "body weight", restSec: nil, followAlongUrl: nil)
            ],
            source: .coach
        )
        let dto = try converter.convertToWKPlanDTO(workout)
        guard case .repeatSet(_, let steps) = dto.intervals.first else {
            return XCTFail("Expected repeatSet")
        }
        XCTAssertEqual(steps.first?.name, "Push-Up · body weight")
    }
```

- [ ] **Step 3: Run tests — expect FAIL** (still single `.step`)

```bash
# From Xcode: AmakaFlowCompanionTests › WorkoutKitConverterTests
# or xcodebuild -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 16' \
#   -only-testing:AmakaFlowCompanionTests/WorkoutKitConverterTests test
```

- [ ] **Step 4: Commit**

```bash
git commit -am "[AMA-2287] test: failing WorkoutKitConverter sets/reps assertions"
```

---

### Task 5: Implement iOS `WorkoutKitConverter`

**Files:**
- Modify: `AmakaFlow/Services/WorkoutKitConverter.swift`

- [ ] **Step 1: Add logger + compact load helper**

```swift
import OSLog

private let workoutKitConverterLog = Logger(
    subsystem: "com.myamaka.AmakaFlowCompanion",
    category: "WorkoutKitConverter"
)

private func compactLoadToken(_ load: String) -> String {
    let trimmed = load.trimmingCharacters(in: .whitespacesAndNewlines)
    let pattern = #"^\d+\s+[A-Za-z%]+$"#
    if trimmed.range(of: pattern, options: .regularExpression) != nil {
        return trimmed.replacingOccurrences(of: " ", with: "")
    }
    return trimmed
}

private func displayName(exercise: String, load: String?) -> String {
    guard let load, !load.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return exercise
    }
    return "\(exercise) · \(compactLoadToken(load))"
}
```

- [ ] **Step 2: Replace `.reps` case**

```swift
case .reps(let sets, let reps, let name, let load, let restSec, _):
    if let sets, sets < 1 {
        workoutKitConverterLog.warning(
            "WorkoutKitConverter: received sets=\(sets, privacy: .public) for '\(name, privacy: .public)'; clamping to 1"
        )
    }
    let setCount = max(sets ?? 1, 1)
    let rest = (restSec ?? 0) > 0 ? restSec : nil
    let step = WKPlanDTO.Interval.Step(
        kind: "reps",
        seconds: nil,
        meters: nil,
        reps: reps,
        name: displayName(exercise: name, load: load),
        load: nil, // convertLoad remains stub
        restSec: rest,
        target: nil
    )
    return .repeatSet(reps: setCount, intervals: [step])
```

- [ ] **Step 3: Run converter tests — expect PASS**

- [ ] **Step 4: Commit**

```bash
git commit -am "[AMA-2287] Emit repeatSet and compact load for WorkoutKit strength steps"
```

---

### Task 6: Pin `workoutkit-sync` to release tag

**Files:**
- Modify: `AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.pbxproj` (SPM requirement)
- Modify: `AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`

- [ ] **Step 1: Resolve to tag from Task 2** (example `1.4.0`)

In Xcode: Package Dependencies → workoutkit-sync → Up to Next Major / exact version matching the tag. Or edit resolved file after `xcodebuild -resolvePackageDependencies`.

- [ ] **Step 2: Confirm no local path override remains**

- [ ] **Step 3: Re-run `WorkoutKitConverterTests` + package-dependent handoff tests**

- [ ] **Step 4: Commit**

```bash
git add AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.pbxproj \
  AmakaFlowCompanion/AmakaFlowCompanion.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
git commit -m "[AMA-2287] Bump workoutkit-sync to 1.4.0 for reps displayName"
```

---

### Task 7: Device / Simulator dogfood + PR

- [ ] **Step 1: Build** AmakaFlowCompanion to phone; schedule a known 3×N strength workout via Start → Workout on Apple Watch

- [ ] **Step 2: Fill truncation table** in `docs/ama-2287-visual-evidence/README.md` with Y/N notes from Series 9 45mm (sim or device)

- [ ] **Step 3: Commit notes if updated; open app PR** base `main`, title `[AMA-2287] WorkoutKit sets/reps fidelity`

PR body must link spec + package tag + AMA-2329 for export non-goal.

- [ ] **Step 4: Request CodeRabbit on Amakaflow org PR** (`@coderabbitai review`)

---

## Spec coverage self-check

| Spec requirement | Task |
| --- | --- |
| repeatSet from sets | 5 |
| displayName with reps | 2 |
| Compact numeric load / preserve phrases | 5 |
| Warn on sets &lt; 1 | 5 |
| No recovery when rest nil/0 | 2 (+ tests 1) |
| `WorkoutPlanConversionError` | 1–2 |
| Location omitted | 2 (no change) |
| Truncation fixtures in gaps README | 3, 7 |
| Semver tag pin | 2, 6 |
| AMA-2329 comment | 2 |
| `#available` at assignment site | 2 (keep `makeWorkoutStep`) |
