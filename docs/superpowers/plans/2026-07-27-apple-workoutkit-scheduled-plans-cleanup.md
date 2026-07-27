# Scheduled WorkoutKit plan cleanup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users list and delete AmakaFlow-scheduled WorkoutKit plans on iPhone (multi-select, swipe, Clear all) without changing Start’s keep-adding behavior.

**Architecture:** Mirror `WorkoutKitSaving` with `WorkoutKitScheduleManaging` (Live → `WorkoutScheduler`, Mock for tests). `WorkoutScheduleViewModel` owns list ordering, selection, refresh-clears-selection, and partial-failure retry. UI is `WorkoutScheduleView`, entered from Devices and from the Start success status “Manage scheduled plans” link. Cap awareness uses `WorkoutScheduler.maxAllowedScheduledWorkoutCount`.

**Tech Stack:** Swift, SwiftUI, WorkoutKit (iOS 18+), XCTest

**Spec:** `docs/superpowers/specs/2026-07-27-apple-workoutkit-scheduled-plans-cleanup-design.md`  
**Linear:** AMA-2330 (parent AMA-2287)

## Global Constraints

- Start **keeps adding** — never call `remove` / `removeAllWorkouts` inside `AppleStartHandoffService.handoff` or `LiveWorkoutKitSaver` except optional **preflight fail** when already at cap (no auto-delete to make room).
- User-facing brand is **AmakaFlow** — never “AmakaFlowCompanion” in UI copy.
- Destination name is **Workout** / **Apple Watch Workout** — not “Apple Fitness”.
- Live adapter and UI gated `@available(iOS 18.0, *)` (same floor as Start).
- Remove always uses **fetched** `ScheduledWorkoutPlan.plan` + `.date` — never recompute “now”.
- Apple API to call: `remove(_ workout: WorkoutPlan, at: DateComponents) async` (verify against SDK in Task 1).
- Soften cap language: use `maxAllowedScheduledWorkoutCount`; do not hardcode `15` in user copy.
- Pull-to-refresh / successful reload: **clear selection and exit edit mode** (except after partial-failure retry staging — selection becomes failed IDs only).
- V1: protocol lives in the app; do **not** add list/remove to `workoutkit-sync` yet.
- Garmin / AmakaFlowWatch / composition export (AMA-2329): do not modify.

---

## File Structure

| File | Responsibility |
| ---- | -------------- |
| `AmakaFlow/Services/WorkoutKitScheduleManaging.swift` | Protocol, row identity helpers, Live + types used by VM |
| `AmakaFlow/ViewModels/WorkoutScheduleViewModel.swift` | Load/sort/select/delete/clear/refresh/retry |
| `AmakaFlow/Views/WorkoutScheduleView.swift` | SwiftUI list, edit mode, confirms, footnote, auth banner |
| `AmakaFlow/Views/DevicesView.swift` | Entry row → push/sheet schedule screen |
| `AmakaFlow/Views/UnifiedWorkoutDetailView.swift` | Manage link after Apple Start success |
| `AmakaFlow/Services/AppleStartHandoff.swift` | Optional at-cap failure code + copy; Manage affordance does not require message change |
| `AmakaFlowCompanion/AmakaFlowCompanionTests/WorkoutScheduleViewModelTests.swift` | Unit tests with mock scheduler |
| `AmakaFlowCompanion/AmakaFlowCompanionTests/AppleStartHandoffTests.swift` | At-cap / manage-related copy tests if Task 5 adds them |
| `docs/ama-2287-visual-evidence/README.md` | Duplicates gap → cleanup screen; at-cap + Watch-lag dogfood |

**Leave alone:** `workoutkit-sync` package sources, Garmin handoff, AmakaFlowWatch, Start schedule path except optional preflight.

---

### Task 1: Protocol + Mock + row identity

**Files:**
- Create: `AmakaFlow/Services/WorkoutKitScheduleManaging.swift`
- Test: `AmakaFlowCompanion/AmakaFlowCompanionTests/WorkoutScheduleViewModelTests.swift` (start with identity + mock tests; VM in Task 2)

