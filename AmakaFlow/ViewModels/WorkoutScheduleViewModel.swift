//
//  WorkoutScheduleViewModel.swift
//  AmakaFlow
//
//  AMA-2330: Auth-aware load + section state for the scheduled-plan cleanup screen.
//

import Combine
import Foundation

/// Distinguishes a user-initiated refresh from a refresh that follows a mutation
/// (delete/clear), which needs to reconcile selection against rows that failed to remove.
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
    /// AMA-2330 P1 fix: gates `refresh`/`deleteSelected`/`clearAll`/`delete` against
    /// re-entrancy — a second tap (e.g. Delete then Clear all before the first
    /// finishes) is a no-op instead of racing WorkoutKit calls against each other.
    @Published private(set) var isMutating = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var authDenied = false
    @Published private(set) var showEmptyState = false

    private let scheduler: any WorkoutKitScheduleManaging
    private var rowsByID: [WorkoutScheduleRowID: WorkoutScheduleRow] = [:]
    /// Set only on the specific "Removed N of M; tap to retry" status — never derived
    /// from `statusMessage` text, so view copy can change without breaking retry.
    @Published private(set) var canRetry = false

    init(scheduler: any WorkoutKitScheduleManaging) {
        self.scheduler = scheduler
    }

    var selectedCount: Int { selectedIDs.count }

    /// AMA-2330 P1 fix: surfaces Apple's schedule cap on the cleanup screen itself
    /// (not just as a Start-time failure) — never hardcodes 15, always reads the
    /// scheduler's own `maxAllowedCount`.
    var isAtScheduleCap: Bool {
        incompleteRows.count + completedRows.count >= scheduler.maxAllowedCount
    }

    func enterEditing() { isEditing = true }
    func exitEditing() {
        isEditing = false
        selectedIDs = []
    }

    func toggleSelect(_ id: WorkoutScheduleRowID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    /// Public entry point — gated so an overlapping refresh/delete/clear-all can't
    /// interleave with this one. See `performRefresh` for the actual body, which
    /// `deleteSelected`/`clearAll` call directly since they already hold the gate.
    func refresh(mode: WorkoutScheduleRefreshMode = .manual) async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        _ = await performRefresh(mode: mode)
    }

    @discardableResult
    private func performRefresh(mode: WorkoutScheduleRefreshMode) async -> Bool {
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
            rowsByID = [:]
            showEmptyState = false
            selectedIDs = []
            isEditing = false
            canRetry = false
            return true
        }

        do {
            let rows = try await scheduler.fetchScheduledRows()
            let sorted = rows.sorted {
                ($0.scheduledAt ?? .distantPast) > ($1.scheduledAt ?? .distantPast)
            }
            incompleteRows = sorted.filter { !$0.isComplete }
            completedRows = sorted.filter(\.isComplete)
            // Collision-safe: duplicate WorkoutScheduleRowIDs must not trap.
            rowsByID = Dictionary(sorted.map { ($0.id, $0) }) { first, _ in first }
            showEmptyState = sorted.isEmpty

            switch mode {
            case .manual:
                selectedIDs = []
                isEditing = false
                statusMessage = nil
                canRetry = false
            case .afterMutation(let attempted):
                let failed = attempted.intersection(Set(rowsByID.keys))
                selectedIDs = failed
                isEditing = !failed.isEmpty
                let removed = attempted.count - failed.count
                if failed.isEmpty {
                    statusMessage = removed == 1 ? "Removed 1 plan." : "Removed \(removed) plans."
                    canRetry = false
                } else {
                    statusMessage = "Removed \(removed) of \(attempted.count); tap to retry"
                    canRetry = true
                }
            }
            return true
        } catch {
            statusMessage = error.localizedDescription
            showEmptyState = false
            canRetry = false
            return false
        }
    }

    /// Single-row delete (e.g. swipe-to-delete). Does not flip the list into
    /// multi-select edit mode; still-present reconciliation may select the row
    /// afterward only if removal silently failed.
    func delete(row: WorkoutScheduleRow) async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        guard rowsByID[row.id] != nil else { return }
        await performDelete(ids: [row.id])
    }

    /// Removes every selected row. `remove(row:)` is non-throwing and may be a
    /// silent no-op (see `WorkoutKitScheduleManaging`), so the post-mutation
    /// refresh — not the call site — is the source of truth for what actually
    /// disappeared; still-present ids stay selected for retry.
    func deleteSelected() async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        await performDelete(ids: Array(selectedIDs))
    }

    private func performDelete(ids: [WorkoutScheduleRowID]) async {
        let targets = ids.compactMap { rowsByID[$0] }
        guard !targets.isEmpty else { return }
        let attempted = Set(targets.map(\.id))
        for target in targets {
            await scheduler.remove(row: target)
        }
        _ = await performRefresh(mode: .afterMutation(attempted: attempted))
        Self.postScheduleDidChange()
    }

    func clearAll() async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        await scheduler.removeAll()
        let refreshed = await performRefresh(mode: .manual)
        // Always notify overview — removeAll may have succeeded even if list refresh failed.
        Self.postScheduleDidChange()
        guard refreshed else { return }
        if showEmptyState {
            statusMessage = "Removed all AmakaFlow plans."
        } else if !incompleteRows.isEmpty || !completedRows.isEmpty {
            // AMA-2330 P1 fix: `removeAll()` is non-throwing and may silently no-op
            // (mirrors `remove(row:)`); surface that instead of claiming success.
            statusMessage = "Some plans could not be removed — pull to refresh."
        }
    }

    /// AMA-2375 Move v1 — remove+re-add at a new date via the scheduler seam.
    /// Returns `true` when the reschedule itself succeeded (refresh may still warn).
    @discardableResult
    func move(row: WorkoutScheduleRow, to date: Date) async -> Bool {
        guard !isMutating else { return false }
        isMutating = true
        defer { isMutating = false }
        do {
            try await scheduler.reschedule(row: row, to: date)
            guard await performRefresh(mode: .manual) else {
                statusMessage = "Moved \(row.title), but the list couldn't refresh — pull to refresh."
                return false
            }
            statusMessage = "Moved \(row.title)."
            isEditing = true
            Self.postScheduleDidChange()
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    /// Notifies Library / On your watches so overview slot counts don't stay stale
    /// until a manual pull-to-refresh (parent screens load once and stay alive under
    /// NavigationStack).
    private static func postScheduleDidChange() {
        NotificationCenter.default.post(name: .appleWatchScheduleDidChange, object: nil)
    }

    var maxAllowedCount: Int { scheduler.maxAllowedCount }
}
