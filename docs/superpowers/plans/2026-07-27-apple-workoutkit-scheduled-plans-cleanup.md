# Scheduled WorkoutKit plan cleanup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users list and delete AmakaFlow-scheduled WorkoutKit plans on iPhone (multi-select, swipe, Clear all) without changing Start’s keep-adding behavior.

**Architecture:** App-shaped `WorkoutKitScheduleManaging` (Live → `WorkoutScheduler` with plan cache + auth state; Mock for tests). ViewModel reconciles delete outcomes via **still-present after refresh**. UI: `WorkoutScheduleView` from Devices and Start success.

**Tech Stack:** Swift, SwiftUI, WorkoutKit (iOS 18+), XCTest

**Spec:** `docs/superpowers/specs/2026-07-27-apple-workoutkit-scheduled-plans-cleanup-design.md`  
**Linear:** AMA-2330 (parent AMA-2287)

## Global Constraints

- Start **keeps adding** — at-cap preflight may fail Start; never auto-delete to make room.
- Brand: **AmakaFlow**. Destination: **Workout** / Apple Watch Workout.
- Pre-iOS 18: **hide** Devices row and Manage link. Live `@available(iOS 18.0, *)`.
- `remove` / `removeAll` on the protocol are **non-throwing**. Failure = still present after refresh.
- Live caches `WorkoutPlan` by row id from the latest `fetchScheduledRows()`; missing cache → remove no-op.
- Selection: (1) manual refresh clears; (2) post-delete `selectedIDs = attempted ∩ stillPresent`.
- Cap: `maxAllowedCount` from Apple — never hardcode 15 in copy.
- No `workoutkit-sync` extraction in V1. Leave Garmin / AmakaFlowWatch / AMA-2329 alone.

---

## File Structure

| File | Responsibility |
| ---- | -------------- |
| `AmakaFlow/Services/WorkoutKitScheduleManaging.swift` | Auth enum, row ID, row model, protocol, Live (+ cache), Mock |
| `AmakaFlow/ViewModels/WorkoutScheduleViewModel.swift` | Auth, load, sections, selection rules, delete/clear |
| `AmakaFlow/Views/WorkoutScheduleView.swift` | UI |
| `AmakaFlow/Views/DevicesView.swift` | Entry |
| `AmakaFlow/Views/UnifiedWorkoutDetailView.swift` | Manage link |
| `AmakaFlow/Services/AppleStartHandoff.swift` | At-cap copy |
| `AmakaFlowCompanion/AmakaFlowCompanionTests/WorkoutScheduleViewModelTests.swift` | Unit tests |
| `AmakaFlowCompanion/AmakaFlowCompanionTests/AppleStartHandoffTests.swift` | Cap copy tests |
| `docs/ama-2287-visual-evidence/README.md` | Gaps + dogfood |

---

### Task 1: Protocol, identity, Mock, Live (+ plan cache)

**Files:**
- Create: `AmakaFlow/Services/WorkoutKitScheduleManaging.swift`
- Test: `AmakaFlowCompanion/AmakaFlowCompanionTests/WorkoutScheduleViewModelTests.swift`

**Interfaces:**
- Produces: `ScheduleAuthState`, `WorkoutScheduleRowID`, `WorkoutScheduleRow`, `WorkoutKitScheduleManaging`, `MockWorkoutKitScheduler`, `LiveWorkoutKitScheduler`

- [ ] **Step 1: Confirm SDK signatures**

Verify: `scheduledWorkouts`, `remove(_:at:)`, `removeAllWorkouts()`, `maxAllowedScheduledWorkoutCount`, `authorizationState`, `requestAuthorization()`, and the title property for list rows.

- [ ] **Step 2: Write failing identity + auth-shape tests**

