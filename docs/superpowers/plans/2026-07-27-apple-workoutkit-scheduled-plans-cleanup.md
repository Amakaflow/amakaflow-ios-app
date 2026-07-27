# Scheduled WorkoutKit plan cleanup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users list and delete AmakaFlow-scheduled WorkoutKit plans on iPhone (multi-select, swipe, Clear all) without changing Start’s keep-adding behavior.

**Architecture:** `WorkoutKitScheduleManaging` (Live → `WorkoutScheduler`, Mock for tests). ViewModel owns sort/sections, selection rules, and **still-present-after-refetch** failure detection (`remove` / `removeAllWorkouts` are non-throwing on Apple’s API). UI is `WorkoutScheduleView`, entered from Devices and Start success.

**Tech Stack:** Swift, SwiftUI, WorkoutKit (iOS 18+), XCTest

**Spec:** `docs/superpowers/specs/2026-07-27-apple-workoutkit-scheduled-plans-cleanup-design.md`  
**Linear:** AMA-2330 (parent AMA-2287)

## Global Constraints

- Start **keeps adding** — never remove/replace inside handoff except optional **preflight fail** when already at cap.
- User-facing brand: **AmakaFlow** (never AmakaFlowCompanion). Destination: **Workout** / Apple Watch Workout.
- Live adapter `@available(iOS 18.0, *)`. Pre-iOS 18: **hide** Devices row and Manage link.
- Remove uses fetched `scheduled.plan` + `scheduled.date` only.
- Apple `remove` / `removeAllWorkouts` are async **non-throwing**. Production failure = row still present after re-fetch.
- Selection rules: (1) manual refresh clears selection + exits edit; (2) post-delete refresh sets `selectedIDs = attempted ∩ stillPresent`.
- Cap: `WorkoutScheduler.maxAllowedScheduledWorkoutCount` — never hardcode 15 in copy.
- V1 protocol in app; no `workoutkit-sync` list/remove extraction yet.
- Do not modify Garmin / AmakaFlowWatch / AMA-2329.

---

## File Structure

| File | Responsibility |
| ---- | -------------- |
| `AmakaFlow/Services/WorkoutKitScheduleManaging.swift` | Row ID helper, row model, protocol, Live, Mock |
| `AmakaFlow/ViewModels/WorkoutScheduleViewModel.swift` | Load/sort/sections/select/delete/clear/selection rules |
| `AmakaFlow/Views/WorkoutScheduleView.swift` | List UI, confirms, footnote, auth → Settings |
| `AmakaFlow/Views/DevicesView.swift` | Scheduled in Workout entry (iOS 18+) |
| `AmakaFlow/Views/UnifiedWorkoutDetailView.swift` | Manage scheduled plans after Apple Start success |
| `AmakaFlow/Services/AppleStartHandoff.swift` | At-cap failure code + copy |
| `AmakaFlowCompanion/AmakaFlowCompanionTests/WorkoutScheduleViewModelTests.swift` | Unit tests |
| `AmakaFlowCompanion/AmakaFlowCompanionTests/AppleStartHandoffTests.swift` | Cap copy tests |
| `docs/ama-2287-visual-evidence/README.md` | Gaps + dogfood (incl. completed-vs-cap) |

---

### Task 1: Protocol, row identity, Mock, Live

**Files:**
- Create: `AmakaFlow/Services/WorkoutKitScheduleManaging.swift`
- Test: `AmakaFlowCompanion/AmakaFlowCompanionTests/WorkoutScheduleViewModelTests.swift`

**Interfaces:**
- Produces: `WorkoutScheduleRowID`, `WorkoutScheduleRow`, `WorkoutKitScheduleManaging`, `MockWorkoutKitScheduler`, `LiveWorkoutKitScheduler`

- [ ] **Step 1: Confirm SDK signatures**

Jump to Definition / docs for:

- `scheduledWorkouts: [ScheduledWorkoutPlan] { get async }`
- `remove(_ workout: WorkoutPlan, at: DateComponents) async` (non-throwing)
- `removeAllWorkouts() async` (non-throwing)
- `static let maxAllowedScheduledWorkoutCount: Int`
- Title property on `WorkoutPlan` / associated workout for list display

