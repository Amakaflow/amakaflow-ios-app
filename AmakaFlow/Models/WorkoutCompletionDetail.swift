//
//  WorkoutCompletionDetail.swift
//  AmakaFlow
//
//  Extended model for workout completion with full HR samples and zone data
//

import Foundation

// MARK: - Heart Rate Sample (for detail chart)

struct HeartRateDataPoint: Identifiable, Codable, Hashable {
    var id: Date { timestamp }
    let timestamp: Date
    let bpm: Int

    enum CodingKeys: String, CodingKey {
        case timestamp
        case bpm
    }
}

// MARK: - Device Info (for completion detail)

struct CompletionDeviceInfo: Codable, Hashable {
    let model: String?
    let platform: String?
    let osVersion: String?

    var displayName: String {
        // Build a friendly display name from available fields
        if let model = model {
            // Convert model identifiers like "iPhone18,1" to friendlier names
            if model.starts(with: "iPhone") {
                return "iPhone"
            } else if model.starts(with: "Watch") {
                return "Apple Watch"
            }
            return model
        }
        if let platform = platform {
            switch platform.lowercased() {
            case "ios": return "iPhone"
            case "watchos": return "Apple Watch"
            default: return platform.capitalized
            }
        }
        return "Unknown Device"
    }
}

// MARK: - HR Zone

struct HRZone: Identifiable, Hashable {
    let id: Int
    let name: String
    let minPercent: Int
    let maxPercent: Int
    let timeInZoneSeconds: Int
    let percentageOfWorkout: Double
    let color: HRZoneColor

    var formattedTime: String {
        let minutes = timeInZoneSeconds / 60
        let seconds = timeInZoneSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    var rangeLabel: String {
        "\(minPercent)-\(maxPercent)%"
    }
}

enum HRZoneColor: String, Hashable {
    case gray = "gray"
    case blue = "blue"
    case green = "green"
    case yellow = "yellow"
    case red = "red"

    static func forZone(_ zoneNumber: Int) -> HRZoneColor {
        switch zoneNumber {
        case 1: return .gray
        case 2: return .blue
        case 3: return .green
        case 4: return .yellow
        case 5: return .red
        default: return .gray
        }
    }
}

// MARK: - Workout Completion Detail

struct WorkoutCompletionDetail: Identifiable, Codable, Hashable {
    let id: String
    let workoutName: String
    let startedAt: Date
    let endedAt: Date?              // Optional - backend may not return this
    let durationSeconds: Int
    let avgHeartRate: Int?
    let maxHeartRate: Int?
    let minHeartRate: Int?
    let activeCalories: Int?
    let totalCalories: Int?
    let steps: Int?
    let distanceMeters: Int?
    let source: WorkoutCompletion.CompletionSource
    let deviceInfo: CompletionDeviceInfo?
    let heartRateSamples: [HeartRateDataPoint]?
    let syncedToStrava: Bool?       // Optional - backend may not return this
    let stravaActivityId: String?
    let workoutId: String?          // Original workout ID (AMA-224)
    let workoutStructure: [WorkoutInterval]? // Workout steps/exercises (AMA-240)

    /// Computed endedAt from startedAt + durationSeconds if not provided
    var resolvedEndedAt: Date {
        endedAt ?? startedAt.addingTimeInterval(TimeInterval(durationSeconds))
    }

    /// Strava sync status with default false if not provided
    var isSyncedToStrava: Bool {
        syncedToStrava ?? false
    }

    /// Backward-compatible alias for workoutStructure
    var intervals: [WorkoutInterval]? {
        workoutStructure
    }

    enum CodingKeys: String, CodingKey {
        case id
        case workoutName
        case startedAt
        case endedAt
        case durationSeconds
        case avgHeartRate
        case maxHeartRate
        case minHeartRate
        case activeCalories
        case totalCalories
        case steps
        case distanceMeters
        case source
        case deviceInfo
        case heartRateSamples
        case syncedToStrava
        case stravaActivityId
        case workoutId
        case workoutStructure = "workout_structure"
        case intervalsLegacy = "intervals"  // Backwards compatibility (AMA-240)
    }

