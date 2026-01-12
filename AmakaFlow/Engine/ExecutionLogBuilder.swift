//
//  ExecutionLogBuilder.swift
//  AmakaFlow
//
//  AMA-291: Tracks actual workout execution to build execution_log for completion submission
//

import Foundation

// MARK: - Execution Models

/// Status of an interval's execution (v2 contract)
enum IntervalStatus: String, Codable {
    case completed
    case skipped
    case notReached = "not_reached"
}

/// Status of a single set within an interval (v2 contract)
enum SetStatus: String, Codable {
    case completed
    case skipped
    case notReached = "not_reached"
}

/// Source of weight for a set (v2 contract)
enum WeightSource: String, Codable {
    case barbell
    case dumbbell
    case machine
    case bodyweight
    case cable
    case kettlebell
    case other
}

/// A single weight component (e.g., bar, plates, etc.)
struct WeightComponent: Codable {
    let source: WeightSource
    let value: Double
    let unit: String

    enum CodingKeys: String, CodingKey {
        case source, value, unit
    }
}

/// Complete weight entry with components and display label
struct WeightEntry: Codable {
    let components: [WeightComponent]
    let displayLabel: String

    enum CodingKeys: String, CodingKey {
        case components
        case displayLabel = "display_label"
    }

    /// Convenience initializer for simple single-weight entry
    static func simple(value: Double, unit: String, source: WeightSource = .other) -> WeightEntry {
        let component = WeightComponent(source: source, value: value, unit: unit)
        return WeightEntry(
            components: [component],
            displayLabel: "\(Int(value)) \(unit)"
        )
    }

    /// Convenience initializer from legacy weight/unit format
    static func fromLegacy(weight: Double?, unit: String?) -> WeightEntry? {
        guard let weight = weight, let unit = unit else { return nil }
        return simple(value: weight, unit: unit)
    }
}

/// Execution data for a single set within an interval (v2 contract)
struct SetExecution: Codable {
    let setNumber: Int
    var status: SetStatus = .completed
    var repsPlanned: Int?
    var repsCompleted: Int?
    var weight: WeightEntry?
    var durationSeconds: Int?
    var rpe: Int?

    enum CodingKeys: String, CodingKey {
        case setNumber = "set_number"
        case status
        case repsPlanned = "reps_planned"
        case repsCompleted = "reps_completed"
        case weight
        case durationSeconds = "duration_seconds"
        case rpe
    }
}

/// Execution data for a single interval (v2 contract)
struct IntervalExecution: Codable {
    let intervalIndex: Int
    let plannedKind: String?
    let plannedName: String?
    var status: IntervalStatus = .completed
    var plannedDurationSeconds: Int?
    var actualDurationSeconds: Int?
    var startedAt: Date?
    var endedAt: Date?
    var skipReason: String?
    var sets: [SetExecution]?

    enum CodingKeys: String, CodingKey {
        case intervalIndex = "interval_index"
        case plannedKind = "planned_kind"
        case plannedName = "planned_name"
        case status
        case plannedDurationSeconds = "planned_duration_seconds"
        case actualDurationSeconds = "actual_duration_seconds"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case skipReason = "skip_reason"
        case sets
    }
}

/// Summary statistics for execution log (v2 contract)
struct ExecutionSummary: Codable {
    let totalIntervals: Int
    let completed: Int
    let skipped: Int
    let notReached: Int
    let completionPercentage: Double
    let totalSets: Int
    let setsCompleted: Int
    let setsSkipped: Int
    let totalDurationSeconds: Int
    let activeDurationSeconds: Int

    enum CodingKeys: String, CodingKey {
        case totalIntervals = "total_intervals"
        case completed
        case skipped
        case notReached = "not_reached"
        case completionPercentage = "completion_percentage"
        case totalSets = "total_sets"
        case setsCompleted = "sets_completed"
        case setsSkipped = "sets_skipped"
        case totalDurationSeconds = "total_duration_seconds"
        case activeDurationSeconds = "active_duration_seconds"
    }
}