```swift
import XCTest
@testable import AmakaFlowCompanion

final class WorkoutScheduleRowIDTests: XCTestCase {
    func testCanonicalKeyStableAcrossEqualComponents() {
        var a = DateComponents()
        a.year = 2026; a.month = 7; a.day = 27; a.hour = 10; a.minute = 5
        var b = DateComponents()
        b.year = 2026; b.month = 7; b.day = 27; b.hour = 10; b.minute = 5
        XCTAssertEqual(
            WorkoutScheduleRowID(planID: "p1", date: a),
            WorkoutScheduleRowID(planID: "p1", date: b)
        )
    }

    func testCanonicalKeyDiffersWhenMinuteDiffers() {
        var a = DateComponents()
        a.year = 2026; a.month = 7; a.day = 27; a.hour = 10; a.minute = 5
        var b = DateComponents()
        b.year = 2026; b.month = 7; b.day = 27; b.hour = 10; b.minute = 6
        XCTAssertNotEqual(
            WorkoutScheduleRowID(planID: "p1", date: a),
            WorkoutScheduleRowID(planID: "p1", date: b)
        )
    }

    func testOptionalCalendarIncludedOnlyWhenPresent() {
        var withCal = DateComponents()
        withCal.year = 2026; withCal.month = 7; withCal.day = 27
        withCal.calendar = Calendar(identifier: .gregorian)
        var without = DateComponents()
        without.year = 2026; without.month = 7; without.day = 27
        XCTAssertNotEqual(
            WorkoutScheduleRowID.canonicalDateKey(withCal),
            WorkoutScheduleRowID.canonicalDateKey(without)
        )
    }
}
```

- [ ] **Step 3: Run — expect compile fail**

```bash
cd /Users/davidandrews/dev/amakaflow-workspace/amakaflow-ios-app
xcodebuild test -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:AmakaFlowCompanionTests/WorkoutScheduleRowIDTests 2>&1 | tail -40
```

- [ ] **Step 4: Implement protocol + Mock + Live**

```swift
import Foundation
#if canImport(WorkoutKit)
import WorkoutKit
#endif

enum ScheduleAuthState: Equatable, Sendable {
    case authorized, denied, notDetermined
}

struct WorkoutScheduleRowID: Hashable, Sendable {
    let planID: String
    let dateKey: String

    init(planID: String, date: DateComponents) {
        self.planID = planID
        self.dateKey = Self.canonicalDateKey(date)
    }

    static func canonicalDateKey(_ date: DateComponents) -> String {
        var parts: [String] = [
            "y=\(date.year.map(String.init) ?? "")",
            "m=\(date.month.map(String.init) ?? "")",
            "d=\(date.day.map(String.init) ?? "")",
            "H=\(date.hour.map(String.init) ?? "")",
            "M=\(date.minute.map(String.init) ?? "")",
            "S=\(date.second.map(String.init) ?? "")",
            "n=\(date.nanosecond.map(String.init) ?? "")"
        ]
        if let calendar = date.calendar {
            parts.append("cal=\(calendar.identifier)")
        }
        if let timeZone = date.timeZone {
            parts.append("tz=\(timeZone.identifier)")
        }
        return parts.joined(separator: "|")
    }
}

struct WorkoutScheduleRow: Identifiable, Equatable, Sendable {
    let id: WorkoutScheduleRowID
    let title: String
    let dateComponents: DateComponents
    let scheduledAt: Date?
    let isComplete: Bool
}

protocol WorkoutKitScheduleManaging: Sendable {
    var authorizationState: ScheduleAuthState { get async }
    var maxAllowedCount: Int { get }
    func requestAuthorization() async -> ScheduleAuthState
    func fetchScheduledRows() async throws -> [WorkoutScheduleRow]
    func remove(row: WorkoutScheduleRow) async
    func removeAll() async
}

final class MockWorkoutKitScheduler: WorkoutKitScheduleManaging, @unchecked Sendable {
    var authState: ScheduleAuthState = .authorized
    var rows: [WorkoutScheduleRow] = []
    var maxAllowedCount: Int = 15
    var removeCallRows: [WorkoutScheduleRow] = []
    var removeAllCallCount = 0
    var noopRemoveIDs: Set<WorkoutScheduleRowID> = []
    var fetchError: Error?
    var requestAuthorizationCallCount = 0

    var authorizationState: ScheduleAuthState {
        get async { authState }
    }

    func requestAuthorization() async -> ScheduleAuthState {
        requestAuthorizationCallCount += 1
        return authState
    }

    func fetchScheduledRows() async throws -> [WorkoutScheduleRow] {
        if let fetchError { throw fetchError }
        return rows
    }

    func remove(row: WorkoutScheduleRow) async {
        removeCallRows.append(row)
        guard !noopRemoveIDs.contains(row.id) else { return }
        rows.removeAll { $0.id == row.id }
    }

    func removeAll() async {
        removeAllCallCount += 1
        rows = []
    }
}

#if canImport(WorkoutKit)
@available(iOS 18.0, *)
final class LiveWorkoutKitScheduler: WorkoutKitScheduleManaging, @unchecked Sendable {
    private let calendar: Calendar
    private var planCache: [WorkoutScheduleRowID: WorkoutPlan] = [:]

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    var maxAllowedCount: Int {
        WorkoutScheduler.maxAllowedScheduledWorkoutCount
    }

    var authorizationState: ScheduleAuthState {
        get async {
            switch await WorkoutScheduler.shared.authorizationState {
            case .authorized: return .authorized
            case .denied: return .denied
            default: return .notDetermined
            }
        }
    }

    func requestAuthorization() async -> ScheduleAuthState {
        let result = await WorkoutScheduler.shared.requestAuthorization()
        switch result {
        case .authorized: return .authorized
        case .denied: return .denied
        default: return .notDetermined
        }
    }

    func fetchScheduledRows() async throws -> [WorkoutScheduleRow] {
        let scheduled = await WorkoutScheduler.shared.scheduledWorkouts
        if scheduled.count >= maxAllowedCount {
            print("WorkoutKitSchedule: at Apple schedule cap (\(scheduled.count)/\(maxAllowedCount))")
        }
        var cache: [WorkoutScheduleRowID: WorkoutPlan] = [:]
        let rows: [WorkoutScheduleRow] = scheduled.map { item in
            let planID = String(describing: item.plan.id)
            let id = WorkoutScheduleRowID(planID: planID, date: item.date)
            cache[id] = item.plan
            // Title: replace with SDK display property confirmed in Step 1.
            let title = String(describing: item.plan)
            return WorkoutScheduleRow(
                id: id,
                title: title,
                dateComponents: item.date,
                scheduledAt: calendar.date(from: item.date),
                isComplete: item.complete
            )
        }
        planCache = cache
        return rows
    }

    func remove(row: WorkoutScheduleRow) async {
        guard let plan = planCache[row.id] else { return }
        await WorkoutScheduler.shared.remove(plan, at: row.dateComponents)
    }

    func removeAll() async {
        await WorkoutScheduler.shared.removeAllWorkouts()
        planCache = [:]
    }
}
#endif
```