**Interfaces:**
- Produces:
  - `struct WorkoutScheduleRowID: Hashable, Sendable`
  - `struct WorkoutScheduleRow: Identifiable, Equatable, Sendable` with `id`, `title`, `dateComponents`, `scheduledAt: Date?`, `isComplete`, and opaque `removalPlan` handle for Live
  - `protocol WorkoutKitScheduleManaging: Sendable` with `fetchScheduledRows()`, `remove(row:)`, `removeAll()`, `maxAllowedCount`
  - `final class MockWorkoutKitScheduler: WorkoutKitScheduleManaging` (test target or internal for `@testable`)
  - `@available(iOS 18.0, *) struct LiveWorkoutKitScheduler: WorkoutKitScheduleManaging`

- [ ] **Step 1: Confirm SDK signatures in Xcode / docs**

Open Apple docs or Xcode Jump to Definition for `WorkoutScheduler`:

- `scheduledWorkouts: [ScheduledWorkoutPlan] { get async }`
- `remove(_ workout: WorkoutPlan, at: DateComponents) async`
- `removeAllWorkouts() async`
- `static let maxAllowedScheduledWorkoutCount: Int`

If the local SDK uses different argument labels, update this plan’s Live adapter to match **before** writing production code. Expected call site:

```swift
await WorkoutScheduler.shared.remove(scheduled.plan, at: scheduled.date)
```

- [ ] **Step 2: Write failing identity tests**

Add `AmakaFlowCompanion/AmakaFlowCompanionTests/WorkoutScheduleViewModelTests.swift` (or a small `WorkoutScheduleRowIDTests` class in that file):

```swift
import XCTest
@testable import AmakaFlowCompanion

final class WorkoutScheduleRowIDTests: XCTestCase {
    func testRowIDIsStableForSamePlanAndDateComponents() {
        var a = DateComponents()
        a.year = 2026; a.month = 7; a.day = 27; a.hour = 10; a.minute = 5
        var b = DateComponents()
        b.year = 2026; b.month = 7; b.day = 27; b.hour = 10; b.minute = 5
        let id1 = WorkoutScheduleRowID(planID: "plan-1", date: a)
        let id2 = WorkoutScheduleRowID(planID: "plan-1", date: b)
        XCTAssertEqual(id1, id2)
        XCTAssertEqual(id1.hashValue, id2.hashValue)
    }

    func testRowIDDiffersWhenMinuteDiffers() {
        var a = DateComponents()
        a.year = 2026; a.month = 7; a.day = 27; a.hour = 10; a.minute = 5
        var b = DateComponents()
        b.year = 2026; b.month = 7; b.day = 27; b.hour = 10; b.minute = 6
        XCTAssertNotEqual(
            WorkoutScheduleRowID(planID: "plan-1", date: a),
            WorkoutScheduleRowID(planID: "plan-1", date: b)
        )
    }
}
```

- [ ] **Step 3: Run tests — expect fail (types missing)**

```bash
cd /Users/davidandrews/dev/amakaflow-workspace/amakaflow-ios-app
xcodebuild test -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:AmakaFlowCompanionTests/WorkoutScheduleRowIDTests 2>&1 | tail -40
```

Expected: compile failure — `WorkoutScheduleRowID` not found.

- [ ] **Step 4: Implement protocol + identity + Mock (+ Live stub)**

Create `AmakaFlow/Services/WorkoutKitScheduleManaging.swift`:

```swift
import Foundation
#if canImport(WorkoutKit)
import WorkoutKit
#endif

struct WorkoutScheduleRowID: Hashable, Sendable {
    let planID: String
    let dateKey: String

    init(planID: String, date: DateComponents) {
        self.planID = planID
        self.dateKey = Self.canonicalDateKey(date)
    }

    /// Fixed field order so hashing is deterministic across refreshes.
    static func canonicalDateKey(_ date: DateComponents) -> String {
        let fields: [(String, Int?)] = [
            ("y", date.year), ("m", date.month), ("d", date.day),
            ("H", date.hour), ("M", date.minute), ("S", date.second),
            ("n", date.nanosecond)
        ]
        return fields.map { key, value in
            "\(key)=\(value.map(String.init) ?? "")"
        }.joined(separator: "|")
    }
}

struct WorkoutScheduleRow: Identifiable, Equatable, Sendable {
    let id: WorkoutScheduleRowID
    let title: String
    let dateComponents: DateComponents
    let scheduledAt: Date?
    let isComplete: Bool
    /// Opaque token Live uses to recover `WorkoutPlan` for `remove`. Mock ignores.
    let removalToken: String
}

protocol WorkoutKitScheduleManaging: Sendable {
    func fetchScheduledRows() async throws -> [WorkoutScheduleRow]
    func remove(row: WorkoutScheduleRow) async throws
    func removeAll() async throws
    var maxAllowedCount: Int { get }
}

final class MockWorkoutKitScheduler: WorkoutKitScheduleManaging, @unchecked Sendable {
    var rows: [WorkoutScheduleRow] = []
    var maxAllowedCount: Int = 15
    var removeCallIDs: [WorkoutScheduleRowID] = []
    var removeAllCallCount = 0
    /// IDs that should throw on remove (for partial-failure tests).
    var failingRemoveIDs: Set<WorkoutScheduleRowID> = []
    var fetchError: Error?

    func fetchScheduledRows() async throws -> [WorkoutScheduleRow] {
        if let fetchError { throw fetchError }
        return rows
    }

    func remove(row: WorkoutScheduleRow) async throws {
        removeCallIDs.append(row.id)
        if failingRemoveIDs.contains(row.id) {
            throw NSError(domain: "MockScheduler", code: 1)
        }
        rows.removeAll { $0.id == row.id }
    }

    func removeAll() async throws {
        removeAllCallCount += 1
        rows = []
    }
}

#if canImport(WorkoutKit)
@available(iOS 18.0, *)
struct LiveWorkoutKitScheduler: WorkoutKitScheduleManaging {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    var maxAllowedCount: Int {
        WorkoutScheduler.maxAllowedScheduledWorkoutCount
    }

    func fetchScheduledRows() async throws -> [WorkoutScheduleRow] {
        let scheduled = await WorkoutScheduler.shared.scheduledWorkouts
        if scheduled.count >= maxAllowedCount {
            // Dogfood signal — intentional log, not user-facing.
            print("WorkoutKitSchedule: at Apple schedule cap (\(scheduled.count)/\(maxAllowedCount))")
        }
        return scheduled.map { item in
            let planID = String(describing: item.plan.id)
            let scheduledAt = calendar.date(from: item.date)
            return WorkoutScheduleRow(
                id: WorkoutScheduleRowID(planID: planID, date: item.date),
                title: item.plan.workout.displayName, // adjust if SDK property differs — verify in Step 1
                dateComponents: item.date,
                scheduledAt: scheduledAt,
                isComplete: item.complete,
                removalToken: planID
            )
        }
    }

    func remove(row: WorkoutScheduleRow) async throws {
        let scheduled = await WorkoutScheduler.shared.scheduledWorkouts
        guard let match = scheduled.first(where: {
            WorkoutScheduleRowID(planID: String(describing: $0.plan.id), date: $0.date) == row.id
        }) else { return }
        await WorkoutScheduler.shared.remove(match.plan, at: match.date)
    }

    func removeAll() async throws {
        await WorkoutScheduler.shared.removeAllWorkouts()
    }
}
#endif
```

**Note:** `item.plan.workout.displayName` may need adjustment after SDK check — use whatever title property `WorkoutPlan` exposes (often via associated workout). Prefer the same title users see on Watch. If Live cannot resolve title, fall back to `"Workout"`.

Add the new Swift file to the AmakaFlow / AmakaFlowCompanion target in Xcode (or Package/project membership consistent with `AppleStartHandoff.swift`).

- [ ] **Step 5: Run identity tests — expect pass**

Same `xcodebuild` command as Step 3. Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add AmakaFlow/Services/WorkoutKitScheduleManaging.swift \
  AmakaFlowCompanion/AmakaFlowCompanionTests/WorkoutScheduleViewModelTests.swift
git commit -m "$(cat <<'EOF'
feat(AMA-2330): add WorkoutKit schedule manage protocol and mock

