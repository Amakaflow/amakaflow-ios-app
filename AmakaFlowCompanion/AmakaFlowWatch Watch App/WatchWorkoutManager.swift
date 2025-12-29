//
//  WatchWorkoutManager.swift
//  AmakaFlowWatch Watch App
//
//  Manages workout state and WorkoutKit integration on watchOS
//

import Foundation
import Combine
import WatchConnectivity
import HealthKit
import WorkoutKitSync

@MainActor
class WatchWorkoutManager: NSObject, ObservableObject {
    @Published var workouts: [Workout] = []
    @Published var currentWorkout: Workout?
    @Published var isWorkoutActive = false
    
    private var session: WCSession?
    private let healthStore = HKHealthStore()
    
    override init() {
        super.init()
        
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
        
        requestHealthKitPermissions()
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

// MARK: - WCSessionDelegate
extension WatchWorkoutManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("⌚️ WCSession activation failed: \(error.localizedDescription)")
        } else {
            print("⌚️ WCSession activated on watch")
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        print("⌚️ Received message: \(message)")
        
        if let action = message["action"] as? String {
            switch action {
            case "receiveWorkout":
                // Decode workout from message
                if let workoutDict = message["workout"] as? [String: Any] {
                    // Decode in MainActor context to avoid isolation issues
                    Task { @MainActor in
                        do {
                            let workoutData = try JSONSerialization.data(withJSONObject: workoutDict)
                            let decoder = JSONDecoder()
                            let workout = try decoder.decode(Workout.self, from: workoutData)
                            
                            self.workouts.append(workout)
                            print("⌚️ Received workout: \(workout.name)")
                            
                            replyHandler(["status": "received"])
                        } catch {
                            print("⌚️ Failed to decode workout: \(error.localizedDescription)")
                            replyHandler(["status": "error", "message": error.localizedDescription])
                        }
                    }
                    return
                }
                
            default:
                replyHandler(["status": "unknown_action"])
            }
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        // Handle background transfer of workouts
        if let action = userInfo["action"] as? String, action == "syncWorkouts" {
            if let workoutsArray = userInfo["workouts"] as? [[String: Any]] {
                // Decode in MainActor context to avoid isolation issues
                Task { @MainActor in
                    do {
                        let workoutsData = try JSONSerialization.data(withJSONObject: workoutsArray)
                        let decoder = JSONDecoder()
                        let workouts = try decoder.decode([Workout].self, from: workoutsData)
                        
                        self.workouts = workouts
                        print("⌚️ Synced \(workouts.count) workouts")
                    } catch {
                        print("⌚️ Failed to sync workouts: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}