Add file to the same targets as `AppleStartHandoff.swift`.

- [ ] **Step 5: Identity tests PASS**

- [ ] **Step 6: Commit**

```bash
git add AmakaFlow/Services/WorkoutKitScheduleManaging.swift \
  AmakaFlowCompanion/AmakaFlowCompanionTests/WorkoutScheduleViewModelTests.swift
git commit -m "$(cat <<'EOF'
feat(AMA-2330): add WorkoutKit schedule manage protocol with auth and cache

Non-throwing remove; Live caches WorkoutPlan by row id from last fetch.
EOF
)"
```

---

### Task 2: ViewModel — auth, load, sections, manual refresh

**Files:**
- Create: `AmakaFlow/ViewModels/WorkoutScheduleViewModel.swift`
- Modify: `AmakaFlowCompanion/AmakaFlowCompanionTests/WorkoutScheduleViewModelTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
@MainActor
final class WorkoutScheduleViewModelTests: XCTestCase {
    private func row(
        id: String,
        title: String,
        minutesAgo: Int,
        complete: Bool = false
    ) -> WorkoutScheduleRow {
        let date = Calendar.current.date(byAdding: .minute, value: -minutesAgo, to: Date())!
        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        return WorkoutScheduleRow(
            id: WorkoutScheduleRowID(planID: id, date: comps),
            title: title,
            dateComponents: comps,
            scheduledAt: date,
            isComplete: complete
        )
    }

    func testDeniedAuthShowsBannerNotEmptyState() async {
        let mock = MockWorkoutKitScheduler()
        mock.authState = .denied
        mock.rows = []
        let vm = WorkoutScheduleViewModel(scheduler: mock)
        await vm.refresh(mode: .manual)
        XCTAssertTrue(vm.authDenied)
        XCTAssertFalse(vm.showEmptyState)
    }

    func testAuthorizedEmptyShowsEmptyState() async {
        let mock = MockWorkoutKitScheduler()
        mock.authState = .authorized
        mock.rows = []
        let vm = WorkoutScheduleViewModel(scheduler: mock)
        await vm.refresh(mode: .manual)
        XCTAssertFalse(vm.authDenied)
        XCTAssertTrue(vm.showEmptyState)
    }

    func testNotDeterminedRequestsAuthorization() async {
        let mock = MockWorkoutKitScheduler()
        mock.authState = .notDetermined
        let vm = WorkoutScheduleViewModel(scheduler: mock)
        await vm.refresh(mode: .manual)
        XCTAssertEqual(mock.requestAuthorizationCallCount, 1)
    }

    func testRefreshSortsNewestFirstAndSectionsCompleted() async {
        let mock = MockWorkoutKitScheduler()
        mock.rows = [
            row(id: "old", title: "A", minutesAgo: 120),
            row(id: "new", title: "B", minutesAgo: 5),
            row(id: "done", title: "C", minutesAgo: 1, complete: true)
        ]
        let vm = WorkoutScheduleViewModel(scheduler: mock)
        await vm.refresh(mode: .manual)
        XCTAssertEqual(vm.incompleteRows.map(\.title), ["B", "A"])
        XCTAssertEqual(vm.completedRows.map(\.title), ["C"])
    }

    func testManualRefreshClearsSelectionAndExitsEditing() async {
        let mock = MockWorkoutKitScheduler()
        let r = row(id: "1", title: "Hyrox", minutesAgo: 10)
        mock.rows = [r]
        let vm = WorkoutScheduleViewModel(scheduler: mock)
        await vm.refresh(mode: .manual)
        vm.enterEditing()
        vm.toggleSelect(r.id)
        await vm.refresh(mode: .manual)
        XCTAssertFalse(vm.isEditing)
        XCTAssertTrue(vm.selectedIDs.isEmpty)
    }
}
```

