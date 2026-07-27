//
//  WorkoutKitConverter.swift
//  AmakaFlow
//
//  Converts Workout model to WKPlanDTO for WorkoutKitSync
//

import Foundation
import OSLog
import WorkoutKitSync
#if canImport(Sentry)
import Sentry
#endif

private let workoutKitConverterLog = Logger(
    subsystem: "com.myamaka.AmakaFlowCompanion",
    category: "WorkoutKitConverter"
)

private func compactLoadToken(_ load: String) -> String {
    let trimmed = load.trimmingCharacters(in: .whitespacesAndNewlines)
    // Allow-list units so coaching cues like "10 sec" / "3 sets" are not compacted as loads.
    let pattern = #"^\d+(\.\d+)?\s*(lbs?|kgs?|%)$"#
    if trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
        return trimmed.replacingOccurrences(of: " ", with: "")
    }
    return trimmed
}

private func displayName(exercise: String, load: String?) -> String {
    guard let load, !load.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return exercise
    }
    return "\(exercise) · \(compactLoadToken(load))"
}

/// Service for converting Workout models to WorkoutKit DTO format
@available(iOS 18.0, watchOS 11.0, *)
class WorkoutKitConverter {
    
    static let shared = WorkoutKitConverter()
    
    private init() {}
    
    /// Convert Workout model to WKPlanDTO
    /// - Parameter workout: The workout to convert
    /// - Returns: WKPlanDTO ready for WorkoutKit
    /// - Throws: ConversionError if conversion fails
    func convertToWKPlanDTO(_ workout: Workout) throws -> WKPlanDTO {
        // Map sport type
        let sportType = mapSportType(workout.sport)
        
        // Convert intervals
        let intervals = try convertIntervals(workout.intervals)
        
        // Create DTO
        let dto = WKPlanDTO(
            title: workout.name,
            sportType: sportType,
            schedule: nil, // Schedule can be set later if needed
            intervals: intervals
        )
        
        return dto
    }
    
    /// Save workout to WorkoutKit
    /// - Parameter workout: The workout to save
    /// - Throws: ConversionError or WorkoutPlanError
    func saveToWorkoutKit(_ workout: Workout) async throws {
        #if canImport(Sentry)
        // Sentry performance transaction for WorkoutKit / HealthKit write (AMA-1083)
        let tx = SentryService.shared.startTransaction(name: "workoutkit.save", operation: "healthkit.write")
        do {
            let dto: WKPlanDTO
            let convertSpan = tx.startChild(operation: "workoutkit.convert")
            do {
                dto = try convertToWKPlanDTO(workout)
                convertSpan.finish(status: .ok)
            } catch {
                convertSpan.finish(status: .internalError)
                tx.finish(status: .internalError)
                throw error
            }

            let saveSpan = tx.startChild(operation: "healthkit.write")
            do {
                try await WorkoutKitSync.default.save(dto, scheduleAt: nil)
                saveSpan.finish(status: .ok)
            } catch {
                saveSpan.finish(status: .internalError)
                tx.finish(status: .internalError)
                throw error
            }

            tx.finish(status: .ok)
        }
        #else
        let dto = try convertToWKPlanDTO(workout)
        try await WorkoutKitSync.default.save(dto, scheduleAt: nil)
        #endif
    }
    
    /// Parse and save workout from JSON string
    /// - Parameter jsonString: JSON string in WKPlanDTO format
    /// - Throws: WorkoutPlanError if parsing/saving fails
    static func parseAndSave(_ jsonString: String) async throws {
        try await WorkoutKitSync.default.parseAndSave(from: jsonString)
    }
    
    // MARK: - Private Helpers
    
    /// Map WorkoutSport to WorkoutKit sport type string
    func mapSportType(_ sport: WorkoutSport) -> String {
        switch sport {
        case .running:
            return "running"
        case .cycling:
            return "cycling"
        case .strength:
            return "strengthTraining"
        case .mobility:
            return "other" // WorkoutKit doesn't have mobility, use other
        case .swimming:
            return "swimming"
        case .cardio:
            return "mixedCardio"
        case .other:
            return "other"
        }
    }
    
    /// Convert WorkoutInterval array to WKPlanDTO.Interval array
    private func convertIntervals(_ intervals: [WorkoutInterval]) throws -> [WKPlanDTO.Interval] {
        try intervals.map { try convertInterval($0) }
    }
    
