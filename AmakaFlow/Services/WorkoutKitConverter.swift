//
//  WorkoutKitConverter.swift
//  AmakaFlow
//
//  Converts Workout model to WKPlanDTO for WorkoutKitSync
//

import Foundation
import WorkoutKitSync

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
        let dto = try convertToWKPlanDTO(workout)
        try await WorkoutKitSync.default.save(dto, scheduleAt: nil)
    }
    
    /// Parse and save workout from JSON string
    /// - Parameter jsonString: JSON string in WKPlanDTO format
    /// - Throws: WorkoutPlanError if parsing/saving fails
    static func parseAndSave(_ jsonString: String) async throws {
        try await WorkoutKitSync.default.parseAndSave(from: jsonString)
    }
    
    // MARK: - Private Helpers
    
    /// Map WorkoutSport to WorkoutKit sport type string
    private func mapSportType(_ sport: WorkoutSport) -> String {
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
            
        case .reps(let reps, let name, let load, let restSec, _):
            let wkLoad = convertLoad(load)
            let step = WKPlanDTO.Interval.Step(
                kind: "reps",
                seconds: nil,
                meters: nil,
                reps: reps,
                name: name,
                load: wkLoad,
                restSec: restSec,
                target: nil
            )
            return .step(step)
            
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
            let steps = try intervals.compactMap { interval -> WKPlanDTO.Interval.Step? in
                guard case .step(let step) = try convertInterval(interval) else {
                    // Repeat sets can only contain steps, not warmup/cooldown
                    return nil
                }
                return step
            }
            return .repeatSet(reps: reps, intervals: steps)
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

