//
//  FatigueHistoryViewModel.swift
//  AmakaFlow
//
//  ViewModel for fatigue/readiness history display (AMA-1412)
//

import Foundation
import Combine

@MainActor
class FatigueHistoryViewModel: ObservableObject {
    @Published var dayStates: [DayState] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var apiErrorDisplay: APIErrorDisplayState?
    @Published var selectedRange: DateRange = .twoWeeks

    /// AMA-1933 proof hook: Coach readiness history uses the shared APIErrorState
    /// adapter so API failures from the migrated CoachAPIRepository render a typed
    /// user-facing error state instead of a blank or silent failure.
    private let apiErrorState = APIErrorState()

    enum DateRange: String, CaseIterable {
        case oneWeek = "1W"
        case twoWeeks = "2W"
        case oneMonth = "1M"

        var days: Int {
            switch self {
            case .oneWeek: return 7
            case .twoWeeks: return 14
            case .oneMonth: return 30
            }
        }
    }

    private let dependencies: AppDependencies
    private let syncHealthKitHRV: () async -> HealthKitHRVSyncResult

    init(
        dependencies: AppDependencies = .live,
        syncHealthKitHRV: @escaping () async -> HealthKitHRVSyncResult = {
            await HealthKitHRVService.shared.syncRecentHRV()
        }
    ) {
        self.dependencies = dependencies
        self.syncHealthKitHRV = syncHealthKitHRV
    }

    func loadHistory() async {
        isLoading = true
        errorMessage = nil
        apiErrorDisplay = nil
        apiErrorState.clear()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -selectedRange.days, to: today) ?? today

        // AMA-2052: opportunistically ingest real Apple Health HRV without
        // blocking readiness history. Unavailable/denied/empty HK states are
        // honest no-data outcomes and write-back failures stay non-fatal.
        Task { [syncHealthKitHRV] in
            let result = await syncHealthKitHRV()
            if case .failed(let error) = result {
                print("[FatigueHistoryVM] HealthKit HRV sync failed: \(error)")
            }
        }

        do {
            let states = try await dependencies.apiService.fetchDayStates(
                from: formatter.string(from: startDate),
                to: formatter.string(from: today)
            )
            dayStates = states.sorted { $0.date > $1.date }
        } catch {
            print("[FatigueHistoryVM] loadHistory failed: \(error)")
            apiErrorState.present(error)
            apiErrorDisplay = apiErrorState.current
            errorMessage = apiErrorDisplay?.message ?? "Could not load readiness history"
        }

        isLoading = false
    }

    func changeRange(_ range: DateRange) {
        selectedRange = range
        Task { await loadHistory() }
    }

    var averageFatigueScore: Double? {
        let scores = dayStates.compactMap { $0.fatigueScore }
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }

    var greenDays: Int { dayStates.filter { $0.readiness == .green }.count }
    var yellowDays: Int { dayStates.filter { $0.readiness == .yellow }.count }
    var redDays: Int { dayStates.filter { $0.readiness == .red }.count }
}
