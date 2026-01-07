//
//  SimulatedHealthProvider.swift
//  AmakaFlow
//
//  Generates realistic heart rate curves and calories for simulation mode.
//  Part of AMA-271: Workout Simulation Mode
//

import Foundation

// MARK: - HR Sample

/// A single heart rate measurement for simulation
struct SimulatedHRSample: Codable, Equatable {
    let timestamp: Date
    let value: Int  // BPM
}

// MARK: - Simulated Health Data

/// Aggregated health data from a simulated workout
struct SimulatedHealthData: Codable, Equatable {
    let hrSamples: [SimulatedHRSample]
    let avgHR: Int
    let maxHR: Int
    let calories: Int
}

// MARK: - Health Data Provider Protocol

/// Protocol for health data generation
@MainActor
protocol HealthDataProvider: AnyObject {
    /// Current heart rate
    var currentHR: Int { get }

    /// Generate HR samples for a work interval
    func simulateWork(duration: TimeInterval, intensity: ExerciseIntensity) -> [SimulatedHRSample]

    /// Generate HR samples for a rest interval
    func simulateRest(duration: TimeInterval) -> [SimulatedHRSample]

    /// Get all collected health data
    func getCollectedData() -> SimulatedHealthData

    /// Reset for new workout
    func reset()
}

// MARK: - Simulated Health Provider

/// Generates realistic heart rate curves and calorie estimates
@MainActor
final class SimulatedHealthProvider: HealthDataProvider {
    private let profile: HRProfile
    private(set) var currentHR: Int
    private var samples: [SimulatedHRSample] = []
    private var totalCalories: Double = 0
    private var lastSampleTime: Date

    init(profile: HRProfile) {
        self.profile = profile
        self.currentHR = profile.restingHR
        self.lastSampleTime = Date()
    }

    /// Generate HR samples during work interval
    func simulateWork(duration: TimeInterval, intensity: ExerciseIntensity) -> [SimulatedHRSample] {
        let targetHR = profile.hrForIntensity(intensity)
        let newSamples = generateWorkCurve(from: currentHR, to: targetHR, duration: duration, intensity: intensity)
        samples.append(contentsOf: newSamples)
        return newSamples
    }

    /// Generate HR samples during rest
    func simulateRest(duration: TimeInterval) -> [SimulatedHRSample] {
        let newSamples = generateRecoveryCurve(from: currentHR, duration: duration)
        samples.append(contentsOf: newSamples)
        return newSamples
    }

    /// Generate work curve - HR rises toward target
    private func generateWorkCurve(from startHR: Int, to targetHR: Int, duration: TimeInterval, intensity: ExerciseIntensity) -> [SimulatedHRSample] {
        var result: [SimulatedHRSample] = []
        let sampleInterval: TimeInterval = 5.0  // Sample every 5 seconds
        let sampleCount = max(1, Int(duration / sampleInterval))

        for i in 0...sampleCount {
            let progress = Double(i) / Double(sampleCount)

            // Exponential ramp up - faster initial rise, then plateau
            let curve = 1 - pow(1 - progress, 2)

            let baseHR = startHR + Int(Double(targetHR - startHR) * curve)

            // Add realistic noise (+/- 3 BPM)
            let noise = Int.random(in: -3...3)
            let noisyHR = max(profile.restingHR, min(profile.maxHR, baseHR + noise))

            let sampleTime = lastSampleTime.addingTimeInterval(Double(i) * sampleInterval)
            result.append(SimulatedHRSample(timestamp: sampleTime, value: noisyHR))

            currentHR = noisyHR
        }

        // Update last sample time
        lastSampleTime = lastSampleTime.addingTimeInterval(duration)

        // Calculate calories (rough estimate: MET-based)
        // Strength training: ~3-6 METs depending on intensity
        let mets: Double
        switch intensity {
        case .rest: mets = 1.0
        case .low: mets = 2.5
        case .moderate: mets = 4.0
        case .high: mets = 6.0
        case .max: mets = 8.0
        }

        // Calories = METs * weight(kg) * duration(hours)
        // Assume 70kg average, convert to simple cal/min
        let calPerMinute = mets * 70.0 / 60.0  // ~3.5-7 cal/min
        totalCalories += calPerMinute * (duration / 60.0)

        return result
    }

    /// Generate recovery curve - HR drops toward resting
    private func generateRecoveryCurve(from startHR: Int, duration: TimeInterval) -> [SimulatedHRSample] {
        var result: [SimulatedHRSample] = []
        let sampleInterval: TimeInterval = 5.0
        let sampleCount = max(1, Int(duration / sampleInterval))

        var hr = Double(startHR)

        for i in 0...sampleCount {
            // Exponential decay toward resting HR
            let timeInMinutes = Double(i) * sampleInterval / 60.0
            let decay = exp(-profile.recoveryRate * timeInMinutes)
            hr = Double(profile.restingHR) + (Double(startHR - profile.restingHR) * decay)

            // Add noise
            let noise = Int.random(in: -2...2)
            let noisyHR = max(profile.restingHR, Int(hr) + noise)

            let sampleTime = lastSampleTime.addingTimeInterval(Double(i) * sampleInterval)
            result.append(SimulatedHRSample(timestamp: sampleTime, value: noisyHR))

            currentHR = noisyHR
        }

        lastSampleTime = lastSampleTime.addingTimeInterval(duration)

        // Minimal calories during rest
        totalCalories += 1.0 * 70.0 / 60.0 * (duration / 60.0)

        return result
    }

    /// Get aggregated health data
    func getCollectedData() -> SimulatedHealthData {
        let avgHR: Int
        let maxHR: Int

        if samples.isEmpty {
            avgHR = profile.restingHR
            maxHR = profile.restingHR
        } else {
            let sum = samples.reduce(0) { $0 + $1.value }
            avgHR = sum / samples.count
            maxHR = samples.map(\.value).max() ?? profile.restingHR
        }

        return SimulatedHealthData(
            hrSamples: samples,
            avgHR: avgHR,
            maxHR: maxHR,
            calories: Int(totalCalories)
        )
    }

    /// Reset for new workout
    func reset() {
        currentHR = profile.restingHR
        samples = []
        totalCalories = 0
        lastSampleTime = Date()
    }
}