/// Skip reasons for intervals
enum SkipReason: String, CaseIterable {
    case fatigue = "fatigue"
    case timeConstraint = "time_constraint"
    case equipmentUnavailable = "equipment_unavailable"
    case pain = "pain"
    case other = "other"

    var displayName: String {
        switch self {
        case .fatigue: return "Too tired"
        case .timeConstraint: return "Running out of time"
        case .equipmentUnavailable: return "Equipment busy"
        case .pain: return "Pain/discomfort"
        case .other: return "Other"
        }
    }
}


// MARK: - ExecutionLogBuilder

/// Builds execution_log structure tracking actual workout execution
class ExecutionLogBuilder {
    private var intervals: [IntervalExecution] = []
    private var currentIntervalStartTime: Date?
    private var currentIntervalIndex: Int?
    // AMA-291: Track elapsed seconds for accurate simulation time
    private var currentIntervalStartElapsed: Int?

    // MARK: - Interval Tracking

    /// Start tracking a new interval
    /// - Parameters:
    ///   - index: Step index in flattened workout
    ///   - kind: Interval type (warmup, work, rest, reps, etc.)
    ///   - name: Display name for the interval
    ///   - plannedDuration: Planned duration in seconds (nil for reps-based)
    ///   - elapsedSeconds: Current elapsed seconds in workout (for simulation mode timing)
    func startInterval(index: Int, kind: String?, name: String?, plannedDuration: Int?, elapsedSeconds: Int? = nil) {
        print("📊 [AMA-291] startInterval: index=\(index), name=\(name ?? "nil"), elapsedSeconds=\(elapsedSeconds ?? -1)")

        // End any previous interval that wasn't properly closed
        if currentIntervalIndex != nil {
            endCurrentInterval(actualDuration: nil, elapsedSeconds: elapsedSeconds)
        }

        currentIntervalStartTime = Date()
        currentIntervalIndex = index
        currentIntervalStartElapsed = elapsedSeconds

        var interval = IntervalExecution(
            intervalIndex: index,
            plannedKind: kind,
            plannedName: name
        )
        interval.plannedDurationSeconds = plannedDuration
        interval.startedAt = currentIntervalStartTime

        intervals.append(interval)
        print("📊 [AMA-291] startInterval: stored startElapsed=\(currentIntervalStartElapsed ?? -1)")
    }

    /// End the current interval
    /// - Parameters:
    ///   - actualDuration: Actual duration in seconds (nil to calculate from elapsed time or wall clock)
    ///   - elapsedSeconds: Current elapsed seconds in workout (for simulation mode timing)
    func endCurrentInterval(actualDuration: Int?, elapsedSeconds: Int? = nil) {
        print("📊 [AMA-291] endCurrentInterval: currentIndex=\(currentIntervalIndex ?? -1), elapsedSeconds=\(elapsedSeconds ?? -1), startElapsed=\(currentIntervalStartElapsed ?? -1)")

        guard let currentIndex = currentIntervalIndex,
              let idx = intervals.firstIndex(where: { $0.intervalIndex == currentIndex }) else {
            print("📊 [AMA-291] endCurrentInterval: No current interval to end")
            return
        }

        intervals[idx].endedAt = Date()

        if let duration = actualDuration {
            // Explicit duration provided
            intervals[idx].actualDurationSeconds = duration
            print("📊 [AMA-291] endCurrentInterval: Using explicit duration=\(duration)")
        } else if let startElapsed = currentIntervalStartElapsed, let endElapsed = elapsedSeconds {
            // AMA-291: Calculate from elapsed seconds (accurate for simulation mode)
            let calculatedDuration = endElapsed - startElapsed
            intervals[idx].actualDurationSeconds = calculatedDuration
            print("📊 [AMA-291] endCurrentInterval: Calculated duration=\(calculatedDuration) (endElapsed=\(endElapsed) - startElapsed=\(startElapsed))")
        } else if let startTime = currentIntervalStartTime {
            // Fallback to wall-clock time
            let wallClockDuration = Int(Date().timeIntervalSince(startTime))
            intervals[idx].actualDurationSeconds = wallClockDuration
            print("📊 [AMA-291] endCurrentInterval: Fallback to wall-clock duration=\(wallClockDuration)")
        } else {
            print("📊 [AMA-291] endCurrentInterval: WARNING - No duration calculation possible!")
        }

        currentIntervalIndex = nil
        currentIntervalStartTime = nil
        currentIntervalStartElapsed = nil
    }

