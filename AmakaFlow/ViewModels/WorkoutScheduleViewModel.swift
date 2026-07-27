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

    /// Single-row delete (e.g. swipe-to-delete), reusing the same still-present
    /// reconciliation as the multi-select path.
    func delete(row: WorkoutScheduleRow) async {
        selectedIDs = [row.id]
        isEditing = true
        await deleteSelected()
    }

    /// Removes every selected row. `remove(row:)` is non-throwing and may be a
    /// silent no-op (see `WorkoutKitScheduleManaging`), so the post-mutation
    /// refresh — not the call site — is the source of truth for what actually
    /// disappeared; still-present ids stay selected for retry.
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
}
