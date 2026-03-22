//
//  CalendarViewModel.swift
//  AmakaFlow
//
//  ViewModel for enhanced calendar with DayState, readiness, and conflict data (AMA-1147)
//

import Foundation
import Combine

@MainActor
class CalendarViewModel: ObservableObject {
    @Published var dayStates: [String: DayState] = [:]
    @Published var conflicts: [Conflict] = []
    @Published var proposedPlan: ProposedPlan?
    @Published var isLoadingDayStates = false
    @Published var isGeneratingWeek = false
    @Published var errorMessage: String?

    private let dependencies: AppDependencies

    init(dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
    }

    // MARK: - Day States

    /// Load day states for the visible week range
    func loadDayStates(from: Date, to: Date) async {
        isLoadingDayStates = true
        errorMessage = nil

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let fromStr = formatter.string(from: from)
        let toStr = formatter.string(from: to)

        do {
            let states = try await dependencies.apiService.fetchDayStates(from: fromStr, to: toStr)
            dayStates = Dictionary(uniqueKeysWithValues: states.map { ($0.date, $0) })
        } catch {
            if !(error is APIError && (error as! APIError).errorDescription == APIError.unauthorized.errorDescription) {
                print("[CalendarViewModel] Failed to load day states: \(error)")
            }
        }

        isLoadingDayStates = false
    }

    /// Get the readiness level for a given date
    func readiness(for date: Date) -> ReadinessLevel? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let key = formatter.string(from: date)
        return dayStates[key]?.readiness
    }

    // MARK: - Week Generation

    func generateWeek() async {
        isGeneratingWeek = true
        errorMessage = nil

        do {
            proposedPlan = try await dependencies.apiService.generateWeek()
        } catch {
            errorMessage = "Could not generate training week: \(error.localizedDescription)"
            print("[CalendarViewModel] generateWeek failed: \(error)")
        }

        isGeneratingWeek = false
    }

    // MARK: - Conflict Detection

    func detectConflicts(from: Date, to: Date) async {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        do {
            conflicts = try await dependencies.apiService.detectConflicts(
                startDate: formatter.string(from: from),
                endDate: formatter.string(from: to)
            )
        } catch {
            print("[CalendarViewModel] detectConflicts failed: \(error)")
        }
    }

    /// Check if a given date has any conflicts
    func hasConflict(on date: Date) -> Bool {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let dateStr = formatter.string(from: date)
        return conflicts.contains { $0.date == dateStr }
    }
}