- [ ] **Step 2: Run — expect fail**

- [ ] **Step 3: Implement ViewModel (auth + load)**

```swift
import Foundation

enum WorkoutScheduleRefreshMode {
    case manual
    case afterMutation(attempted: Set<WorkoutScheduleRowID>)
}

@MainActor
final class WorkoutScheduleViewModel: ObservableObject {
    @Published private(set) var incompleteRows: [WorkoutScheduleRow] = []
    @Published private(set) var completedRows: [WorkoutScheduleRow] = []
    @Published var selectedIDs: Set<WorkoutScheduleRowID> = []
    @Published var isEditing = false
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var authDenied = false
    @Published private(set) var showEmptyState = false

    private let scheduler: any WorkoutKitScheduleManaging
    private var rowsByID: [WorkoutScheduleRowID: WorkoutScheduleRow] = [:]

    init(scheduler: any WorkoutKitScheduleManaging) {
        self.scheduler = scheduler
    }

    var selectedCount: Int { selectedIDs.count }

    func enterEditing() { isEditing = true }
    func exitEditing() {
        isEditing = false
        selectedIDs = []
    }

    func toggleSelect(_ id: WorkoutScheduleRowID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) }
        else { selectedIDs.insert(id) }
    }

    func refresh(mode: WorkoutScheduleRefreshMode = .manual) async {
        isLoading = true
        defer { isLoading = false }

        var auth = await scheduler.authorizationState
        if auth == .notDetermined {
            auth = await scheduler.requestAuthorization()
        }
        authDenied = (auth == .denied)
        if authDenied {
            incompleteRows = []
            completedRows = []
            showEmptyState = false
            selectedIDs = []
            isEditing = false
            return
        }

        do {
            let rows = try await scheduler.fetchScheduledRows()
            let sorted = rows.sorted {
                ($0.scheduledAt ?? .distantPast) > ($1.scheduledAt ?? .distantPast)
            }
            incompleteRows = sorted.filter { !$0.isComplete }
            completedRows = sorted.filter(\.isComplete)
            rowsByID = Dictionary(uniqueKeysWithValues: sorted.map { ($0.id, $0) })
            showEmptyState = sorted.isEmpty

            switch mode {
            case .manual:
                selectedIDs = []
                isEditing = false
                statusMessage = nil
            case .afterMutation(let attempted):
                let failed = attempted.intersection(Set(rowsByID.keys))
                selectedIDs = failed
                isEditing = !failed.isEmpty
                let removed = attempted.count - failed.count
                if failed.isEmpty {
                    statusMessage = removed == 1 ? "Removed 1 plan." : "Removed \(removed) plans."
                } else {
                    statusMessage = "Removed \(removed) of \(attempted.count); tap to retry"
                }
            }
        } catch {
            statusMessage = error.localizedDescription
            showEmptyState = false
        }
    }
}
```