    /// Mark an interval as skipped
    /// - Parameters:
    ///   - index: Step index in flattened workout
    ///   - kind: Interval type
    ///   - name: Display name
    ///   - reason: Reason for skipping
    func skipInterval(index: Int, kind: String?, name: String?, reason: SkipReason) {
        // End any current interval first
        if currentIntervalIndex != nil {
            endCurrentInterval(actualDuration: nil)
        }

        var interval = IntervalExecution(
            intervalIndex: index,
            plannedKind: kind,
            plannedName: name
        )
        interval.status = .skipped
        interval.skipReason = reason.rawValue
        interval.startedAt = Date()
        interval.endedAt = Date()

        intervals.append(interval)
    }

    // MARK: - Set Tracking

    /// Log a set execution for an interval
    /// - Parameters:
    ///   - intervalIndex: The interval this set belongs to
    ///   - setNumber: Set number (1-based)
    ///   - weight: Weight used (nil if skipped)
    ///   - unit: Weight unit ("lbs" or "kg")
    ///   - reps: Reps completed
    ///   - repsPlanned: Planned reps for this set
    ///   - skipped: Whether set was skipped
    ///   - weightSource: Source of weight (machine, barbell, etc.)
    func logSet(
        intervalIndex: Int,
        setNumber: Int,
        weight: Double?,
        unit: String?,
        reps: Int?,
        repsPlanned: Int? = nil,
        skipped: Bool = false,
        weightSource: WeightSource = .other
    ) {
        print("📊 [AMA-291] logSet called: intervalIndex=\(intervalIndex), setNumber=\(setNumber), reps=\(reps ?? -1), repsPlanned=\(repsPlanned ?? -1), weight=\(weight ?? -1)")

        guard let idx = intervals.firstIndex(where: { $0.intervalIndex == intervalIndex }) else {
            print("📊 [AMA-291] ERROR: Could not find interval with index \(intervalIndex)")
            return
        }

        var setExec = SetExecution(setNumber: setNumber)
        setExec.status = skipped ? .skipped : .completed
        setExec.repsPlanned = repsPlanned
        setExec.repsCompleted = reps
        print("📊 [AMA-291] Created SetExecution: repsPlanned=\(setExec.repsPlanned ?? -1), repsCompleted=\(setExec.repsCompleted ?? -1)")

        // Convert weight to WeightEntry if provided
        if let w = weight, let u = unit {
            setExec.weight = WeightEntry.simple(value: w, unit: u, source: weightSource)
        }

        if intervals[idx].sets == nil {
            intervals[idx].sets = []
        }
        intervals[idx].sets?.append(setExec)
    }

    // MARK: - Build Output