    // MARK: - Memberwise Initializer (required since we have custom decoder)

    init(
        id: String,
        workoutName: String,
        startedAt: Date,
        endedAt: Date?,
        durationSeconds: Int,
        avgHeartRate: Int?,
        maxHeartRate: Int?,
        minHeartRate: Int?,
        activeCalories: Int?,
        totalCalories: Int?,
        steps: Int?,
        distanceMeters: Int?,
        source: WorkoutCompletion.CompletionSource,
        deviceInfo: CompletionDeviceInfo?,
        heartRateSamples: [HeartRateDataPoint]?,
        syncedToStrava: Bool?,
        stravaActivityId: String?,
        workoutId: String?,
        workoutStructure: [WorkoutInterval]?
    ) {
        self.id = id
        self.workoutName = workoutName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.minHeartRate = minHeartRate
        self.activeCalories = activeCalories
        self.totalCalories = totalCalories
        self.steps = steps
        self.distanceMeters = distanceMeters
        self.source = source
        self.deviceInfo = deviceInfo
        self.heartRateSamples = heartRateSamples
        self.syncedToStrava = syncedToStrava
        self.stravaActivityId = stravaActivityId
        self.workoutId = workoutId
        self.workoutStructure = workoutStructure
    }

    // MARK: - Custom Decoder (supports both "workout_structure" and "intervals" from backend)

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        workoutName = try container.decode(String.self, forKey: .workoutName)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        durationSeconds = try container.decode(Int.self, forKey: .durationSeconds)
        avgHeartRate = try container.decodeIfPresent(Int.self, forKey: .avgHeartRate)
        maxHeartRate = try container.decodeIfPresent(Int.self, forKey: .maxHeartRate)
        minHeartRate = try container.decodeIfPresent(Int.self, forKey: .minHeartRate)
        activeCalories = try container.decodeIfPresent(Int.self, forKey: .activeCalories)
        totalCalories = try container.decodeIfPresent(Int.self, forKey: .totalCalories)
        steps = try container.decodeIfPresent(Int.self, forKey: .steps)
        distanceMeters = try container.decodeIfPresent(Int.self, forKey: .distanceMeters)
        source = try container.decode(WorkoutCompletion.CompletionSource.self, forKey: .source)
        deviceInfo = try container.decodeIfPresent(CompletionDeviceInfo.self, forKey: .deviceInfo)
        heartRateSamples = try container.decodeIfPresent([HeartRateDataPoint].self, forKey: .heartRateSamples)
        syncedToStrava = try container.decodeIfPresent(Bool.self, forKey: .syncedToStrava)
        stravaActivityId = try container.decodeIfPresent(String.self, forKey: .stravaActivityId)
        workoutId = try container.decodeIfPresent(String.self, forKey: .workoutId)

        // Try new field name first, fall back to legacy field name (AMA-240)
        if let structure = try container.decodeIfPresent([WorkoutInterval].self, forKey: .workoutStructure) {
            workoutStructure = structure
        } else {
            workoutStructure = try container.decodeIfPresent([WorkoutInterval].self, forKey: .intervalsLegacy)
        }
    }

    // MARK: - Custom Encoder (only encodes workoutStructure, not intervalsLegacy)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(workoutName, forKey: .workoutName)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(endedAt, forKey: .endedAt)
        try container.encode(durationSeconds, forKey: .durationSeconds)
        try container.encodeIfPresent(avgHeartRate, forKey: .avgHeartRate)
        try container.encodeIfPresent(maxHeartRate, forKey: .maxHeartRate)
        try container.encodeIfPresent(minHeartRate, forKey: .minHeartRate)
        try container.encodeIfPresent(activeCalories, forKey: .activeCalories)
        try container.encodeIfPresent(totalCalories, forKey: .totalCalories)
        try container.encodeIfPresent(steps, forKey: .steps)
        try container.encodeIfPresent(distanceMeters, forKey: .distanceMeters)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(deviceInfo, forKey: .deviceInfo)
        try container.encodeIfPresent(heartRateSamples, forKey: .heartRateSamples)
        try container.encodeIfPresent(syncedToStrava, forKey: .syncedToStrava)
        try container.encodeIfPresent(stravaActivityId, forKey: .stravaActivityId)
        try container.encodeIfPresent(workoutId, forKey: .workoutId)
        try container.encodeIfPresent(workoutStructure, forKey: .workoutStructure)
        // Note: intervalsLegacy is NOT encoded - it's only used for decoding backwards compatibility
    }
}