Stable row IDs and Live/Mock seams for scheduled plan cleanup.
EOF
)"
```

---

### Task 2: ViewModel — load, sort, select, refresh clears selection

**Files:**
- Create: `AmakaFlow/ViewModels/WorkoutScheduleViewModel.swift`
- Modify: `AmakaFlowCompanion/AmakaFlowCompanionTests/WorkoutScheduleViewModelTests.swift`

**Interfaces:**
- Consumes: `WorkoutKitScheduleManaging`, `WorkoutScheduleRow`, `WorkoutScheduleRowID`
- Produces: `@MainActor final class WorkoutScheduleViewModel` with
  - `rows`, `incompleteRows`, `completedRows`
  - `selectedIDs`, `isEditing`, `isLoading`, `statusMessage`, `authDenied`
  - `func refresh()`, `func toggleSelect(_:)`, `func enterEditing()`, `func exitEditing()`

- [ ] **Step 1: Write failing ViewModel tests**

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
            isComplete: complete,
            removalToken: id
        )
    }

    func testRefreshSortsNewestFirstAndSectionsCompleted() async {
        let mock = MockWorkoutKitScheduler()
        mock.rows = [
            row(id: "old", title: "A", minutesAgo: 120, complete: false),
            row(id: "new", title: "B", minutesAgo: 5, complete: false),
            row(id: "done", title: "C", minutesAgo: 1, complete: true)
        ]
        let vm = WorkoutScheduleViewModel(scheduler: mock)
        await vm.refresh()
        XCTAssertEqual(vm.incompleteRows.map(\.title), ["B", "A"])
        XCTAssertEqual(vm.completedRows.map(\.title), ["C"])
    }

    func testRefreshClearsSelectionAndExitsEditing() async {
        let mock = MockWorkoutKitScheduler()
        let r = row(id: "1", title: "Hyrox", minutesAgo: 10)
        mock.rows = [r]
        let vm = WorkoutScheduleViewModel(scheduler: mock)
        await vm.refresh()
        vm.enterEditing()
        vm.toggleSelect(r.id)
        XCTAssertTrue(vm.isEditing)
        XCTAssertEqual(vm.selectedIDs, [r.id])
        await vm.refresh()
        XCTAssertFalse(vm.isEditing)
        XCTAssertTrue(vm.selectedIDs.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests — expect fail**

```bash
xcodebuild test -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:AmakaFlowCompanionTests/WorkoutScheduleViewModelTests 2>&1 | tail -40
```

Expected: `WorkoutScheduleViewModel` not found.

- [ ] **Step 3: Implement ViewModel (load/sort/select only)**

```swift
import Foundation

@MainActor
final class WorkoutScheduleViewModel: ObservableObject {
    @Published private(set) var incompleteRows: [WorkoutScheduleRow] = []
    @Published private(set) var completedRows: [WorkoutScheduleRow] = []
    @Published var selectedIDs: Set<WorkoutScheduleRowID> = []
    @Published var isEditing = false
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var authDenied = false

