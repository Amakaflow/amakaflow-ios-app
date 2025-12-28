//
//  HealthKitWorkoutManager.swift
//  AmakaFlowWatch Watch App
//
//  Manages HealthKit workout sessions for heart rate and calorie tracking
//

import Foundation
import HealthKit
import Combine

@MainActor
final class HealthKitWorkoutManager: NSObject, ObservableObject {
    static let shared = HealthKitWorkoutManager()

    // MARK: - Published Properties

    @Published private(set) var heartRate: Double = 0
    @Published private(set) var activeCalories: Double = 0
    @Published private(set) var isSessionActive = false
    @Published private(set) var authorizationStatus: HKAuthorizationStatus = .notDetermined

    // MARK: - Private Properties

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    // Callback for sending HR updates to phone
    var onHeartRateUpdate: ((Double, Double) -> Void)?

    private override init() {
        super.init()
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("❤️ HealthKit not available")
            return false
        }

        // Types to read
        let typesToRead: Set<HKObjectType> = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]

        // Types to write (workout)
        let typesToWrite: Set<HKSampleType> = [
            HKQuantityType.workoutType()
        ]

        do {
            try await healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead)
            let hrStatus = healthStore.authorizationStatus(for: HKQuantityType.quantityType(forIdentifier: .heartRate)!)
            authorizationStatus = hrStatus
            print("❤️ HealthKit authorization complete: \(hrStatus.rawValue)")
            return hrStatus == .sharingAuthorized || hrStatus == .notDetermined
        } catch {
            print("❤️ HealthKit authorization failed: \(error)")
            return false
        }
    }

    // MARK: - Session Management

    func startSession(activityType: HKWorkoutActivityType = .functionalStrengthTraining) async throws {
        guard !isSessionActive else {
            print("❤️ Session already active")
            return
        }

        // Request authorization if needed
        _ = await requestAuthorization()

        let config = HKWorkoutConfiguration()
        config.activityType = activityType
        config.locationType = .indoor

        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            builder = session?.associatedWorkoutBuilder()

            session?.delegate = self
            builder?.delegate = self

            // Set data source for live workout data
            builder?.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: config
            )

            // Start the session
            let startDate = Date()
            session?.startActivity(with: startDate)
            try await builder?.beginCollection(at: startDate)

            isSessionActive = true
            print("❤️ Workout session started")

        } catch {
            print("❤️ Failed to start workout session: \(error)")
            throw error
        }
    }

    func endSession() async {
        guard isSessionActive, let session = session, let builder = builder else {
            print("❤️ No active session to end")
            return
        }

        let endDate = Date()
        session.end()

        do {
            try await builder.endCollection(at: endDate)

            // Optionally save the workout to HealthKit
            // Uncomment if you want to save the workout
            // try await builder.finishWorkout()

            print("❤️ Workout session ended")
        } catch {
            print("❤️ Failed to end workout session: \(error)")
        }

        self.session = nil
        self.builder = nil
        isSessionActive = false
        heartRate = 0
        activeCalories = 0
    }

    func pauseSession() {
        session?.pause()
        print("❤️ Session paused")
    }

    func resumeSession() {
        session?.resume()
        print("❤️ Session resumed")
    }

    // MARK: - Process Workout Data

    private func process(_ statistics: HKStatistics) {
        let quantityType = statistics.quantityType

        switch quantityType {
        case HKQuantityType.quantityType(forIdentifier: .heartRate):
            let unit = HKUnit.count().unitDivided(by: .minute())
            if let value = statistics.mostRecentQuantity()?.doubleValue(for: unit) {
                heartRate = value
                print("❤️ HR: \(Int(value)) bpm")
                onHeartRateUpdate?(heartRate, activeCalories)
            }

        case HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned):
            let unit = HKUnit.kilocalorie()
            if let value = statistics.sumQuantity()?.doubleValue(for: unit) {
                activeCalories = value
                print("❤️ Calories: \(Int(value)) kcal")
                onHeartRateUpdate?(heartRate, activeCalories)
            }

        default:
            break
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension HealthKitWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            print("❤️ Session state: \(fromState.rawValue) → \(toState.rawValue)")

            switch toState {
            case .running:
                isSessionActive = true
            case .paused:
                // Still active but paused
                break
            case .ended, .stopped:
                isSessionActive = false
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        print("❤️ Session failed: \(error)")
        Task { @MainActor in
            isSessionActive = false
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension HealthKitWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType,
                  let statistics = workoutBuilder.statistics(for: quantityType) else {
                continue
            }

            Task { @MainActor in
                process(statistics)
            }
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Handle workout events if needed
    }
}