// MARK: - Workout Step Item (for display)

import SwiftUI

struct WorkoutStepItem: Identifiable, Hashable {
    let id = UUID()
    let stepNumber: Int
    let name: String
    let detail: String
    let target: String?
    let icon: String
    let iconColor: Color
}

// MARK: - Workout Steps Helpers

extension WorkoutCompletionDetail {
    /// Whether this completion has workout steps to display
    var hasWorkoutSteps: Bool {
        !(intervals?.isEmpty ?? true)
    }

    /// Flattened list of workout steps for display (expands repeat blocks)
    var flattenedSteps: [WorkoutStepItem] {
        guard let intervals = intervals else { return [] }
        return flattenIntervals(intervals, stepOffset: 0).0
    }

    private func flattenIntervals(_ intervals: [WorkoutInterval], stepOffset: Int) -> ([WorkoutStepItem], Int) {
        var items: [WorkoutStepItem] = []
        var currentStep = stepOffset

        for interval in intervals {
            switch interval {
            case .warmup(let seconds, let target):
                currentStep += 1
                items.append(WorkoutStepItem(
                    stepNumber: currentStep,
                    name: "Warm Up",
                    detail: formatTime(seconds),
                    target: target,
                    icon: "flame",
                    iconColor: .orange
                ))

            case .cooldown(let seconds, let target):
                currentStep += 1
                items.append(WorkoutStepItem(
                    stepNumber: currentStep,
                    name: "Cool Down",
                    detail: formatTime(seconds),
                    target: target,
                    icon: "snowflake",
                    iconColor: .blue
                ))

            case .time(let seconds, let target):
                currentStep += 1
                items.append(WorkoutStepItem(
                    stepNumber: currentStep,
                    name: "Timed Interval",
                    detail: formatTime(seconds),
                    target: target,
                    icon: "timer",
                    iconColor: .green
                ))

            case .reps(let sets, let reps, let name, let load, _, _):
                currentStep += 1
                var detail = "\(reps) reps"
                if let sets = sets, sets > 1 {
                    detail = "\(sets) × \(reps) reps"
                }
                if let load = load, !load.isEmpty {
                    detail += " @ \(load)"
                }
                items.append(WorkoutStepItem(
                    stepNumber: currentStep,
                    name: name,
                    detail: detail,
                    target: nil,
                    icon: "dumbbell.fill",
                    iconColor: .purple
                ))

            case .distance(let meters, let target):
                currentStep += 1
                items.append(WorkoutStepItem(
                    stepNumber: currentStep,
                    name: "Distance",
                    detail: WorkoutHelpers.formatDistance(meters: meters),
                    target: target,
                    icon: "figure.run",
                    iconColor: .green
                ))

            case .repeat(let repeatCount, let subIntervals):
                // Expand repeat blocks
                for _ in 0..<repeatCount {
                    let (subItems, newStep) = flattenIntervals(subIntervals, stepOffset: currentStep)
                    items.append(contentsOf: subItems)
                    currentStep = newStep
                }

            case .rest(let seconds):
                currentStep += 1
                let detail: String
                if let secs = seconds {
                    detail = formatTime(secs)
                } else {
                    detail = "Manual"
                }
                items.append(WorkoutStepItem(
                    stepNumber: currentStep,
                    name: "Rest",
                    detail: detail,
                    target: nil,
                    icon: "pause.circle.fill",
                    iconColor: .gray
                ))
            }
        }

        return (items, currentStep)
    }

