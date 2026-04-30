//
//  AnalyticsViewModel.swift
//  AmakaFlow
//
//  ViewModel for the Analytics Hub - computes workout analytics client-side
//  from completion history data. (AMA-1234)
//

import Foundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.myamaka.AmakaFlowCompanion", category: "Analytics")

// MARK: - Analytics Data Models

struct WeeklyTrend: Identifiable {
    let id = UUID()
    let weekLabel: String       // e.g. "Mar 3"
    let workoutCount: Int
    let totalDurationSeconds: Int
}

struct AnalyticsRecord {
    let title: String
    let value: String
    let workoutName: String
    let date: Date
}

struct SportDistribution: Identifiable {
    let id = UUID()
    let sport: String
    let count: Int
    let percentage: Double
}

// MARK: - ViewModel

@MainActor
class AnalyticsViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // Weekly Summary
    @Published var weeklyWorkoutCount: Int = 0
    @Published var weeklyDurationSeconds: Int = 0
    @Published var weeklyExerciseCount: Int = 0

    // Volume Trends (last 8 weeks)
    @Published var volumeTrends: [WeeklyTrend] = []

    // Personal Records
    @Published var personalRecords: [AnalyticsRecord] = []

    // Workout Distribution by sport
    @Published var sportDistribution: [SportDistribution] = []

    // Fatigue
    @Published var fatigueLevel: String?
    @Published var fatigueMessage: String?

    // MARK: - Private

    private let dependencies: AppDependencies
    private var allCompletions: [WorkoutCompletion] = []

    // MARK: - Initialization

    init(dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
    }

    // MARK: - Data Loading

    func loadAnalytics() async {
        isLoading = true
        errorMessage = nil

        // Check auth
        let hasAuth = dependencies.pairingService.isPaired

        guard hasAuth else {
            isLoading = false
            return
        }

        do {
            // Fetch a large batch of completions for analytics
            let completions = try await dependencies.apiService.fetchCompletions(limit: 200, offset: 0)
            allCompletions = completions
            computeAnalytics()
            logger.info("Analytics loaded with \(completions.count) completions")
        } catch {
            errorMessage = "Failed to load analytics: \(error.localizedDescription)"
            logger.error("Analytics load error: \(error.localizedDescription)")
        }

        // Fetch fatigue advice (best-effort, don't block on failure)
        do {
            let advice = try await dependencies.apiService.getFatigueAdvice()
            fatigueLevel = advice.level.rawValue.capitalized
            fatigueMessage = advice.message
        } catch {
            logger.info("Fatigue advice not available: \(error.localizedDescription)")
        }

        isLoading = false
    }

    // MARK: - Computation

    private func computeAnalytics() {
        computeWeeklySummary()
        computeVolumeTrends()
        computePersonalRecords()
        computeSportDistribution()
    }

    private func computeWeeklySummary() {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let thisWeek = allCompletions.filter { $0.startedAt >= weekAgo }

        weeklyWorkoutCount = thisWeek.count
        weeklyDurationSeconds = thisWeek.reduce(0) { $0 + $1.durationSeconds }

        // Count exercises (intervals) from original workouts when available
        weeklyExerciseCount = thisWeek.reduce(0) { total, completion in
            if let workout = completion.originalWorkout {
                return total + workout.intervals.count
            }
            return total + 1 // count as 1 if no interval detail
        }
    }

    private func computeVolumeTrends() {
        let calendar = Calendar.current
        let now = Date()
        var trends: [WeeklyTrend] = []

        for weekOffset in (0..<8).reversed() {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: now),
                  let weekEnd = calendar.date(byAdding: .weekOfYear, value: -(weekOffset - 1), to: now) else {
                continue
            }

            let adjustedStart = calendar.startOfDay(for: weekStart)
            let weekCompletions = allCompletions.filter { completion in
                completion.startedAt >= adjustedStart && completion.startedAt < weekEnd
            }

            let label = adjustedStart.formatted(.dateTime.month(.abbreviated).day())

            trends.append(WeeklyTrend(
                weekLabel: label,
                workoutCount: weekCompletions.count,
                totalDurationSeconds: weekCompletions.reduce(0) { $0 + $1.durationSeconds }
            ))
        }

        volumeTrends = trends
    }

    private func computePersonalRecords() {
        guard !allCompletions.isEmpty else {
            personalRecords = []
            return
        }

        var records: [AnalyticsRecord] = []

        // Longest workout
        if let longest = allCompletions.max(by: { $0.durationSeconds < $1.durationSeconds }) {
            let hours = longest.durationSeconds / 3600
            let minutes = (longest.durationSeconds % 3600) / 60
            let value = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
            records.append(AnalyticsRecord(
                title: "Longest Workout",
                value: value,
                workoutName: longest.workoutName,
                date: longest.startedAt
            ))
        }

        // Highest calorie workout
        if let highCal = allCompletions.filter({ $0.activeCalories != nil }).max(by: { ($0.activeCalories ?? 0) < ($1.activeCalories ?? 0) }),
           let calories = highCal.activeCalories {
            records.append(AnalyticsRecord(
                title: "Most Calories Burned",
                value: "\(calories) cal",
                workoutName: highCal.workoutName,
                date: highCal.startedAt
            ))
        }

        // Highest heart rate
        if let highHR = allCompletions.filter({ $0.maxHeartRate != nil }).max(by: { ($0.maxHeartRate ?? 0) < ($1.maxHeartRate ?? 0) }),
           let maxHR = highHR.maxHeartRate {
            records.append(AnalyticsRecord(
                title: "Highest Heart Rate",
                value: "\(maxHR) bpm",
                workoutName: highHR.workoutName,
                date: highHR.startedAt
            ))
        }

        // Most exercises in one workout
        if let mostExercises = allCompletions
            .filter({ $0.originalWorkout != nil })
            .max(by: { ($0.originalWorkout?.intervals.count ?? 0) < ($1.originalWorkout?.intervals.count ?? 0) }),
           let intervalCount = mostExercises.originalWorkout?.intervals.count, intervalCount > 0 {
            records.append(AnalyticsRecord(
                title: "Most Exercises",
                value: "\(intervalCount) exercises",
                workoutName: mostExercises.workoutName,
                date: mostExercises.startedAt
            ))
        }

        personalRecords = records
    }

    private func computeSportDistribution() {
        // Group by sport from original workout, or "Other" if not available
        var sportCounts: [String: Int] = [:]

        for completion in allCompletions {
            let sport = completion.originalWorkout?.sport.rawValue.capitalized ?? "Other"
            sportCounts[sport, default: 0] += 1
        }

        let total = Double(allCompletions.count)
        sportDistribution = sportCounts
            .map { sport, count in
                SportDistribution(
                    sport: sport,
                    count: count,
                    percentage: total > 0 ? Double(count) / total * 100 : 0
                )
            }
            .sorted { $0.count > $1.count }
    }

    // MARK: - Formatted Properties

    var formattedWeeklyDuration: String {
        let hours = weeklyDurationSeconds / 3600
        let minutes = (weeklyDurationSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    var maxTrendCount: Int {
        volumeTrends.map(\.workoutCount).max() ?? 1
    }
}
