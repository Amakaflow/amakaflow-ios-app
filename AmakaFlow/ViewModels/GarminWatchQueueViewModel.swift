//
//  GarminWatchQueueViewModel.swift
//  AmakaFlow
//
//  AMA-2375: Garmin widget queue list (local index + per-workout delivery status).
//

import Combine
import Foundation

@MainActor
final class GarminWatchQueueViewModel: ObservableObject {
    @Published private(set) var items: [GarminQueueItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var isMutating = false

    private let queueStore: any GarminWatchQueueStoring
    private let statusFetcher: (String) async throws -> Components.Schemas.WatchDeliveryStatus
    private let calendar: Calendar

    var onWatchCount: Int { items.filter { $0.state == .onWatch }.count }
    var waitingCount: Int { items.filter { $0.state == .waiting }.count }
    var failedCount: Int { items.filter { $0.state == .failed }.count }

    var summaryLine: String {
        OnYourWatchesCopy.garminOverviewSub(
            onWatch: onWatchCount,
            waiting: waitingCount,
            failed: failedCount
        ).replacingOccurrences(of: "VIA AMAKAFLOW WIDGET", with: OnYourWatchesCopy.garminViaWidget)
    }

    init(
        queueStore: (any GarminWatchQueueStoring)? = nil,
        statusFetcher: ((String) async throws -> Components.Schemas.WatchDeliveryStatus)? = nil,
        calendar: Calendar = .current
    ) {
        self.queueStore = queueStore ?? GarminWatchQueueStore.shared
        self.statusFetcher = statusFetcher ?? { try await APIService.shared.watchDeliveryStatus(workoutId: $0) }
        self.calendar = calendar
    }

    func refresh() async {
        guard !isMutating else { return }
        if OnYourWatchesDemoSupport.isEnabled {
            OnYourWatchesDemoSupport.seedGarminQueueIfNeeded(store: queueStore)
        }
        isLoading = true
        defer { isLoading = false }

        let entries = queueStore.load()
        var built: [GarminQueueItem] = []
        for entry in entries {
            do {
                let status: Components.Schemas.WatchDeliveryStatus
                if OnYourWatchesDemoSupport.isEnabled {
                    status = OnYourWatchesDemoSupport.demoStatus(for: entry.workoutID)
                } else {
                    status = try await statusFetcher(entry.workoutID)
                }
                let state = GarminQueueItemState.from(delivery: status.state) ?? .waiting
                let subtitle = status.subtitle ?? ""
                built.append(
                    GarminQueueItem(
                        id: entry.workoutID,
                        workoutID: entry.workoutID,
                        title: entry.title,
                        state: state,
                        statusLine: Self.statusLine(
                            state: state,
                            subtitle: subtitle,
                            updatedAt: entry.updatedAt,
                            calendar: calendar
                        ),
                        failureReason: state == .failed ? (subtitle.isEmpty ? nil : subtitle) : nil
                    )
                )
            } catch {
                built.append(
                    GarminQueueItem(
                        id: entry.workoutID,
                        workoutID: entry.workoutID,
                        title: entry.title,
                        state: .waiting,
                        statusLine: OnYourWatchesCopy.garminSentHint,
                        failureReason: nil
                    )
                )
            }
        }
        items = built
    }

    func remove(item: GarminQueueItem) async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        queueStore.remove(workoutID: item.workoutID)
        items.removeAll { $0.id == item.id }
        statusMessage = "Removed from queue."
    }

    private static func statusLine(
        state: GarminQueueItemState,
        subtitle: String,
        updatedAt: Date,
        calendar: Calendar
    ) -> String {
        switch state {
        case .onWatch:
            return "ON WATCH · DOWNLOADED \(relativeDay(updatedAt, calendar: calendar))"
        case .waiting:
            return OnYourWatchesCopy.garminSentHint
        case .failed:
            let reason = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if reason.isEmpty {
                return "FAILED"
            }
            return "FAILED · \(reason.uppercased())"
        }
    }

    private static func relativeDay(_ date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "TODAY" }
        if calendar.isDateInYesterday(date) { return "YESTERDAY" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }
}