    private func formatTime(_ seconds: Int) -> String {
        if seconds >= 60 {
            let minutes = seconds / 60
            let secs = seconds % 60
            if secs > 0 {
                return "\(minutes)m \(secs)s"
            }
            return "\(minutes) min"
        }
        return "\(seconds)s"
    }
}

// MARK: - Computed Properties

extension WorkoutCompletionDetail {
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

    /// Full date and time formatted (e.g., "Today at 10:45 AM")
    var formattedDateTime: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(startedAt) {
            return "Today at \(formattedStartTime)"
        } else if calendar.isDateInYesterday(startedAt) {
            return "Yesterday at \(formattedStartTime)"
        } else {
            return startedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }
    }

    /// Full date formatted (e.g., "December 28, 2024")
    var formattedFullDate: String {
        startedAt.formatted(date: .long, time: .omitted)
    }

    /// Formatted calories string
    var formattedCalories: String? {
        guard let calories = activeCalories else { return nil }
        return "\(calories)"
    }

    /// Formatted steps string
    var formattedSteps: String? {
        guard let steps = steps else { return nil }
        if steps >= 1000 {
            return String(format: "%.1fk", Double(steps) / 1000.0)
        }
        return "\(steps)"
    }

    /// Formatted distance string
    var formattedDistance: String? {
        guard let meters = distanceMeters else { return nil }
        if meters >= 1000 {
            let km = Double(meters) / 1000.0
            return String(format: "%.2f km", km)
        }
        return "\(meters) m"
    }

    /// Whether this completion has HR data to display
    var hasHeartRateData: Bool {
        avgHeartRate != nil || !(heartRateSamples?.isEmpty ?? true)
    }

    /// Whether this completion has HR samples for charting
    var hasHeartRateSamples: Bool {
        !(heartRateSamples?.isEmpty ?? true)
    }

    /// Whether this completion has any summary metrics
    var hasSummaryMetrics: Bool {
        activeCalories != nil || steps != nil || distanceMeters != nil
    }
}

// MARK: - HR Zone Calculation

extension WorkoutCompletionDetail {
    /// Calculate HR zones from samples using the given max heart rate
    /// - Parameter maxHR: User's maximum heart rate (default: 220 - age, typically ~190)
    /// - Returns: Array of HR zones with time spent in each
    func calculateHRZones(maxHR: Int = 190) -> [HRZone] {
        guard let samples = heartRateSamples, !samples.isEmpty else {
            return defaultZones()
        }

        // Define zone boundaries as percentages of max HR
        let zoneBoundaries: [(zone: Int, name: String, minPct: Int, maxPct: Int)] = [
            (1, "Zone 1", 50, 60),
            (2, "Zone 2", 60, 70),
            (3, "Zone 3", 70, 80),
            (4, "Zone 4", 80, 90),
            (5, "Zone 5", 90, 100)
        ]

        // Calculate time in each zone
        var zoneSeconds: [Int: Int] = [:]
        for boundary in zoneBoundaries {
            zoneSeconds[boundary.zone] = 0
        }

        // Calculate average time per sample
        let totalSeconds = durationSeconds
        let sampleInterval = samples.count > 1 ? totalSeconds / samples.count : totalSeconds

        for sample in samples {
            let percentage = Double(sample.bpm) / Double(maxHR) * 100

            for boundary in zoneBoundaries {
                if percentage >= Double(boundary.minPct) && percentage < Double(boundary.maxPct) {
                    zoneSeconds[boundary.zone, default: 0] += sampleInterval
                    break
                } else if percentage >= 100 && boundary.zone == 5 {
                    // Above max HR goes to zone 5
                    zoneSeconds[5, default: 0] += sampleInterval
                    break
                }
            }
        }

        // Convert to HRZone objects
        return zoneBoundaries.map { boundary in
            let seconds = zoneSeconds[boundary.zone] ?? 0
            let percentage = totalSeconds > 0 ? Double(seconds) / Double(totalSeconds) * 100 : 0

            return HRZone(
                id: boundary.zone,
                name: boundary.name,
                minPercent: boundary.minPct,
                maxPercent: boundary.maxPct,
                timeInZoneSeconds: seconds,
                percentageOfWorkout: percentage,
                color: HRZoneColor.forZone(boundary.zone)
            )
        }
    }