- [ ] **Step 4: Run — PASS**

- [ ] **Step 5: Commit**

```bash
git add AmakaFlow/ViewModels/WorkoutScheduleViewModel.swift \
  AmakaFlowCompanion/AmakaFlowCompanionTests/WorkoutScheduleViewModelTests.swift
git commit -m "$(cat <<'EOF'
feat(AMA-2330): WorkoutScheduleViewModel auth and list sections

Denied vs empty distinguished via authorizationState; manual refresh clears selection.
EOF
)"
```

---

### Task 3: deleteSelected / clearAll (still-present detection)

**Files:**
- Modify: `AmakaFlow/ViewModels/WorkoutScheduleViewModel.swift`
- Modify: `AmakaFlowCompanion/AmakaFlowCompanionTests/WorkoutScheduleViewModelTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
func testDeleteSelectedPassesExactStoredDateComponents_mockLevel() async {
    // Mock-level passthrough. Live plan+date → remove(_:at:) is code review + dogfood.
    let mock = MockWorkoutKitScheduler()
    let r = row(id: "1", title: "Hyrox", minutesAgo: 3)
    mock.rows = [r]
    let vm = WorkoutScheduleViewModel(scheduler: mock)
    await vm.refresh(mode: .manual)
    vm.enterEditing()
    vm.toggleSelect(r.id)
    await vm.deleteSelected()
    XCTAssertEqual(mock.removeCallRows.map(\.id), [r.id])
    XCTAssertEqual(mock.removeCallRows.first?.dateComponents, r.dateComponents)
    XCTAssertTrue(vm.incompleteRows.isEmpty)
}

func testEmptySelectionDoesNotCallRemove() async {
    let mock = MockWorkoutKitScheduler()
    mock.rows = [row(id: "1", title: "A", minutesAgo: 1)]
    let vm = WorkoutScheduleViewModel(scheduler: mock)
    await vm.refresh(mode: .manual)
    await vm.deleteSelected()
    XCTAssertTrue(mock.removeCallRows.isEmpty)
}

func testClearAllCallsRemoveAllOnce() async {
    let mock = MockWorkoutKitScheduler()
    mock.rows = [
        row(id: "1", title: "A", minutesAgo: 1),
        row(id: "2", title: "B", minutesAgo: 2)
    ]
    let vm = WorkoutScheduleViewModel(scheduler: mock)
    await vm.refresh(mode: .manual)
    await vm.clearAll()
    XCTAssertEqual(mock.removeAllCallCount, 1)
}

func testSilentNoOpRemoveKeepsStillPresentIDsSelected() async {
    let mock = MockWorkoutKitScheduler()
    let a = row(id: "a", title: "A", minutesAgo: 1)
    let b = row(id: "b", title: "B", minutesAgo: 2)
    let c = row(id: "c", title: "C", minutesAgo: 3)
    mock.rows = [a, b, c]
    mock.noopRemoveIDs = [b.id]
    let vm = WorkoutScheduleViewModel(scheduler: mock)
    await vm.refresh(mode: .manual)
    vm.enterEditing()
    [a, b, c].forEach { vm.toggleSelect($0.id) }
    await vm.deleteSelected()
    XCTAssertEqual(vm.selectedIDs, [b.id])
    XCTAssertTrue(vm.isEditing)
    XCTAssertTrue(vm.statusMessage?.contains("Removed 2 of 3") == true)
}

func testRetryOnlyTargetsIDsStillPresent() async {
    let mock = MockWorkoutKitScheduler()
    let a = row(id: "a", title: "A", minutesAgo: 1)
    let b = row(id: "b", title: "B", minutesAgo: 2)
    mock.rows = [a, b]
    mock.noopRemoveIDs = [b.id]
    let vm = WorkoutScheduleViewModel(scheduler: mock)
    await vm.refresh(mode: .manual)
    vm.enterEditing()
    vm.toggleSelect(a.id)
    vm.toggleSelect(b.id)
    await vm.deleteSelected()
    mock.noopRemoveIDs = []
    mock.removeCallRows = []
    await vm.deleteSelected()
    XCTAssertEqual(mock.removeCallRows.map(\.id), [b.id])
    XCTAssertTrue(vm.selectedIDs.isEmpty)
}
```

- [ ] **Step 2: Run — expect fail**

- [ ] **Step 3: Implement**