Expected Live remove:

```swift
await WorkoutScheduler.shared.remove(scheduled.plan, at: scheduled.date)
```

- [ ] **Step 2: Write failing identity tests**

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

- [ ] **Step 3: Run — expect compile fail** (`WorkoutScheduleRowID` missing)

```bash
cd /Users/davidandrews/dev/amakaflow-workspace/amakaflow-ios-app
xcodebuild test -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:AmakaFlowCompanionTests/WorkoutScheduleRowIDTests 2>&1 | tail -40
```

- [ ] **Step 4: Implement types + Mock + Live**

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
    /// Opaque Live token (plan id string); Mock uses same as planID.
    let removalToken: String
}

protocol WorkoutKitScheduleManaging: Sendable {
    func fetchScheduledRows() async throws -> [WorkoutScheduleRow]
    func remove(row: WorkoutScheduleRow) async throws
    func removeAll() async throws
    var maxAllowedCount: Int { get }
}

/// Test double. `noopRemoveIDs` leave the row present (production-shaped silent no-op).
final class MockWorkoutKitScheduler: WorkoutKitScheduleManaging, @unchecked Sendable {
    var rows: [WorkoutScheduleRow] = []
    var maxAllowedCount: Int = 15
    var removeCallIDs: [WorkoutScheduleRowID] = []
    var removeAllCallCount = 0
    var noopRemoveIDs: Set<WorkoutScheduleRowID> = []
    var fetchError: Error?

    func fetchScheduledRows() async throws -> [WorkoutScheduleRow] {
        if let fetchError { throw fetchError }
        return rows
    }