    /// Build the final execution_log dictionary for API submission (v2 format)
    func build() -> [String: Any] {
        print("📊 [AMA-291] build() called with \(intervals.count) intervals")

        // End any unclosed interval
        if currentIntervalIndex != nil {
            endCurrentInterval(actualDuration: nil)
        }

        // Debug: Print all interval data before building
        for interval in intervals {
            print("📊 [AMA-291] Interval \(interval.intervalIndex): \(interval.plannedName ?? "unnamed"), actualDuration=\(interval.actualDurationSeconds ?? -1)")
            if let sets = interval.sets {
                for set in sets {
                    print("📊 [AMA-291]   Set \(set.setNumber): repsPlanned=\(set.repsPlanned ?? -1), repsCompleted=\(set.repsCompleted ?? -1), weight=\(set.weight?.displayLabel ?? "nil")")
                }
            } else {
                print("📊 [AMA-291]   No sets logged for this interval")
            }
        }

        let summary = calculateSummary()

        // Convert intervals to dictionaries
        let intervalDicts: [[String: Any]] = intervals.map { interval in
            var dict: [String: Any] = [
                "interval_index": interval.intervalIndex,
                "status": interval.status.rawValue
            ]

            if let kind = interval.plannedKind { dict["planned_kind"] = kind }
            if let name = interval.plannedName { dict["planned_name"] = name }
            if let plannedDuration = interval.plannedDurationSeconds { dict["planned_duration_seconds"] = plannedDuration }
            if let actualDuration = interval.actualDurationSeconds { dict["actual_duration_seconds"] = actualDuration }
            if let startedAt = interval.startedAt { dict["started_at"] = ISO8601DateFormatter().string(from: startedAt) }
            if let endedAt = interval.endedAt { dict["ended_at"] = ISO8601DateFormatter().string(from: endedAt) }
            if let skipReason = interval.skipReason { dict["skip_reason"] = skipReason }

            if let sets = interval.sets {
                dict["sets"] = sets.map { set -> [String: Any] in
                    var setDict: [String: Any] = [
                        "set_number": set.setNumber,
                        "status": set.status.rawValue
                    ]
                    if let repsPlanned = set.repsPlanned { setDict["reps_planned"] = repsPlanned }
                    if let reps = set.repsCompleted { setDict["reps_completed"] = reps }
                    if let duration = set.durationSeconds { setDict["duration_seconds"] = duration }
                    if let rpe = set.rpe { setDict["rpe"] = rpe }

                    // Convert WeightEntry to v2 format
                    if let weight = set.weight {
                        let componentDicts = weight.components.map { component -> [String: Any] in
                            return [
                                "source": component.source.rawValue,
                                "value": component.value,
                                "unit": component.unit
                            ]
                        }
                        setDict["weight"] = [
                            "components": componentDicts,
                            "display_label": weight.displayLabel
                        ]
                    }
                    return setDict
                }
            }

            return dict
        }

        return [
            "version": 2,
            "intervals": intervalDicts,
            "summary": [
                "total_intervals": summary.totalIntervals,
                "completed": summary.completed,
                "skipped": summary.skipped,
                "not_reached": summary.notReached,
                "completion_percentage": summary.completionPercentage,
                "total_sets": summary.totalSets,
                "sets_completed": summary.setsCompleted,
                "sets_skipped": summary.setsSkipped,
                "total_duration_seconds": summary.totalDurationSeconds,
                "active_duration_seconds": summary.activeDurationSeconds
            ]
        ]
    }

    /// Calculate summary statistics (v2 format)
    private func calculateSummary() -> ExecutionSummary {
        let completed = intervals.filter { $0.status == .completed }.count
        let skipped = intervals.filter { $0.status == .skipped }.count
        let notReached = intervals.filter { $0.status == .notReached }.count
        let total = intervals.count

        // Calculate set statistics
        var totalSets = 0
        var setsCompleted = 0
        var setsSkipped = 0

        for interval in intervals {
            if let sets = interval.sets {
                totalSets += sets.count
                setsCompleted += sets.filter { $0.status == .completed }.count
                setsSkipped += sets.filter { $0.status == .skipped }.count
            }
        }

        // Calculate duration statistics
        let totalDurationSeconds = intervals.compactMap { $0.actualDurationSeconds }.reduce(0, +)

        // Active duration excludes rest intervals
        let activeDurationSeconds = intervals
            .filter { $0.plannedKind != "rest" }
            .compactMap { $0.actualDurationSeconds }
            .reduce(0, +)

        let completionPct = total > 0 ? Double(completed) / Double(total) * 100.0 : 0.0

        return ExecutionSummary(
            totalIntervals: total,
            completed: completed,
            skipped: skipped,
            notReached: notReached,
            completionPercentage: round(completionPct * 10) / 10,
            totalSets: totalSets,
            setsCompleted: setsCompleted,
            setsSkipped: setsSkipped,
            totalDurationSeconds: totalDurationSeconds,
            activeDurationSeconds: activeDurationSeconds
        )
    }

    /// Reset the builder for a new workout
    func reset() {
        intervals = []
        currentIntervalStartTime = nil
        currentIntervalIndex = nil
        currentIntervalStartElapsed = nil
    }

    /// Get current interval count (for debugging)
    var intervalCount: Int {
        intervals.count
    }
}
