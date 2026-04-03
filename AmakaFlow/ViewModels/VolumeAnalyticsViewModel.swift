//
//  VolumeAnalyticsViewModel.swift
//  AmakaFlow
//
//  ViewModel for volume analytics with balance computation (AMA-1414)
//

import Foundation
import Combine

@MainActor
class VolumeAnalyticsViewModel: ObservableObject {
    enum AnalyticsPeriod: String, CaseIterable {
        case week = "1W"
        case month = "1M"
        case quarter = "3M"

        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            case .quarter: return 90
            }
        }

        var granularity: String {
            switch self {
            case .week: return "daily"
            case .month: return "weekly"
            case .quarter: return "monthly"
            }
        }
    }

    @Published var selectedPeriod: AnalyticsPeriod = .month
    @Published var currentData: VolumeAnalyticsResponse?
    @Published var previousData: VolumeAnalyticsResponse?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let dependencies: AppDependencies
    private var loadTask: Task<Void, Never>?
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init(dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
    }

    func loadVolume() async {
        isLoading = true
        errorMessage = nil

        let today = Date()
        let currentStart = Calendar.current.date(byAdding: .day, value: -selectedPeriod.days, to: today) ?? today
        let previousStart = Calendar.current.date(byAdding: .day, value: -selectedPeriod.days, to: currentStart) ?? currentStart

        do {
            async let currentResult = dependencies.apiService.fetchVolumeAnalytics(
                startDate: formatter.string(from: currentStart),
                endDate: formatter.string(from: today),
                granularity: selectedPeriod.granularity
            )
            async let previousResult = dependencies.apiService.fetchVolumeAnalytics(
                startDate: formatter.string(from: previousStart),
                endDate: formatter.string(from: currentStart),
                granularity: selectedPeriod.granularity
            )
            let current = try await currentResult
            let previous = try await previousResult

            guard !Task.isCancelled else { return }
            currentData = current
            previousData = previous
        } catch {
            guard !Task.isCancelled else { return }
            print("[VolumeAnalyticsVM] loadVolume failed: \(error)")
            errorMessage = "Could not load volume data"
        }

        if !Task.isCancelled {
            isLoading = false
        }
    }

    func changePeriod(_ period: AnalyticsPeriod) {
        selectedPeriod = period
        loadTask?.cancel()
        loadTask = Task { await loadVolume() }
    }

    // MARK: - Balance Ratios

    private static let pushMuscles: Set<String> = ["chest", "shoulders", "triceps"]
    private static let pullMuscles: Set<String> = ["back", "biceps"]
    private static let upperMuscles: Set<String> = ["chest", "back", "shoulders", "biceps", "triceps"]
    private static let lowerMuscles: Set<String> = ["legs", "glutes", "hamstrings", "calves", "quads"]

    var pushPullRatio: Double? {
        guard let breakdown = currentData?.summary.muscleGroupBreakdown else { return nil }
        let push = Self.pushMuscles.reduce(0.0) { $0 + (breakdown[$1] ?? 0) }
        let pull = Self.pullMuscles.reduce(0.0) { $0 + (breakdown[$1] ?? 0) }
        guard pull > 0 else { return nil }
        return push / pull
    }

    var upperLowerRatio: Double? {
        guard let breakdown = currentData?.summary.muscleGroupBreakdown else { return nil }
        let upper = Self.upperMuscles.reduce(0.0) { $0 + (breakdown[$1] ?? 0) }
        let lower = Self.lowerMuscles.reduce(0.0) { $0 + (breakdown[$1] ?? 0) }
        guard lower > 0 else { return nil }
        return upper / lower
    }

    var sortedMuscleGroups: [(name: String, volume: Double, percentage: Double)] {
        guard let breakdown = currentData?.summary.muscleGroupBreakdown else { return [] }
        let total = breakdown.values.reduce(0, +)
        guard total > 0 else { return [] }
        return breakdown.map { (name: $0.key, volume: $0.value, percentage: $0.value / total * 100) }
            .sorted { $0.volume > $1.volume }
    }

    var volumeChange: Double? {
        guard let current = currentData?.summary.totalVolume,
              let previous = previousData?.summary.totalVolume,
              previous > 0 else { return nil }
        return (current - previous) / previous * 100
    }
}
