//
//  WorkoutCompletion.swift
//  AmakaFlow
//
//  Model for completed workout records from the API
//

import Foundation

// MARK: - Workout Completion Model

struct WorkoutCompletion: Identifiable, Codable, Hashable {
    let id: String
    let workoutName: String
    let startedAt: Date
    let endedAt: Date?           // Optional - backend may not return this
    let durationSeconds: Int
    let avgHeartRate: Int?
    let maxHeartRate: Int?
    let activeCalories: Int?
    let source: CompletionSource
    let syncedToStrava: Bool?    // Optional - backend may not return this
    let workoutId: String?       // Link to original workout (AMA-237)
    let originalWorkout: Workout? // Full workout for re-running (AMA-237)
    let isSimulated: Bool?       // True if workout was run in simulation mode (AMA-271)

    /// Computed endedAt from startedAt + durationSeconds if not provided
    var resolvedEndedAt: Date {
        endedAt ?? startedAt.addingTimeInterval(TimeInterval(durationSeconds))
    }

    /// Strava sync status with default false if not provided
    var isSyncedToStrava: Bool {
        syncedToStrava ?? false
    }

    /// Whether this completion can be re-run (has original workout data)
    var canRerun: Bool {
        originalWorkout != nil
    }

    /// Whether this was a simulated workout (AMA-271)
    var wasSimulated: Bool {
        isSimulated ?? false
    }

    enum CompletionSource: String, Codable {
        case appleWatch = "apple_watch"
        case garmin = "garmin"
        case manual = "manual"
        case phone = "phone"

        var displayName: String {
            switch self {
            case .appleWatch: return "Apple Watch"
            case .garmin: return "Garmin"
            case .manual: return "Manual"
            case .phone: return "Phone"
            }
        }

        var iconName: String {
            switch self {
            case .appleWatch: return "applewatch"
            case .garmin: return "watchface.applewatch.case"
            case .manual: return "pencil"
            case .phone: return "iphone"
            }
        }
    }
}

// MARK: - Computed Properties

extension WorkoutCompletion {
    /// Formatted duration string (e.g., "45:00" or "1:02:30")
    var formattedDuration: String {
        let hours = durationSeconds / 3600
        let minutes = (durationSeconds % 3600) / 60
        let seconds = durationSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Formatted start time (e.g., "10:45 AM")
    var formattedStartTime: String {
        startedAt.formatted(date: .omitted, time: .shortened)
    }

    /// Date formatted for display (e.g., "Dec 28")
    var formattedDate: String {
        startedAt.formatted(.dateTime.month(.abbreviated).day())
    }

    /// Whether this completion has any health metrics
    var hasHealthMetrics: Bool {
        avgHeartRate != nil || activeCalories != nil
    }
}

// MARK: - Date Grouping Helpers

extension WorkoutCompletion {
    /// Returns the date category for grouping (Today, Yesterday, or the date)
    var dateCategory: DateCategory {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let completionDay = calendar.startOfDay(for: startedAt)

        if calendar.isDateInToday(startedAt) {
            return .today
        } else if calendar.isDateInYesterday(startedAt) {
            return .yesterday
        } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: today),
                  completionDay >= weekAgo {
            return .thisWeek(startedAt)
        } else {
            return .older(startedAt)
        }
    }

    enum DateCategory: Hashable {
        case today
        case yesterday
        case thisWeek(Date)
        case older(Date)

        var title: String {
            switch self {
            case .today:
                return "Today"
            case .yesterday:
                return "Yesterday"
            case .thisWeek(let date):
                return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
            case .older(let date):
                return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
            }
        }

        var sortOrder: Int {
            switch self {
            case .today: return 0
            case .yesterday: return 1
            case .thisWeek: return 2
            case .older: return 3
            }
        }
    }
}

// MARK: - Weekly Summary

struct WeeklySummary {
    let workoutCount: Int
    let totalDurationSeconds: Int
    let totalCalories: Int

    var formattedDuration: String {
        let hours = totalDurationSeconds / 3600
        let minutes = (totalDurationSeconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    var formattedCalories: String {
        if totalCalories >= 1000 {
            return String(format: "%.1fk", Double(totalCalories) / 1000.0)
        }
        return "\(totalCalories)"
    }

    init(completions: [WorkoutCompletion]) {
        self.workoutCount = completions.count
        self.totalDurationSeconds = completions.reduce(0) { $0 + $1.durationSeconds }
        self.totalCalories = completions.reduce(0) { $0 + ($1.activeCalories ?? 0) }
    }
}

// MARK: - Sample Data

extension WorkoutCompletion {
    static var sampleData: [WorkoutCompletion] {
        let now = Date()
        return [
            WorkoutCompletion(
                id: "1",
                workoutName: "HIIT Cardio Blast",
                startedAt: now.addingTimeInterval(-3600), // 1 hour ago
                endedAt: now.addingTimeInterval(-600),
                durationSeconds: 2700,
                avgHeartRate: 142,
                maxHeartRate: 178,
                activeCalories: 320,
                source: .appleWatch,
                syncedToStrava: true,
                workoutId: "workout-1",
                originalWorkout: nil,
                isSimulated: false
            ),
            WorkoutCompletion(
                id: "2",
                workoutName: "Upper Body Strength",
                startedAt: now.addingTimeInterval(-86400 - 3600 * 6), // Yesterday 6pm
                endedAt: now.addingTimeInterval(-86400 - 3600 * 6 + 2280),
                durationSeconds: 2280,
                avgHeartRate: 118,
                maxHeartRate: 145,
                activeCalories: 245,
                source: .appleWatch,
                syncedToStrava: false,
                workoutId: "workout-2",
                originalWorkout: nil,
                isSimulated: false
            ),
            WorkoutCompletion(
                id: "3",
                workoutName: "Morning Yoga",
                startedAt: now.addingTimeInterval(-86400 - 3600 * 17), // Yesterday 7am
                endedAt: now.addingTimeInterval(-86400 - 3600 * 17 + 1500),
                durationSeconds: 1500,
                avgHeartRate: 95,
                maxHeartRate: 110,
                activeCalories: 120,
                source: .appleWatch,
                syncedToStrava: false,
                workoutId: nil,
                originalWorkout: nil,
                isSimulated: false
            ),
            WorkoutCompletion(
                id: "4",
                workoutName: "Evening Run",
                startedAt: now.addingTimeInterval(-86400 * 3), // 3 days ago
                endedAt: now.addingTimeInterval(-86400 * 3 + 1800),
                durationSeconds: 1800,
                avgHeartRate: 155,
                maxHeartRate: 172,
                activeCalories: 280,
                source: .garmin,
                syncedToStrava: true,
                workoutId: "workout-4",
                originalWorkout: nil,
                isSimulated: false
            ),
            WorkoutCompletion(
                id: "5",
                workoutName: "Core Workout",
                startedAt: now.addingTimeInterval(-86400 * 5), // 5 days ago
                endedAt: now.addingTimeInterval(-86400 * 5 + 1200),
                durationSeconds: 1200,
                avgHeartRate: 110,
                maxHeartRate: 130,
                activeCalories: 150,
                source: .phone,
                syncedToStrava: false,
                workoutId: nil,
                originalWorkout: nil,
                isSimulated: false
            )
        ]
    }
}