```swift
func delete(row: WorkoutScheduleRow) async {
    selectedIDs = [row.id]
    isEditing = true
    await deleteSelected()
}

func deleteSelected() async {
    let targets = selectedIDs.compactMap { rowsByID[$0] }
    guard !targets.isEmpty else { return }
    let attempted = Set(targets.map(\.id))
    for target in targets {
        await scheduler.remove(row: target)
    }
    await refresh(mode: .afterMutation(attempted: attempted))
}

func clearAll() async {
    await scheduler.removeAll()
    await refresh(mode: .manual)
    if showEmptyState {
        statusMessage = "Removed all AmakaFlow plans."
    }
}
```

- [ ] **Step 4: Run — PASS**

- [ ] **Step 5: Commit**

```bash
git add AmakaFlow/ViewModels/WorkoutScheduleViewModel.swift \
  AmakaFlowCompanion/AmakaFlowCompanionTests/WorkoutScheduleViewModelTests.swift
git commit -m "$(cat <<'EOF'
feat(AMA-2330): still-present delete reconciliation in schedule VM

Non-throwing removes; retry keeps attempted ∩ present after refresh.
EOF
)"
```

---

### Task 4: `WorkoutScheduleView`

**Files:**
- Create: `AmakaFlow/Views/WorkoutScheduleView.swift`

- [ ] **Step 1: Implement UI** per spec (auth banner → Settings, empty only when `showEmptyState`, Scheduled + Completed sections, footnote, confirms, Delete (N) / Clear all, tap status to retry). Use `LiveWorkoutKitScheduler` on iOS 18+ in the default init.

- [ ] **Step 2: Build SUCCEEDED**

```bash
xcodebuild build -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30
```

- [ ] **Step 3: Commit**

```bash
git add AmakaFlow/Views/WorkoutScheduleView.swift
git commit -m "$(cat <<'EOF'
feat(AMA-2330): add WorkoutScheduleView for multi-select cleanup

Auth banner, Completed section, relative times, Watch sync footnote.
EOF
)"
```

---

### Task 5: Navigation + at-cap Start

**Files:**
- Modify: `AmakaFlow/Views/DevicesView.swift`
- Modify: `AmakaFlow/Views/UnifiedWorkoutDetailView.swift`
- Modify: `AmakaFlow/Services/AppleStartHandoff.swift`
- Modify: `AmakaFlowCompanion/AmakaFlowCompanionTests/AppleStartHandoffTests.swift`

- [ ] **Step 1:** Devices row behind `#available(iOS 18.0, *)` only (hide otherwise).
- [ ] **Step 2:** Start success → **Manage scheduled plans** → same screen.
- [ ] **Step 3:** `scheduleCapReached` failure code + preflight using `maxAllowedScheduledWorkoutCount` / scheduled count. Unit-test copy.
- [ ] **Step 4:** Tests PASS.
- [ ] **Step 5:** Commit.

```bash
git commit -m "$(cat <<'EOF'
feat(AMA-2330): wire schedule cleanup entry points and at-cap Start

Devices + Start Manage link; preflight when Apple schedule cap is full.
EOF
)"
```

---

### Task 6: Gaps README

**Files:**
- Modify: `docs/ama-2287-visual-evidence/README.md`

- [ ] **Step 1:** Point duplicates at AMA-2330 cleanup; add Watch-lag, at-cap, and **completed-counts-toward-cap?** dogfood steps.
- [ ] **Step 2:** Commit.

```bash
git commit -m "$(cat <<'EOF'
docs(AMA-2330): point duplicates gap at schedule cleanup screen

Add Watch-lag, at-cap, and completed-vs-cap dogfood steps.
EOF
)"
```

---

## Self-review

| Spec | Task |
| --- | --- |
| Non-throwing remove + still-present | Tasks 1, 3 |
| Auth state vs empty | Tasks 1–2, 4 |
| Live plan cache | Task 1 |
| Mock-level DateComponents assert | Task 3 |
| Completed section | Tasks 2, 4 |
| Hide pre-iOS 18 | Task 5 |
| Manage link + at-cap | Task 5 |
| Gaps dogfood | Task 6 |

---

## Execution handoff

Plan complete at `docs/superpowers/plans/2026-07-27-apple-workoutkit-scheduled-plans-cleanup.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — fresh subagent per task  
2. **Inline Execution** — this session with checkpoints  

Which approach?