    private let scheduler: any WorkoutKitScheduleManaging
    private var rowsByID: [WorkoutScheduleRowID: WorkoutScheduleRow] = [:]
    /// When true, next refresh preserves selectedIDs (partial-failure path sets this).
    private var preserveSelectionOnNextRefresh = false

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

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let rows = try await scheduler.fetchScheduledRows()
            let sorted = rows.sorted { lhs, rhs in
                (lhs.scheduledAt ?? .distantPast) > (rhs.scheduledAt ?? .distantPast)
            }
            incompleteRows = sorted.filter { !$0.isComplete }
            completedRows = sorted.filter(\.isComplete)
            rowsByID = Dictionary(uniqueKeysWithValues: sorted.map { ($0.id, $0) })
            if preserveSelectionOnNextRefresh {
                preserveSelectionOnNextRefresh = false
                selectedIDs = selectedIDs.filter { rowsByID[$0] != nil }
            } else {
                selectedIDs = []
                isEditing = false
            }
            statusMessage = nil
            authDenied = false
        } catch {
            // Map authorization-style errors to banner; keep list as-is.
            authDenied = error.localizedDescription.lowercased().contains("authoriz")
                || error.localizedDescription.lowercased().contains("denied")
            statusMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 4: Run ViewModel tests — expect pass**

Same command as Step 2. Expected: PASS for sort + refresh-clears-selection.

- [ ] **Step 5: Commit**

```bash
git add AmakaFlow/ViewModels/WorkoutScheduleViewModel.swift \
  AmakaFlowCompanion/AmakaFlowCompanionTests/WorkoutScheduleViewModelTests.swift
git commit -m "$(cat <<'EOF'
feat(AMA-2330): add WorkoutScheduleViewModel load and selection rules

Newest-first list; refresh clears selection and exits edit mode.
EOF
)"
```

---

### Task 3: ViewModel — deleteSelected, clearAll, partial-failure retry

**Files:**
- Modify: `AmakaFlow/ViewModels/WorkoutScheduleViewModel.swift`
- Modify: `AmakaFlowCompanion/AmakaFlowCompanionTests/WorkoutScheduleViewModelTests.swift`

**Interfaces:**
- Produces: `deleteSelected()`, `delete(row:)`, `clearAll()`, `retryFailedDeletes()` (or retry = `deleteSelected` after failed IDs retained)

- [ ] **Step 1: Write failing delete / partial-failure tests**

```swift
func testDeleteSelectedCallsRemoveWithExactDateComponents() async {
    let mock = MockWorkoutKitScheduler()
    let r = row(id: "1", title: "Hyrox", minutesAgo: 3)
    mock.rows = [r]
    let vm = WorkoutScheduleViewModel(scheduler: mock)
    await vm.refresh()
    vm.enterEditing()
    vm.toggleSelect(r.id)
    await vm.deleteSelected()
    XCTAssertEqual(mock.removeCallIDs, [r.id])
    // Exact DateComponents from the row model — not recomputed "now"
    XCTAssertEqual(mock.rows, [])
}

func testEmptySelectionDoesNotCallRemove() async {
    let mock = MockWorkoutKitScheduler()
    mock.rows = [row(id: "1", title: "A", minutesAgo: 1)]
    let vm = WorkoutScheduleViewModel(scheduler: mock)
    await vm.refresh()
    await vm.deleteSelected()
    XCTAssertTrue(mock.removeCallIDs.isEmpty)
}

func testClearAllCallsRemoveAllOnce() async {
    let mock = MockWorkoutKitScheduler()
    mock.rows = [
        row(id: "1", title: "A", minutesAgo: 1),
        row(id: "2", title: "B", minutesAgo: 2)
    ]
    let vm = WorkoutScheduleViewModel(scheduler: mock)
    await vm.refresh()
    await vm.clearAll()
    XCTAssertEqual(mock.removeAllCallCount, 1)
    XCTAssertTrue(vm.incompleteRows.isEmpty)
}

func testPartialFailureKeepsOnlyFailedIDsSelected() async {
    let mock = MockWorkoutKitScheduler()
    let a = row(id: "a", title: "A", minutesAgo: 1)
    let b = row(id: "b", title: "B", minutesAgo: 2)
    let c = row(id: "c", title: "C", minutesAgo: 3)
    mock.rows = [a, b, c]
    mock.failingRemoveIDs = [b.id]
    let vm = WorkoutScheduleViewModel(scheduler: mock)
    await vm.refresh()
    vm.enterEditing()
    [a, b, c].forEach { vm.toggleSelect($0.id) }
    await vm.deleteSelected()
    XCTAssertEqual(vm.selectedIDs, [b.id])
    XCTAssertTrue(vm.isEditing)
    XCTAssertTrue(vm.statusMessage?.contains("Removed") == true)
}
```

- [ ] **Step 2: Run tests — expect fail** (methods missing)

- [ ] **Step 3: Implement delete / clear / partial failure**

Append to `WorkoutScheduleViewModel`:

```swift
func delete(row: WorkoutScheduleRow) async {
    selectedIDs = [row.id]
    isEditing = true
    await deleteSelected()
}

func deleteSelected() async {
    let targets = selectedIDs.compactMap { rowsByID[$0] }
    guard !targets.isEmpty else { return }
    var failed: Set<WorkoutScheduleRowID> = []
    var removed = 0
    for target in targets {
        do {
            try await scheduler.remove(row: target)
            removed += 1
        } catch {
            failed.insert(target.id)
        }
    }
    if failed.isEmpty {
        statusMessage = removed == 1 ? "Removed 1 plan." : "Removed \(removed) plans."
        selectedIDs = []
        isEditing = false
        await refresh()
    } else {
        let total = targets.count
        statusMessage = "Removed \(removed) of \(total); tap to retry"
        selectedIDs = failed
        isEditing = true
        preserveSelectionOnNextRefresh = true
        await refresh()
    }
}

func clearAll() async {
    do {
        try await scheduler.removeAll()
        statusMessage = "Removed all AmakaFlow plans."
        selectedIDs = []
        isEditing = false
        await refresh()
    } catch {
        statusMessage = error.localizedDescription
    }
}
```

- [ ] **Step 4: Run tests — expect pass**

- [ ] **Step 5: Commit**

```bash
git add AmakaFlow/ViewModels/WorkoutScheduleViewModel.swift \
  AmakaFlowCompanion/AmakaFlowCompanionTests/WorkoutScheduleViewModelTests.swift
git commit -m "$(cat <<'EOF'
feat(AMA-2330): delete, clear-all, and partial-failure retry in schedule VM

Failed IDs stay selected for one-tap retry after mixed remove results.
EOF
)"
```

---

### Task 4: `WorkoutScheduleView` UI

**Files:**
- Create: `AmakaFlow/Views/WorkoutScheduleView.swift`

**Interfaces:**
- Consumes: `WorkoutScheduleViewModel`
- Produces: SwiftUI screen with relative times, completed section, footnote, confirms

- [ ] **Step 1: Implement view**

```swift
import SwiftUI

struct WorkoutScheduleView: View {
    @StateObject private var viewModel: WorkoutScheduleViewModel
    @State private var confirmDelete = false
    @State private var confirmClearAll = false

    init(viewModel: WorkoutScheduleViewModel? = nil) {
        if let viewModel {
            _viewModel = StateObject(wrappedValue: viewModel)
        } else if #available(iOS 18.0, *) {
            _viewModel = StateObject(wrappedValue: WorkoutScheduleViewModel(scheduler: LiveWorkoutKitScheduler()))
        } else {
            _viewModel = StateObject(wrappedValue: WorkoutScheduleViewModel(scheduler: MockWorkoutKitScheduler()))
        }
    }

    var body: some View {
        List {
            if viewModel.authDenied {
                Section {
                    Text("Workout permission denied — Settings → Health → Data Access → AmakaFlow, allow Workouts.")
                        .font(.footnote)
                }
            }

            if viewModel.incompleteRows.isEmpty && viewModel.completedRows.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "No AmakaFlow plans in Workout",
                    systemImage: "figure.run",
                    description: Text("Start a workout to schedule one, or pull to refresh.")
                )
            }

            if !viewModel.incompleteRows.isEmpty {
                Section("Scheduled") {
                    ForEach(viewModel.incompleteRows) { row in
                        rowView(row)
                    }
                    .onDelete { indexSet in
                        Task {
                            for index in indexSet {
                                await viewModel.delete(row: viewModel.incompleteRows[index])
                            }
                        }
                    }
                }
            }

            if !viewModel.completedRows.isEmpty {
                Section("Completed") {
                    ForEach(viewModel.completedRows) { row in
                        rowView(row)
                            .opacity(0.55)
                    }
                    .onDelete { indexSet in
                        Task {
                            for index in indexSet {
                                await viewModel.delete(row: viewModel.completedRows[index])
                            }
                        }
                    }
                }
            }

            Section {
                Text("Changes may take a moment to appear on Apple Watch.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Schedule")
        .toolbar { toolbarContent }
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.refresh() }
        .confirmationDialog(
            "Remove \(viewModel.selectedCount) AmakaFlow workout plan(s) from Apple Watch Workout?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                Task { await viewModel.deleteSelected() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Remove all AmakaFlow plans from the Workout app? This can’t be undone — you can re-schedule any workout from its Start button.",
            isPresented: $confirmClearAll,
            titleVisibility: .visible
        ) {
            Button("Clear all", role: .destructive) {
                Task { await viewModel.clearAll() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .overlay(alignment: .bottom) {
            if let status = viewModel.statusMessage {
                Text(status)
                    .font(.caption)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .onTapGesture {
                        if status.contains("retry") {
                            Task { await viewModel.deleteSelected() }
                        }
                    }
            }
        }
        .accessibilityIdentifier("af_workout_schedule_screen")
    }

    @ViewBuilder
    private func rowView(_ row: WorkoutScheduleRow) -> some View {
        HStack {
            if viewModel.isEditing {
                Image(systemName: viewModel.selectedIDs.contains(row.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(DailyDriver.lime)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(Theme.Typography.body)
                Text(relativeLabel(for: row))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if viewModel.isEditing { viewModel.toggleSelect(row.id) }
        }
        .accessibilityIdentifier("af_workout_schedule_row")
    }

    private func relativeLabel(for row: WorkoutScheduleRow) -> String {
        guard let date = row.scheduledAt else { return "Scheduled time unknown" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Scheduled \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if viewModel.isEditing {
                Button("Done") { viewModel.exitEditing() }
            } else {
                Button("Select") { viewModel.enterEditing() }
                    .disabled(viewModel.incompleteRows.isEmpty && viewModel.completedRows.isEmpty)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            HStack {
                if !viewModel.incompleteRows.isEmpty || !viewModel.completedRows.isEmpty {
                    Button("Clear all", role: .destructive) { confirmClearAll = true }
                }
                if viewModel.isEditing, viewModel.selectedCount >= 1 {
                    Button("Delete (\(viewModel.selectedCount))", role: .destructive) {
                        confirmDelete = true
                    }
                }
            }
        }
    }
}
```

Match existing Daily Driver styling (`DailyDriver`, `Theme`) where the Devices screens do. Prefer `AFTopBar` only if Devices-style custom chrome is required for visual consistency when embedded; NavigationStack push with `navigationTitle` is fine when Devices already sits in a stack.

Wire the new file into the Xcode target.

- [ ] **Step 2: Build**

```bash
xcodebuild build -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30
```

Expected: BUILD SUCCEEDED. Fix compile errors (display name property, availability) before continuing.

- [ ] **Step 3: Commit**

```bash
git add AmakaFlow/Views/WorkoutScheduleView.swift
git commit -m "$(cat <<'EOF'
feat(AMA-2330): add WorkoutScheduleView for multi-select cleanup

Relative times, completed section, Clear all, and Watch sync footnote.
EOF
)"
```

---

### Task 5: Entry points — Devices + Start Manage link (+ optional at-cap)

**Files:**
- Modify: `AmakaFlow/Views/DevicesView.swift`
- Modify: `AmakaFlow/Views/UnifiedWorkoutDetailView.swift`
- Modify (optional): `AmakaFlow/Services/AppleStartHandoff.swift`
- Modify (optional): `AmakaFlowCompanion/AmakaFlowCompanionTests/AppleStartHandoffTests.swift`

**Interfaces:**
- Produces: Devices row; Start success “Manage scheduled plans”; optional `.scheduleCapReached` failure code

- [ ] **Step 1: Add Devices entry**

In `DevicesView.contentView` and `emptyView` (so Apple-only users still see it), add a row near `watchDisplayPrefsRow`:

```swift
private var scheduledWorkoutPlansRow: some View {
    Group {
        if #available(iOS 18.0, *) {
            NavigationLink {
                WorkoutScheduleView()
            } label: {
                AFCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Scheduled in Workout")
                            .afH2()
                        Text("Manage AmakaFlow plans on Apple Watch Workout.")
                            .afMuted()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("af_devices_scheduled_workout_plans")
        }
    }
}
```

Insert `scheduledWorkoutPlansRow` in both `contentView` and `emptyView` scroll stacks.

- [ ] **Step 2: Add Start success Manage link**

In `UnifiedWorkoutDetailView`:

1. Track Apple handoff kind, e.g. `@State private var appleHandoffSucceeded = false`
2. In `beginAppleTryHandoff`, set `appleHandoffSucceeded = (result.kind == .savedToFitness)`
3. In `garminHandoffPanel` (or a sibling), when `appleHandoffSucceeded`:

```swift
if appleHandoffSucceeded {
    NavigationLink {
        if #available(iOS 18.0, *) {
            WorkoutScheduleView()
        }
    } label: {
        Text("Manage scheduled plans")
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundColor(DailyDriver.lime)
    }
    .accessibilityIdentifier("af_workout_detail_manage_scheduled_plans")
}
```

If the detail view is not inside a `NavigationStack`, present `WorkoutScheduleView` in a `.sheet` instead — prefer sheet if NavigationLink is unreliable from that surface.

- [ ] **Step 3 (preferred after dogfood, but implement preflight now if cheap): at-cap Start copy**

Add to `AppleStartHandoffFailureCode`:

```swift
case scheduleCapReached = "schedule_cap_reached"
```

Copy:

```swift
.scheduleCapReached: "Workout schedule is full — open Manage scheduled plans (or Devices → Scheduled in Workout), remove some, then retry."
```

In `LiveWorkoutKitSaver` or a thin wrapper used by handoff, before `saveToWorkoutKit`:

```swift
if #available(iOS 18.0, *) {
    let scheduled = await WorkoutScheduler.shared.scheduledWorkouts
    if scheduled.count >= WorkoutScheduler.maxAllowedScheduledWorkoutCount {
        throw WorkoutPlanError.saveFailed(
            NSError(domain: "WorkoutKitSchedule", code: 15, userInfo: [
                NSLocalizedDescriptionKey: "schedule_cap_reached"
            ])
        )
    }
}
```

Map that in `failureCode(from:)` → `.scheduleCapReached`. Add a unit test on the copy string.

If injecting this into `LiveWorkoutKitSaver` feels too invasive, add the preflight inside `AppleStartHandoffService.handoff` via a new optional `WorkoutKitScheduleManaging` dependency used only for `fetchScheduledRows` / `maxAllowedCount` — keep save path otherwise unchanged.

- [ ] **Step 4: Build + run unit tests**

```bash
xcodebuild test -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:AmakaFlowCompanionTests/WorkoutScheduleViewModelTests \
  -only-testing:AmakaFlowCompanionTests/AppleStartHandoffCopyTests 2>&1 | tail -50
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add AmakaFlow/Views/DevicesView.swift \
  AmakaFlow/Views/UnifiedWorkoutDetailView.swift \
  AmakaFlow/Services/AppleStartHandoff.swift \
  AmakaFlowCompanion/AmakaFlowCompanionTests/AppleStartHandoffTests.swift
git commit -m "$(cat <<'EOF'
feat(AMA-2330): wire schedule cleanup from Devices and Start success

Add Manage scheduled plans discoverability; optional at-cap Start copy.
EOF
)"
```

---

### Task 6: Docs + dogfood checklist

**Files:**
- Modify: `docs/ama-2287-visual-evidence/README.md`

- [ ] **Step 1: Update duplicates gap section**

Replace “Duplicate scheduled plans (accepted gap)” follow-up with:

```markdown
## Duplicate scheduled plans

Every Start **adds** another plan (keep-adding is intentional). Cleanup is user-initiated:

- Devices → **Scheduled in Workout**
- Or Start success → **Manage scheduled plans**

Multi-select, swipe delete, and Clear all remove AmakaFlow plans via `WorkoutScheduler` (per-app). Spec: `docs/superpowers/specs/2026-07-27-apple-workoutkit-scheduled-plans-cleanup-design.md` (AMA-2330).

### Dogfood — cleanup

1. Start 2–3 times → list shows newest-first with relative times.
2. Delete one → Watch list loses one card (may lag ~30s — expected).
3. Multi-select two → both gone.
4. Clear all → no AmakaFlow cards left.
5. **Watch lag:** delete on iPhone → open Watch immediately → card may still show → gone within ~30s.
6. **At cap:** schedule until `WorkoutScheduler.maxAllowedScheduledWorkoutCount`, Start again — record throw vs silent no-op; confirm friendly copy / Manage link.
```

- [ ] **Step 2: Commit**

```bash
git add docs/ama-2287-visual-evidence/README.md \
  docs/superpowers/specs/2026-07-27-apple-workoutkit-scheduled-plans-cleanup-design.md
git commit -m "$(cat <<'EOF'
docs(AMA-2330): point duplicates gap at schedule cleanup screen

Add Watch-lag and at-cap dogfood steps for founder verification.
EOF
)"
```

---

## Self-review (plan vs spec)

| Spec requirement | Task |
| --- | --- |
| Keep-adding Start | Global constraint; Task 5 preflight fails only at cap |
| Multi / single / Clear all | Tasks 3–4 |
| Newest-first + relative + completed de-emphasize | Tasks 2, 4 |
| Refresh clears selection | Task 2 |
| Partial failure keeps failed IDs | Task 3 |
| Devices + Start Manage link | Task 5 |
| Copy (AmakaFlow, can’t be undone) | Task 4 |
| Cap via `maxAllowedScheduledWorkoutCount` | Tasks 1, 5, 6 |
| Exact `remove(plan, at: date)` | Tasks 1, 3 |
| Live iOS 18 gate | Task 1 |
| Defer workoutkit-sync | Global constraint |
| Docs / dogfood | Task 6 |

No TBD placeholders remain for implementable paths; Live `displayName` property may need a one-line SDK adjustment noted in Task 1.

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-27-apple-workoutkit-scheduled-plans-cleanup.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks  
2. **Inline Execution** — run tasks in this session with checkpoints  

Which approach?
