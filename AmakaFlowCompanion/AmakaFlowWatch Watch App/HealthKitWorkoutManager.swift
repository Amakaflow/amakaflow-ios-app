//
//  HealthKitWorkoutManager.swift
//  AmakaFlowWatch Watch App
//
//  Manages HealthKit workout sessions for heart rate and calorie tracking
//

import Combine
import Foundation
import HealthKit

protocol WorkoutSessionBuilding: AnyObject {
    func endCollection(at end: Date) async throws
    func finishWorkout() async throws -> HKWorkout?
}

extension HKLiveWorkoutBuilder: WorkoutSessionBuilding {}

@MainActor
final class HealthKitWorkoutManager: NSObject, ObservableObject {
    static let shared = HealthKitWorkoutManager()

    // MARK: - Published Properties

    @Published private(set) var heartRate: Double = 0
    @Published private(set) var activeCalories: Double = 0
    /// Active + basal when basal is available; otherwise equals active.
    @Published private(set) var totalCalories: Double = 0
    @Published private(set) var isSessionActive = false
    @Published private(set) var authorizationStatus: HKAuthorizationStatus = .notDetermined
    private var basalCalories: Double = 0

    // MARK: - Private Properties

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var liveWorkoutBuilder: HKLiveWorkoutBuilder?
    private var builder: (any WorkoutSessionBuilding)?

    // Multicast callbacks for HR updates (supports multiple consumers without clobbering)
    private var heartRateHandlers: [UUID: (Double, Double) -> Void] = [:]

    @discardableResult
    func addHeartRateHandler(_ handler: @escaping (Double, Double) -> Void) -> UUID {
        let token = UUID()
        heartRateHandlers[token] = handler
        return token
    }

    func removeHeartRateHandler(_ token: UUID) {
        heartRateHandlers.removeValue(forKey: token)
    }

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
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned)!
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

    func startSession(activityType: HKWorkoutActivityType) async throws {
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
            let liveBuilder = session?.associatedWorkoutBuilder()
            liveWorkoutBuilder = liveBuilder
            builder = liveBuilder

            session?.delegate = self
            liveBuilder?.delegate = self

            // Set data source for live workout data
            let dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: config
            )
            if let basalType = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned) {
                dataSource.enableCollection(for: basalType, predicate: nil)
            }
            liveBuilder?.dataSource = dataSource

            // Start the session
            let startDate = Date()
            session?.startActivity(with: startDate)
            try await liveBuilder?.beginCollection(at: startDate)

            basalCalories = 0
            activeCalories = 0
            totalCalories = 0
            heartRate = 0
            isSessionActive = true
            print("❤️ Workout session started")
        } catch {
            print("❤️ Failed to start workout session: \(error)")
            throw error
        }
    }

    func endSession() async {
        guard isSessionActive, let builder = builder else {
            print("❤️ No active session to end")
            return
        }

        let endDate = Date()
        session?.end()

        do {
            try await builder.endCollection(at: endDate)
            try await builder.finishWorkout()

            print("❤️ Workout session ended")
            clearSessionState()
        } catch {
            print("❤️ Failed to end workout session: \(error)")
            clearSessionState()
        }
    }

    /// AMA-2420 — discard an in-progress session without saving an HKWorkout.
    func discardSession() async {
        guard isSessionActive else {
            print("❤️ No active session to discard")
            return
        }

        session?.end()
        if let liveBuilder = liveWorkoutBuilder {
            liveBuilder.discardWorkout()
        } else if let builder = builder {
            // Test seam / non-live builders: end collection without finish.
            do {
                try await builder.endCollection(at: Date())
            } catch {
                print("❤️ Discard endCollection failed: \(error)")
            }
        }

        print("❤️ Workout session discarded")
        clearSessionState()
    }

    private func clearSessionState() {
        session = nil
        builder = nil
        liveWorkoutBuilder = nil
        isSessionActive = false
        heartRate = 0
        activeCalories = 0
        basalCalories = 0
        totalCalories = 0
        // Keep registered heart-rate handlers across sessions so consumers stay wired.
    }

    private func publishCalories() {
        totalCalories = activeCalories + basalCalories
    }

#if DEBUG
    /// Test seam for Issue #300 regression coverage.
    func setBuilderForTesting(_ builder: any WorkoutSessionBuilding, isSessionActive: Bool = true) {
        self.builder = builder
        self.liveWorkoutBuilder = nil
        self.isSessionActive = isSessionActive
    }
#endif

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
                heartRateHandlers.values.forEach { $0(heartRate, activeCalories) }
            }

        case HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned):
            let unit = HKUnit.kilocalorie()
            if let value = statistics.sumQuantity()?.doubleValue(for: unit) {
                activeCalories = value
                print("❤️ Active cal: \(Int(value)) kcal")
                publishCalories()
            }

        case HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned):
            let unit = HKUnit.kilocalorie()
            if let value = statistics.sumQuantity()?.doubleValue(for: unit) {
                basalCalories = value
                print("❤️ Basal cal: \(Int(value)) kcal")
                publishCalories()
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
