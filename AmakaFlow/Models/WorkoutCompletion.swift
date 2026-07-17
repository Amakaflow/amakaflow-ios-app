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
    let distanceMeters: Int?
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
        dateCategory(now: Date(), calendar: .current)
    }

    func dateCategory(now: Date, calendar: Calendar = .current) -> DateCategory {
        let today = calendar.startOfDay(for: now)
        let completionDay = calendar.startOfDay(for: startedAt)

        if completionDay == today {
            return .today
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  completionDay == yesterday {
            return .yesterday
        } else if let weekInterval = calendar.dateInterval(of: .weekOfYear, for: today),
                  weekInterval.contains(completionDay) {
            return .thisWeek(completionDay)
        } else {
            return .older(completionDay)
        }
    }

    enum DateCategory: Hashable {
        case today
        case yesterday
        case thisWeek(Date)
        case older(Date)

        var id: String {
            switch self {
            case .today:
                return "today"
            case .yesterday:
                return "yesterday"
            case .thisWeek(let date):
                return "this-week-\(Int(date.timeIntervalSince1970))"
            case .older(let date):
                return "older-\(Int(date.timeIntervalSince1970))"
            }
        }

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
    let totalDistanceMeters: Int

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

    var formattedDistance: String {
        let km = Double(totalDistanceMeters) / 1000.0
        return String(format: "%.1f", km)
    }

    init(completions: [WorkoutCompletion]) {
        self.workoutCount = completions.count
        self.totalDurationSeconds = completions.reduce(0) { $0 + $1.durationSeconds }
        self.totalCalories = completions.reduce(0) { $0 + ($1.activeCalories ?? 0) }
        self.totalDistanceMeters = completions.reduce(0) { $0 + ($1.distanceMeters ?? 0) }
    }
}

// MARK: - Sample Data

extension WorkoutCompletion {
    /// AMA-2289 / AMA-2297 fixture: Today diary matching `dd-today-dark.png` (newest-first).
    /// Lunch Run + Lunch Workout (Strava imports) — system rows GARMIN SYNCED / DAY STARTED
    /// are rendered by `TodayDiaryView` when `isSimulated` fixtures are present.
    static func todayDiarySampleData(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [WorkoutCompletion] {
        let lunchRun = todayFixtureWindow(
            dayOf: now,
            startHour: 12,
            startMinute: 53,
            durationSeconds: 59 * 60,
            calendar: calendar
        )
        let lunchWorkout = todayFixtureWindow(
            dayOf: now,
            startHour: 12,
            startMinute: 44,
            durationSeconds: 8 * 60,
            calendar: calendar
        )
        return [
            WorkoutCompletion(
                id: "today-lunch-run",
                workoutName: "Lunch Run",
                startedAt: lunchRun.startedAt,
                endedAt: lunchRun.endedAt,
                durationSeconds: 59 * 60,
                avgHeartRate: 143,
                maxHeartRate: 165,
                activeCalories: 677,
                distanceMeters: 8200,
                source: .garmin,
                syncedToStrava: true,
                workoutId: "workout-lunch-run",
                originalWorkout: nil,
                isSimulated: true
            ),
            WorkoutCompletion(
                id: "today-lunch-workout",
                workoutName: "Lunch Workout",
                startedAt: lunchWorkout.startedAt,
                endedAt: lunchWorkout.endedAt,
                durationSeconds: 8 * 60,
                avgHeartRate: nil,
                maxHeartRate: nil,
                activeCalories: 50,
                distanceMeters: nil,
                source: .manual,
                syncedToStrava: true,
                workoutId: nil,
                originalWorkout: nil,
                isSimulated: true
            )
        ]
    }

    /// Profile tab fixture when API returns no completions — matches `dd-profile-dark.png`.
    static func profileHubSampleData(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [WorkoutCompletion] {
        func dayOffset(_ weekday: Int, hour: Int, minute: Int = 0) -> Date {
            let todayWeekday = calendar.component(.weekday, from: now)
            let delta = weekday - todayWeekday
            let base = calendar.date(byAdding: .day, value: delta, to: calendar.startOfDay(for: now)) ?? now
            return calendar.date(byAdding: .minute, value: hour * 60 + minute, to: base) ?? base
        }

        // Monday = 2 in Calendar weekday (Sunday = 1)
        let monday = dayOffset(2, hour: 7, minute: 30)
        let sunday = dayOffset(1, hour: 10)
        let saturday = dayOffset(7, hour: 8)
        let streakDay1 = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: now)) ?? now
        let streakDay2 = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) ?? now
        let thisWeekSession = calendar.date(byAdding: .hour, value: -3, to: now) ?? now

        var entries: [WorkoutCompletion] = [
            WorkoutCompletion(
                id: "profile-easy-shakeout",
                workoutName: "Easy shakeout",
                startedAt: monday,
                endedAt: monday.addingTimeInterval(32 * 60),
                durationSeconds: 32 * 60,
                avgHeartRate: 125,
                maxHeartRate: 140,
                activeCalories: 280,
                distanceMeters: 5100,
                source: .garmin,
                syncedToStrava: false,
                workoutId: "workout-shakeout",
                originalWorkout: nil,
                isSimulated: true
            ),
            WorkoutCompletion(
                id: "profile-amrap",
                workoutName: "DB Full-body AMRAP",
                startedAt: sunday,
                endedAt: sunday.addingTimeInterval(21 * 60),
                durationSeconds: 21 * 60,
                avgHeartRate: 132,
                maxHeartRate: 158,
                activeCalories: 190,
                distanceMeters: nil,
                source: .phone,
                syncedToStrava: false,
                workoutId: "workout-amrap",
                originalWorkout: nil,
                isSimulated: true
            ),
            WorkoutCompletion(
                id: "profile-long-run",
                workoutName: "Long endurance run",
                startedAt: saturday,
                endedAt: saturday.addingTimeInterval(98 * 60),
                durationSeconds: 98 * 60,
                avgHeartRate: 138,
                maxHeartRate: 162,
                activeCalories: 920,
                distanceMeters: 14600,
                source: .garmin,
                syncedToStrava: false,
                workoutId: "workout-long-run",
                originalWorkout: nil,
                isSimulated: true
            ),
            WorkoutCompletion(
                id: "profile-streak-1",
                workoutName: "Tempo run",
                startedAt: streakDay1.addingTimeInterval(3600 * 7),
                endedAt: streakDay1.addingTimeInterval(3600 * 7 + 2400),
                durationSeconds: 2400,
                avgHeartRate: 145,
                maxHeartRate: 168,
                activeCalories: 350,
                distanceMeters: 6000,
                source: .garmin,
                syncedToStrava: false,
                workoutId: nil,
                originalWorkout: nil,
                isSimulated: true
            ),
            WorkoutCompletion(
                id: "profile-streak-2",
                workoutName: "Recovery jog",
                startedAt: streakDay2.addingTimeInterval(3600 * 8),
                endedAt: streakDay2.addingTimeInterval(3600 * 8 + 1800),
                durationSeconds: 1800,
                avgHeartRate: 128,
                maxHeartRate: 145,
                activeCalories: 220,
                distanceMeters: 4500,
                source: .garmin,
                syncedToStrava: false,
                workoutId: nil,
                originalWorkout: nil,
                isSimulated: true
            ),
            WorkoutCompletion(
                id: "profile-this-week",
                workoutName: "Hyrox prep session",
                startedAt: thisWeekSession,
                endedAt: thisWeekSession.addingTimeInterval(44 * 60),
                durationSeconds: 44 * 60,
                avgHeartRate: 151,
                maxHeartRate: 172,
                activeCalories: 486,
                distanceMeters: nil,
                source: .phone,
                syncedToStrava: false,
                workoutId: "workout-hyrox",
                originalWorkout: nil,
                isSimulated: true
            )
        ]

        // Pad July month count toward handoff “9 sessions in July”.
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        for offset in 0..<3 {
            guard let day = calendar.date(byAdding: .day, value: offset + 1, to: monthStart) else { continue }
            let started = calendar.date(byAdding: .hour, value: 9, to: day) ?? day
            entries.append(
                WorkoutCompletion(
                    id: "profile-july-\(offset)",
                    workoutName: "July session \(offset + 1)",
                    startedAt: started,
                    endedAt: started.addingTimeInterval(1800),
                    durationSeconds: 1800,
                    avgHeartRate: 130,
                    maxHeartRate: 150,
                    activeCalories: 200,
                    distanceMeters: 4000,
                    source: .garmin,
                    syncedToStrava: false,
                    workoutId: nil,
                    originalWorkout: nil,
                    isSimulated: true
                )
            )
        }
        return entries
    }

    /// Fixed clock-times on `dayOf`'s calendar day (always same-day, never “yesterday before 02:00”).
    private static func todayFixtureWindow(
        dayOf: Date,
        startHour: Int,
        startMinute: Int = 0,
        durationSeconds: TimeInterval,
        calendar: Calendar
    ) -> (startedAt: Date, endedAt: Date) {
        let dayStart = calendar.startOfDay(for: dayOf)
        var components = DateComponents()
        components.hour = startHour
        components.minute = startMinute
        let startedAt = calendar.date(byAdding: components, to: dayStart) ?? dayStart
        let endedAt = startedAt.addingTimeInterval(durationSeconds)
        return (startedAt, endedAt)
    }

    static var sampleData: [WorkoutCompletion] {
        let now = Date()
        return todayDiarySampleData(now: now) + [
            WorkoutCompletion(
                id: "1",
                workoutName: "HIIT Cardio Blast",
                // Keep a legacy “today” Apple Watch sample for History grouping tests
                // when chronologically near `todayDiarySampleData` (still same day).
                startedAt: now.addingTimeInterval(-4800),
                endedAt: now.addingTimeInterval(-2100),
                durationSeconds: 2700,
                avgHeartRate: 142,
                maxHeartRate: 178,
                activeCalories: 320,
                distanceMeters: nil,
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
                distanceMeters: nil,
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
                distanceMeters: nil,
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
                distanceMeters: 5200,
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
                distanceMeters: nil,
                source: .phone,
                syncedToStrava: false,
                workoutId: nil,
                originalWorkout: nil,
                isSimulated: false
            )
        ]
    }
}