    func remove(row: WorkoutScheduleRow) async throws {
        removeCallIDs.append(row.id)
        guard !noopRemoveIDs.contains(row.id) else { return }
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
            print("WorkoutKitSchedule: at Apple schedule cap (\(scheduled.count)/\(maxAllowedCount))")
        }
        return scheduled.map { item in
            let planID = String(describing: item.plan.id)
            // Title: adjust to the SDK property confirmed in Step 1.
            let title = String(describing: item.plan)
            return WorkoutScheduleRow(
                id: WorkoutScheduleRowID(planID: planID, date: item.date),
                title: title,
                dateComponents: item.date,
                scheduledAt: calendar.date(from: item.date),
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

Replace Live `title` with the real display-name property after Step 1. Add the file to the same targets as `AppleStartHandoff.swift`.

- [ ] **Step 5: Run identity tests — PASS**

- [ ] **Step 6: Commit**

```bash
git add AmakaFlow/Services/WorkoutKitScheduleManaging.swift \
  AmakaFlowCompanion/AmakaFlowCompanionTests/WorkoutScheduleViewModelTests.swift
git commit -m "$(cat <<'EOF'
feat(AMA-2330): add WorkoutKit schedule manage protocol and mock

Canonical row IDs; Live/Mock seams for scheduled plan cleanup.
EOF
)"
```

---

### Task 2: ViewModel load, sections, manual-refresh selection rule

**Files:**
- Create: `AmakaFlow/ViewModels/WorkoutScheduleViewModel.swift`
- Modify: `AmakaFlowCompanion/AmakaFlowCompanionTests/WorkoutScheduleViewModelTests.swift`

**Interfaces:**
- Produces: `WorkoutScheduleViewModel` with `incompleteRows`, `completedRows`, `selectedIDs`, `isEditing`, `refresh(mode:)`

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
            isComplete: complete,
            removalToken: id
        )
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

- [ ] **Step 2: Run — expect fail** (`WorkoutScheduleViewModel` missing)

- [ ] **Step 3: Implement ViewModel (load/select only)**

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
        do {
            let rows = try await scheduler.fetchScheduledRows()
            let sorted = rows.sorted {
                ($0.scheduledAt ?? .distantPast) > ($1.scheduledAt ?? .distantPast)
            }
            incompleteRows = sorted.filter { !$0.isComplete }
            completedRows = sorted.filter(\.isComplete)
            rowsByID = Dictionary(uniqueKeysWithValues: sorted.map { ($0.id, $0) })
            authDenied = false

            switch mode {
            case .manual:
                selectedIDs = []
                isEditing = false
                statusMessage = nil
            case .afterMutation(let attempted):
                let present = Set(rowsByID.keys)
                let failed = attempted.intersection(present)
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
            let lower = error.localizedDescription.lowercased()
            authDenied = lower.contains("authoriz") || lower.contains("denied")
            statusMessage = error.localizedDescription
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
feat(AMA-2330): add WorkoutScheduleViewModel load and selection rules

Newest-first sections; manual refresh clears selection.
EOF
)"
```

---

### Task 3: deleteSelected / clearAll with still-present failure detection

**Files:**
- Modify: `AmakaFlow/ViewModels/WorkoutScheduleViewModel.swift`
- Modify: `AmakaFlowCompanion/AmakaFlowCompanionTests/WorkoutScheduleViewModelTests.swift`

**Interfaces:**
- Produces: `deleteSelected()`, `delete(row:)`, `clearAll()`

- [ ] **Step 1: Write failing tests**

```swift
func testDeleteSelectedPassesExactDateComponentsAndRemoves() async {
    let mock = MockWorkoutKitScheduler()
    let r = row(id: "1", title: "Hyrox", minutesAgo: 3)
    mock.rows = [r]
    let vm = WorkoutScheduleViewModel(scheduler: mock)
    await vm.refresh(mode: .manual)
    vm.enterEditing()
    vm.toggleSelect(r.id)
    await vm.deleteSelected()
    XCTAssertEqual(mock.removeCallIDs, [r.id])
    XCTAssertTrue(vm.incompleteRows.isEmpty)
    XCTAssertTrue(vm.selectedIDs.isEmpty)
}

func testEmptySelectionDoesNotCallRemove() async {
    let mock = MockWorkoutKitScheduler()
    mock.rows = [row(id: "1", title: "A", minutesAgo: 1)]
    let vm = WorkoutScheduleViewModel(scheduler: mock)
    await vm.refresh(mode: .manual)
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
    await vm.refresh(mode: .manual)
    await vm.clearAll()
    XCTAssertEqual(mock.removeAllCallCount, 1)
    XCTAssertTrue(vm.incompleteRows.isEmpty)
}

func testSilentNoOpRemoveKeepsStillPresentIDsSelected() async {
    let mock = MockWorkoutKitScheduler()
    let a = row(id: "a", title: "A", minutesAgo: 1)
    let b = row(id: "b", title: "B", minutesAgo: 2)
    let c = row(id: "c", title: "C", minutesAgo: 3)
    mock.rows = [a, b, c]
    mock.noopRemoveIDs = [b.id] // production-shaped: remove "succeeds" but row stays
    let vm = WorkoutScheduleViewModel(scheduler: mock)
    await vm.refresh(mode: .manual)
    vm.enterEditing()
    [a, b, c].forEach { vm.toggleSelect($0.id) }
    await vm.deleteSelected()
    XCTAssertEqual(vm.selectedIDs, [b.id])
    XCTAssertTrue(vm.isEditing)
    XCTAssertEqual(mock.removeCallIDs, [a.id, b.id, c.id])
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
    XCTAssertEqual(vm.selectedIDs, [b.id])
    mock.noopRemoveIDs = []
    mock.removeCallIDs = []
    await vm.deleteSelected()
    XCTAssertEqual(mock.removeCallIDs, [b.id])
    XCTAssertTrue(vm.selectedIDs.isEmpty)
}
```

- [ ] **Step 2: Run — expect fail** (methods missing)

- [ ] **Step 3: Implement delete / clear**

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
        try? await scheduler.remove(row: target)
    }
    await refresh(mode: .afterMutation(attempted: attempted))
}

func clearAll() async {
    try? await scheduler.removeAll()
    await refresh(mode: .manual)
    if incompleteRows.isEmpty && completedRows.isEmpty {
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
feat(AMA-2330): detect delete failures via still-present re-fetch

Non-throwing WorkoutKit removes; retry keeps attempted ∩ present.
EOF
)"
```

---

### Task 4: `WorkoutScheduleView`

**Files:**
- Create: `AmakaFlow/Views/WorkoutScheduleView.swift`

- [ ] **Step 1: Implement UI**

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
            _viewModel = StateObject(
                wrappedValue: WorkoutScheduleViewModel(scheduler: LiveWorkoutKitScheduler())
            )
        } else {
            _viewModel = StateObject(
                wrappedValue: WorkoutScheduleViewModel(scheduler: MockWorkoutKitScheduler())
            )
        }
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.incompleteRows.isEmpty && viewModel.completedRows.isEmpty {
                ProgressView("Loading scheduled plans…")
            } else {
                listContent
            }
        }
        .navigationTitle("Schedule")
        .toolbar { toolbarContent }
        .refreshable { await viewModel.refresh(mode: .manual) }
        .task { await viewModel.refresh(mode: .manual) }
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
        .accessibilityIdentifier("af_workout_schedule_screen")
    }

    private var listContent: some View {
        List {
            if viewModel.authDenied {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Workout permission denied — Settings → Health → Data Access → AmakaFlow, allow Workouts.")
                            .font(.footnote)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }
            }

            if viewModel.incompleteRows.isEmpty && viewModel.completedRows.isEmpty {
                ContentUnavailableView(
                    "No AmakaFlow plans in Workout",
                    systemImage: "figure.run",
                    description: Text("Start a workout to schedule one, or pull to refresh.")
                )
            }

            if !viewModel.incompleteRows.isEmpty {
                Section("Scheduled") {
                    ForEach(viewModel.incompleteRows, content: rowView)
                        .onDelete { offsets in
                            Task {
                                for index in offsets {
                                    await viewModel.delete(row: viewModel.incompleteRows[index])
                                }
                            }
                        }
                }
            }

            if !viewModel.completedRows.isEmpty {
                Section("Completed") {
                    ForEach(viewModel.completedRows) { row in
                        rowView(row).opacity(0.55)
                    }
                    .onDelete { offsets in
                        Task {
                            for index in offsets {
                                await viewModel.delete(row: viewModel.completedRows[index])
                            }
                        }
                    }
                }
            }

            if !viewModel.incompleteRows.isEmpty || !viewModel.completedRows.isEmpty {
                Section {
                    Text("Changes may take a moment to appear on Apple Watch.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
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
    }

    private func rowView(_ row: WorkoutScheduleRow) -> some View {
        HStack {
            if viewModel.isEditing {
                Image(systemName: viewModel.selectedIDs.contains(row.id)
                      ? "checkmark.circle.fill" : "circle")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
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

Match Daily Driver typography (`Theme` / `DailyDriver`) where neighboring screens do. Add file to target.

- [ ] **Step 2: Build SUCCEEDED**

```bash
xcodebuild build -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30
```

- [ ] **Step 3: Commit**

```bash
git add AmakaFlow/Views/WorkoutScheduleView.swift
git commit -m "$(cat <<'EOF'
feat(AMA-2330): add WorkoutScheduleView for multi-select cleanup

Completed section, relative times, Settings auth banner, Watch footnote.
EOF
)"
```

---

### Task 5: Entry points + at-cap Start copy

**Files:**
- Modify: `AmakaFlow/Views/DevicesView.swift`
- Modify: `AmakaFlow/Views/UnifiedWorkoutDetailView.swift`
- Modify: `AmakaFlow/Services/AppleStartHandoff.swift`
- Modify: `AmakaFlowCompanion/AmakaFlowCompanionTests/AppleStartHandoffTests.swift`

- [ ] **Step 1: Devices entry (hide pre-iOS 18)**

Add to `contentView` and `emptyView`:

```swift
@ViewBuilder
private var scheduledWorkoutPlansRow: some View {
    if #available(iOS 18.0, *) {
        NavigationLink {
            WorkoutScheduleView()
        } label: {
            AFCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Scheduled in Workout").afH2()
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
```

- [ ] **Step 2: Start success Manage link**

Track `@State private var appleHandoffSucceeded = false`. In `beginAppleTryHandoff`, set from `result.kind == .savedToFitness`. Under the status panel when true, present NavigationLink or sheet to `WorkoutScheduleView` labeled **Manage scheduled plans** (`af_workout_detail_manage_scheduled_plans`). Hide when not iOS 18+.

- [ ] **Step 3: At-cap preflight**

Add `AppleStartHandoffFailureCode.scheduleCapReached` with copy:

> Workout schedule is full — open Manage scheduled plans (or Devices → Scheduled in Workout), remove some, then retry.

In `AppleStartHandoffService.handoff`, before save, if iOS 18+ and `scheduledWorkouts.count >= maxAllowedScheduledWorkoutCount`, return `.failed` with that copy. Do not delete to make room.

Add copy unit test. If dogfood later shows completed plans count toward the cap, amend copy to mention clearing Completed — record that in Task 6, not guess here.

- [ ] **Step 4: Run unit tests — PASS**

```bash
xcodebuild test -scheme AmakaFlowCompanion -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:AmakaFlowCompanionTests/WorkoutScheduleViewModelTests \
  -only-testing:AmakaFlowCompanionTests/WorkoutScheduleRowIDTests \
  -only-testing:AmakaFlowCompanionTests/AppleStartHandoffCopyTests 2>&1 | tail -50
```

- [ ] **Step 5: Commit**

```bash
git add AmakaFlow/Views/DevicesView.swift \
  AmakaFlow/Views/UnifiedWorkoutDetailView.swift \
  AmakaFlow/Services/AppleStartHandoff.swift \
  AmakaFlowCompanion/AmakaFlowCompanionTests/AppleStartHandoffTests.swift
git commit -m "$(cat <<'EOF'
feat(AMA-2330): wire schedule cleanup entry points and at-cap Start

Devices + Start Manage link; preflight when Apple schedule cap is full.
EOF
)"
```

---

### Task 6: Gaps README + dogfood checklist

**Files:**
- Modify: `docs/ama-2287-visual-evidence/README.md`

- [ ] **Step 1: Replace duplicate-plans gap with cleanup + dogfood**

```markdown
## Duplicate scheduled plans

Start **keeps adding**. Cleanup is user-initiated (AMA-2330):

- Devices → **Scheduled in Workout**
- Start success → **Manage scheduled plans**

Spec: `docs/superpowers/specs/2026-07-27-apple-workoutkit-scheduled-plans-cleanup-design.md`

### Dogfood — cleanup

1. Start 2–3 times → list newest-first with relative times; Completed section separate.
2. Delete one / multi-select / Clear all; confirm Watch list.
3. **Watch lag:** delete on iPhone → Watch may still show card ~30s (accepted).
4. **At cap:** fill to `WorkoutScheduler.maxAllowedScheduledWorkoutCount`, Start again — record failure mode.
5. **Completed vs cap:** with scheduler full of a mix including `complete == true`, note whether completed plans count toward the cap. If yes, update at-cap copy to mention clearing Completed.
```

- [ ] **Step 2: Commit**

```bash
git add docs/ama-2287-visual-evidence/README.md
git commit -m "$(cat <<'EOF'
docs(AMA-2330): point duplicates gap at schedule cleanup screen

Add Watch-lag, at-cap, and completed-vs-cap dogfood steps.
EOF
)"
```

---

## Self-review (plan vs spec)

| Spec requirement | Task |
| --- | --- |
| Keep-adding Start | Global + Task 5 preflight only |
| Multi / single / Clear all | Tasks 3–4 |
| Newest-first + Completed section | Tasks 2, 4 |
| Manual refresh clears selection | Task 2 |
| Failure = still present after re-fetch | Task 3 |
| Retry = selected ∩ present | Task 3 |
| Hide pre-iOS 18 entries | Task 5 |
| Auth → Settings deep link | Task 4 |
| Cap API + dogfood completed-vs-cap | Tasks 5–6 |
| Exact `remove(plan, at:)` | Tasks 1, 3 |

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-27-apple-workoutkit-scheduled-plans-cleanup.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks  
2. **Inline Execution** — run tasks in this session with checkpoints  

Which approach?
