//
//  WorkoutKitScheduleManaging.swift
//  AmakaFlow
//
//  AMA-2330: App-shaped seam over WorkoutScheduler for scheduled-plan cleanup.
//

import Foundation
#if canImport(WorkoutKit)
import WorkoutKit
#endif

/// Auth state surfaced to the UI, decoupled from WorkoutKit's own enum.
enum ScheduleAuthState: Equatable, Sendable {
    case authorized, denied, notDetermined
}

/// Stable identity for a scheduled row, independent of `DateComponents` field ordering
/// or incidental metadata (e.g. `Calendar`/`TimeZone` set on one instance but not another).
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

/// One row in the scheduled-plans list — a plan + the date/time it's scheduled for.
struct WorkoutScheduleRow: Identifiable, Equatable, Sendable {
    let id: WorkoutScheduleRowID
    let title: String
    let dateComponents: DateComponents
    let scheduledAt: Date?
    let isComplete: Bool
}

/// App-shaped seam over `WorkoutScheduler` — mirrors `WorkoutKitSaving` in `AppleStartHandoff.swift`
/// so ViewModels/tests never link WorkoutKit directly.
///
/// `remove`/`removeAll` are intentionally non-throwing: WorkoutKit's own APIs
/// (`remove(_:at:)`, `removeAllWorkouts()`) are non-throwing, and a missing/mismatched
/// cache entry is a silent no-op rather than an error (see `LiveWorkoutKitScheduler`).
protocol WorkoutKitScheduleManaging: Sendable {
    var authorizationState: ScheduleAuthState { get async }
    var maxAllowedCount: Int { get }
    func requestAuthorization() async -> ScheduleAuthState
    func fetchScheduledRows() async throws -> [WorkoutScheduleRow]
    func remove(row: WorkoutScheduleRow) async
    func removeAll() async
    /// AMA-2375 Move v1: remove at the old slot and schedule the cached plan at `date`.
    func reschedule(row: WorkoutScheduleRow, to date: Date) async throws
}

#if DEBUG
/// In-memory test double. `maxAllowedCount` defaults to 15 to mirror Apple's real
/// schedule cap for fixtures, but UI copy must read `maxAllowedCount` — never hardcode 15.
final class MockWorkoutKitScheduler: WorkoutKitScheduleManaging, @unchecked Sendable {
    var authState: ScheduleAuthState = .authorized
    var rows: [WorkoutScheduleRow] = []
    var maxAllowedCount: Int = 15
    var removeCallRows: [WorkoutScheduleRow] = []
    var removeAllCallCount = 0
    var noopRemoveIDs: Set<WorkoutScheduleRowID> = []
    var fetchError: Error?
    var requestAuthorizationCallCount = 0
    /// When set, `remove(row:)` awaits this before mutating — deterministic
    /// concurrency-gate tests resume via `releaseRemoveGate()`.
    var removeGate: (@Sendable () async -> Void)?
    /// When true, `removeAll()` is a no-op (mirrors a WorkoutKit-side failure).
    var removeAllIsNoOp = false

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
        if let removeGate {
            await removeGate()
        }
        removeCallRows.append(row)
        guard !noopRemoveIDs.contains(row.id) else { return }
        rows.removeAll { $0.id == row.id }
    }

    func removeAll() async {
        removeAllCallCount += 1
        guard !removeAllIsNoOp else { return }
        rows = []
    }

    func reschedule(row: WorkoutScheduleRow, to date: Date) async throws {
        guard let index = rows.firstIndex(where: { $0.id == row.id }) else { return }
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        let updated = WorkoutScheduleRow(
            id: WorkoutScheduleRowID(planID: row.id.planID, date: components),
            title: row.title,
            dateComponents: components,
            scheduledAt: date,
            isComplete: row.isComplete
        )
        rows[index] = updated
    }
}
#else
/// Unreachable in shipping builds — schedule UI entry points are iOS 18+ only.
struct UnavailableWorkoutKitScheduler: WorkoutKitScheduleManaging {
    var authorizationState: ScheduleAuthState { get async { .denied } }
    var maxAllowedCount: Int { 0 }
    func requestAuthorization() async -> ScheduleAuthState { .denied }
    func fetchScheduledRows() async throws -> [WorkoutScheduleRow] { [] }
    func remove(row: WorkoutScheduleRow) async {}
    func removeAll() async {}
    func reschedule(row: WorkoutScheduleRow, to date: Date) async throws {}
}
#endif

#if canImport(WorkoutKit)
/// Live WorkoutKit-backed implementation. Caches `WorkoutPlan` by row id from the
/// last `fetchScheduledRows()` call, since `remove(row:)` needs the original
/// `WorkoutPlan` value (not just its id) to call `WorkoutScheduler.remove(_:at:)`.
/// A row with no cache entry (stale row, or `remove` called before any fetch) is a no-op.
///
/// `@MainActor` matches `AppleStartHandoffService` and the ViewModel call sites,
/// so `planCache` is not accessed across concurrent executors.
@available(iOS 18.0, *)
@MainActor
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
            Self.mapAuthorizationState(await WorkoutScheduler.shared.authorizationState)
        }
    }

    func requestAuthorization() async -> ScheduleAuthState {
        Self.mapAuthorizationState(await WorkoutScheduler.shared.requestAuthorization())
    }

    func fetchScheduledRows() async throws -> [WorkoutScheduleRow] {
        let scheduled = await WorkoutScheduler.shared.scheduledWorkouts
        if scheduled.count >= maxAllowedCount {
            print("WorkoutKitSchedule: at Apple schedule cap (\(scheduled.count)/\(maxAllowedCount))")
        }
        var cache: [WorkoutScheduleRowID: WorkoutPlan] = [:]
        let rows: [WorkoutScheduleRow] = scheduled.map { item in
            let planID = item.plan.id.uuidString
            let id = WorkoutScheduleRowID(planID: planID, date: item.date)
            cache[id] = item.plan
            return WorkoutScheduleRow(
                id: id,
                title: Self.title(for: item.plan),
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

    func reschedule(row: WorkoutScheduleRow, to date: Date) async throws {
        guard let plan = planCache[row.id] else { return }
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        await WorkoutScheduler.shared.remove(plan, at: row.dateComponents)
        try await WorkoutScheduler.shared.schedule(plan, at: components)
        // Refresh cache key for the new slot.
        _ = try await fetchScheduledRows()
    }

    private static func mapAuthorizationState(
        _ state: WorkoutScheduler.AuthorizationState
    ) -> ScheduleAuthState {
        switch state {
        case .authorized:
            return .authorized
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    /// AmakaFlow always schedules `.custom(CustomWorkout)` with `displayName` set
    /// (see `WorkoutPlanConverter`). `SingleGoalWorkout` and `PacerWorkout` have no
    /// `displayName` property in the SDK, so those plans (never created by AmakaFlow)
    /// fall back to a generic label.
    private static func title(for plan: WorkoutPlan) -> String {
        let displayName: String?
        switch plan.workout {
        case .custom(let workout):
            displayName = workout.displayName
        case .goal, .pacer:
            displayName = nil
        case .swimBikeRun(let workout):
            displayName = workout.displayName
        @unknown default:
            displayName = nil
        }
        if let displayName, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return displayName
        }
        return "Workout"
    }
}
#endif
