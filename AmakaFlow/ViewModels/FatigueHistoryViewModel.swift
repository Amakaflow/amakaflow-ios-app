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
    @Published var selectedRange: DateRange = .twoWeeks

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

    init(dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
    }

    func loadHistory() async {
        isLoading = true
        errorMessage = nil

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -selectedRange.days, to: today) ?? today

        do {
            let states = try await dependencies.apiService.fetchDayStates(
                from: formatter.string(from: startDate),
                to: formatter.string(from: today)
            )
            dayStates = states.sorted { $0.date > $1.date }
        } catch {
            print("[FatigueHistoryVM] loadHistory failed: \(error)")
            errorMessage = "Could not load readiness history"
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
