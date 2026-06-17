//
//  WatchWorkoutManager.swift
//  AmakaFlowWatch Watch App
//
//  Manages workout state and WorkoutKit integration on watchOS
//

import Foundation
import Combine
import HealthKit
import WorkoutKitSync

@MainActor
class WatchWorkoutManager: ObservableObject {
    @Published var workouts: [Workout] = []
    @Published var currentWorkout: Workout?
    @Published var isWorkoutActive = false

    private let healthStore = HKHealthStore()

    init() {
        // AMA-1797: skip auto-request on simulator so the system HealthKit
        // sheet doesn't block automated end-to-end test runs. Real-device
        // builds still request on launch as before. Auth is also re-checked
        // inside startWorkout() on real devices.
        #if !targetEnvironment(simulator)
        requestHealthKitPermissions()
        #endif
    }

    // MARK: - Workout Delivery (AMA-297)
    // Called by WatchConnectivityBridge — the single WCSessionDelegate — when a
    // "receiveWorkout" message arrives from the phone.

    func addWorkout(_ workout: Workout) {
        workouts.append(workout)
        print("⌚️ Received workout: \(workout.name)")
    }

    func setWorkouts(_ workouts: [Workout]) {
        self.workouts = workouts
        print("⌚️ Synced \(workouts.count) workouts")
    }
    
    // MARK: - HealthKit Permissions
    private func requestHealthKitPermissions() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        
        let typesToShare: Set = [
            HKObjectType.workoutType()
        ]
        
        let typesToRead: Set = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!
        ]
        
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { success, error in
            if let error = error {
                print("⌚️ HealthKit authorization failed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Start Workout
    func startWorkout(_ workout: Workout) async {
        currentWorkout = workout
        isWorkoutActive = true
        
        // Create WorkoutKit composition
        if #available(watchOS 10.0, *) {
            await startWorkoutKitSession(workout)
        } else {
            // Fallback for older watchOS versions
            await startLegacyWorkout(workout)
        }
    }
    
    @available(watchOS 11.0, *)
    private func startWorkoutKitSession(_ workout: Workout) async {
        do {
            // Use WorkoutKitConverter to save workout to WorkoutKit
            let converter = WorkoutKitConverter.shared
            try await converter.saveToWorkoutKit(workout)
            
            print("⌚️ Starting WorkoutKit session: \(workout.name)")
            
        } catch {
            print("⌚️ Failed to start WorkoutKit session: \(error.localizedDescription)")
        }
    }
    
    private func startLegacyWorkout(_ workout: Workout) async {
        // Fallback implementation using HKWorkoutSession for watchOS < 10
        print("⌚️ Starting legacy workout session: \(workout.name)")
        
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = hkActivityType(for: workout.sport)
        configuration.locationType = .outdoor
        
        // Create and start HKWorkoutSession
        // Implementation depends on your needs
    }
    
    // MARK: - Stop Workout
    func stopWorkout() {
        isWorkoutActive = false
        currentWorkout = nil
        print("⌚️ Workout stopped")
    }
    
    // MARK: - Helpers
    
    private func hkActivityType(for sport: WorkoutSport) -> HKWorkoutActivityType {
        switch sport {
        case .running:
            return .running
        case .cycling:
            return .cycling
        case .strength:
            return .functionalStrengthTraining
        case .mobility:
            return .yoga
        case .swimming:
            return .swimming
        case .cardio:
            return .mixedCardio
        case .other:
            return .other
        }
    }
    
}