    /// Convert single WorkoutInterval to WKPlanDTO.Interval
    private func convertInterval(_ interval: WorkoutInterval) throws -> WKPlanDTO.Interval {
        switch interval {
        case .warmup(let seconds, let target):
            let wkTarget = convertTarget(target)
            return .warmup(seconds: seconds, target: wkTarget)
            
        case .cooldown(let seconds, let target):
            let wkTarget = convertTarget(target)
            return .cooldown(seconds: seconds, target: wkTarget)
            
        case .time(let seconds, let target):
            let wkTarget = convertTarget(target)
            let step = WKPlanDTO.Interval.Step(
                kind: "time",
                seconds: seconds,
                meters: nil,
                reps: nil,
                name: nil,
                load: nil,
                restSec: nil,
                target: wkTarget
            )
            return .step(step)
            
        case .reps(let sets, let reps, let name, let load, let restSec, _):
            if let sets, sets < 1 {
                workoutKitConverterLog.warning(
                    "WorkoutKitConverter: received sets=\(sets, privacy: .public) for '\(name, privacy: .public)'; clamping to 1"
                )
            }
            let setCount = max(sets ?? 1, 1)
            let rest = (restSec ?? 0) > 0 ? restSec : nil
            let step = WKPlanDTO.Interval.Step(
                kind: "reps",
                seconds: nil,
                meters: nil,
                reps: reps,
                name: displayName(exercise: name, load: load),
                load: nil, // convertLoad remains stub
                restSec: rest,
                target: nil
            )
            return .repeatSet(reps: setCount, intervals: [step])
            
        case .distance(let meters, let target):
            let wkTarget = convertTarget(target)
            let step = WKPlanDTO.Interval.Step(
                kind: "distance",
                seconds: nil,
                meters: Double(meters),
                reps: nil,
                name: nil,
                load: nil,
                restSec: nil,
                target: wkTarget
            )
            return .step(step)
            
        case .repeat(let reps, let intervals):
            // Nested `.reps` converts to `.repeatSet`; expand those steps into this circuit
            // (set count × steps per outer round). Skip warmup/cooldown inside a repeat.
            var steps: [WKPlanDTO.Interval.Step] = []
            for interval in intervals {
                switch try convertInterval(interval) {
                case .step(let step):
                    steps.append(step)
                case .repeatSet(let nestedReps, let nestedSteps):
                    let count = max(nestedReps, 1)
                    for _ in 0..<count {
                        steps.append(contentsOf: nestedSteps)
                    }
                default:
                    continue
                }
            }
            return .repeatSet(reps: reps, intervals: steps)

        case .rest(let seconds):
            // Convert rest to a time-based step
            let step = WKPlanDTO.Interval.Step(
                kind: "rest",
                seconds: seconds,
                meters: nil,
                reps: nil,
                name: "Rest",
                load: nil,
                restSec: nil,
                target: nil
            )
            return .step(step)
        }
    }
    
    /// Convert optional target string to WKPlanDTO.Interval.Target
    private func convertTarget(_ target: String?) -> WKPlanDTO.Interval.Target? {
        guard let target = target, !target.isEmpty else { return nil }
        // Parse target if needed (e.g., "hrZone:3" or "pace:5.0")
        // For now, return nil as target parsing is complex
        // TODO: Implement target parsing if needed
        _ = target // Suppress unused variable warning
        return nil
    }
    
    /// Convert optional load string to WKPlanDTO.Interval.Load
    private func convertLoad(_ load: String?) -> WKPlanDTO.Interval.Load? {
        guard let load = load, !load.isEmpty else { return nil }
        // Parse load string (e.g., "50kg" or "100lbs")
        // For now, return nil as load parsing is complex
        // TODO: Implement load parsing if needed
        _ = load // Suppress unused variable warning
        return nil
    }
}

// MARK: - Errors
enum ConversionError: LocalizedError {
    case invalidIntervalType
    case invalidLoadFormat
    case invalidTargetFormat
    
    var errorDescription: String? {
        switch self {
        case .invalidIntervalType:
            return "Invalid interval type"
        case .invalidLoadFormat:
            return "Invalid load format"
        case .invalidTargetFormat:
            return "Invalid target format"
        }
    }
}