    private func defaultZones() -> [HRZone] {
        [
            HRZone(id: 1, name: "Zone 1", minPercent: 50, maxPercent: 60, timeInZoneSeconds: 0, percentageOfWorkout: 0, color: .gray),
            HRZone(id: 2, name: "Zone 2", minPercent: 60, maxPercent: 70, timeInZoneSeconds: 0, percentageOfWorkout: 0, color: .blue),
            HRZone(id: 3, name: "Zone 3", minPercent: 70, maxPercent: 80, timeInZoneSeconds: 0, percentageOfWorkout: 0, color: .green),
            HRZone(id: 4, name: "Zone 4", minPercent: 80, maxPercent: 90, timeInZoneSeconds: 0, percentageOfWorkout: 0, color: .yellow),
            HRZone(id: 5, name: "Zone 5", minPercent: 90, maxPercent: 100, timeInZoneSeconds: 0, percentageOfWorkout: 0, color: .red)
        ]
    }
}

// MARK: - Sample Data

extension WorkoutCompletionDetail {
    static var sample: WorkoutCompletionDetail {
        let now = Date()
        let startTime = now.addingTimeInterval(-3600) // 1 hour ago

        // Generate sample HR data points
        let samples = (0..<45).map { i in
            let timestamp = startTime.addingTimeInterval(Double(i) * 60) // Every minute
            let baseBPM = 100
            let variation = Int.random(in: -10...50)
            let bpm = min(180, max(85, baseBPM + variation + (i < 5 ? 0 : 40))) // Warmup then higher
            return HeartRateDataPoint(timestamp: timestamp, bpm: bpm)
        }

        // Sample workout steps
        let sampleIntervals: [WorkoutInterval] = [
            .warmup(seconds: 300, target: "Easy pace"),
            .reps(sets: 3, reps: 10, name: "Squats", load: "Body weight", restSec: 60, followAlongUrl: nil),
            .reps(sets: 3, reps: 12, name: "Lunges", load: nil, restSec: 45, followAlongUrl: nil),
            .reps(sets: 4, reps: 8, name: "Jump Squats", load: nil, restSec: 30, followAlongUrl: nil),
            .time(seconds: 60, target: "High knees"),
            .time(seconds: 60, target: "Mountain climbers"),
            .cooldown(seconds: 300, target: "Stretch")
        ]

        return WorkoutCompletionDetail(
            id: "detail-1",
            workoutName: "HIIT Cardio Blast",
            startedAt: startTime,
            endedAt: now.addingTimeInterval(-600),
            durationSeconds: 2700,
            avgHeartRate: 142,
            maxHeartRate: 178,
            minHeartRate: 85,
            activeCalories: 320,
            totalCalories: 380,
            steps: 4500,
            distanceMeters: 3200,
            source: .appleWatch,
            deviceInfo: CompletionDeviceInfo(model: "Watch7,1", platform: "watchos", osVersion: "11.0"),
            heartRateSamples: samples,
            syncedToStrava: true,
            stravaActivityId: "12345678",
            workoutId: nil,  // nil to show "Save to My Workouts" button
            workoutStructure: sampleIntervals
        )
    }

    static var sampleNoHR: WorkoutCompletionDetail {
        let now = Date()
        return WorkoutCompletionDetail(
            id: "detail-2",
            workoutName: "Quick Stretch",
            startedAt: now.addingTimeInterval(-1800),
            endedAt: now,
            durationSeconds: 900,
            avgHeartRate: nil,
            maxHeartRate: nil,
            minHeartRate: nil,
            activeCalories: 50,
            totalCalories: 60,
            steps: nil,
            distanceMeters: nil,
            source: .manual,
            deviceInfo: nil,
            heartRateSamples: nil,
            syncedToStrava: false,
            stravaActivityId: nil,
            workoutId: nil,
            workoutStructure: nil
        )
    }
}
