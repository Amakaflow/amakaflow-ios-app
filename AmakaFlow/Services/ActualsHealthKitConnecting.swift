//
//  ActualsHealthKitConnecting.swift
//  AmakaFlow
//
//  AMA-2387: Apple Health read-only connect for Actuals (primer → HK prompt).
//  AMA-2419: HKWorkout 30-day pull → Actuals cards (Today / History / Profile).
//

import Foundation
import HealthKit
import UIKit

/// Result of an Actuals Apple Health connect attempt.
enum ActualsHealthKitAuthOutcome: Equatable {
    /// Read path usable — caller may `markConnected(.appleHealth)`.
    case granted
    /// User denied (or HealthKit unavailable) — leave disconnected.
    case denied
    /// Already determined denied; iOS will not re-prompt — open Settings → Health.
    case needsSettings
    /// System prompt finished with no usable read path — stay disconnected.
    case promptCompleted
}

/// Read-authorization state we persist locally (HealthKit does not expose read grant/deny).
enum ActualsHealthKitReadAuthorizationState: String, Equatable {
    case notDetermined
    /// Evidence query succeeded after the system sheet (or mock grant).
    case authorized
    case denied
    /// System sheet completed; access remains unknown / unusable.
    case promptCompleted
}

protocol ActualsHealthKitConnecting: AnyObject {
    var authorizationState: ActualsHealthKitReadAuthorizationState { get }
    /// First prompt → system sheet + evidence query; retry after deny → `.needsSettings`.
    func connect() async -> ActualsHealthKitAuthOutcome
    func openHealthSettings()
}

// MARK: - Workout sample (HealthKit → Actuals)

/// On-device workout row from HealthKit — Strava DTO analogue for Apple Health.
struct ActualsHealthKitWorkoutSample: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let activityType: ActualsWorkoutType
    let startDate: Date
    let durationSeconds: TimeInterval
    let distanceMeters: Double?
    let activeEnergyKcal: Double?
    let averageHeartRateBPM: Double?
}

protocol ActualsHealthKitWorkoutFetching: AnyObject {
    /// Newest-first workouts ending within `daysBack` local days.
    func fetchWorkouts(daysBack: Int) async throws -> [ActualsHealthKitWorkoutSample]
}

enum ActualsHealthKitWorkoutMapping {
    static func workoutType(for activityType: HKWorkoutActivityType) -> ActualsWorkoutType {
        switch activityType {
        case .running, .walking, .hiking, .trackAndField:
            return .run
        case .cycling, .handCycling:
            return .ride
        case .traditionalStrengthTraining, .functionalStrengthTraining,
             .highIntensityIntervalTraining, .crossTraining, .flexibility,
             .yoga, .pilates, .coreTraining, .elliptical:
            return .strength
        default:
            return .other
        }
    }

    static func title(for activityType: HKWorkoutActivityType, metadataName: String?) -> String {
        let trimmed = metadataName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        return displayName(for: activityType)
    }

    // Large HKWorkoutActivityType surface — keep a single lookup table.
    // swiftlint:disable:next cyclomatic_complexity
    static func displayName(for activityType: HKWorkoutActivityType) -> String {
        switch activityType {
        case .running: return "Run"
        case .walking: return "Walk"
        case .hiking: return "Hike"
        case .cycling: return "Ride"
        case .traditionalStrengthTraining, .functionalStrengthTraining:
            return "Strength"
        case .highIntensityIntervalTraining: return "HIIT"
        case .crossTraining: return "Cross Training"
        case .yoga: return "Yoga"
        case .pilates: return "Pilates"
        case .elliptical: return "Elliptical"
        case .rowing: return "Row"
        case .swimming: return "Swim"
        case .mixedCardio: return "Cardio"
        case .cooldown: return "Cooldown"
        default: return "Workout"
        }
    }

    static func sample(from workout: HKWorkout) -> ActualsHealthKitWorkoutSample {
        let distanceMeters = workout.totalDistance?.doubleValue(for: .meter())
        let energy = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
        var avgHR: Double?
        if let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate),
           let avg = workout.statistics(for: hrType)?.averageQuantity() {
            avgHR = avg.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        }
        let customTitle = (workout.metadata?["Title"] as? String)
            ?? (workout.metadata?[HKMetadataKeyWorkoutBrandName] as? String)
        return ActualsHealthKitWorkoutSample(
            id: workout.uuid.uuidString,
            title: title(for: workout.workoutActivityType, metadataName: customTitle),
            activityType: workoutType(for: workout.workoutActivityType),
            startDate: workout.startDate,
            durationSeconds: workout.duration,
            distanceMeters: distanceMeters.flatMap { $0 > 0 ? $0 : nil },
            activeEnergyKcal: energy.flatMap { $0 > 0 ? $0 : nil },
            averageHeartRateBPM: avgHR.flatMap { $0 > 0 ? $0 : nil }
        )
    }
}

// MARK: - Connect outcome applicator (unit-testable)

enum ActualsAppleHealthConnectAction {
    /// Applies connect outcome to the source store / settings opener.
    @MainActor
    static func apply(
        outcome: ActualsHealthKitAuthOutcome,
        store: ActualsSourceConnecting,
        openSettings: () -> Void
    ) {
        switch outcome {
        case .granted:
            store.markConnected(.appleHealth)
        case .denied, .promptCompleted:
            break
        case .needsSettings:
            openSettings()
        }
    }
}

// MARK: - Live HealthKit

@MainActor
final class LiveActualsHealthKitConnector: ActualsHealthKitConnecting {
    private enum Keys {
        static let state = "ama2387.actuals.appleHealth.authState"
    }

    private let defaults: UserDefaults
    private let healthStore: HKHealthStore?
    private let workoutFetcher: any ActualsHealthKitWorkoutFetching
    private let openURL: (URL) -> Void

    private(set) var authorizationState: ActualsHealthKitReadAuthorizationState {
        didSet { defaults.set(authorizationState.rawValue, forKey: Keys.state) }
    }

    init(
        defaults: UserDefaults = .standard,
        healthStore: HKHealthStore? = nil,
        workoutFetcher: (any ActualsHealthKitWorkoutFetching)? = nil,
        openURL: @escaping (URL) -> Void = { UIApplication.shared.open($0) }
    ) {
        self.defaults = defaults
        self.openURL = openURL
        let store: HKHealthStore?
        if HKHealthStore.isHealthDataAvailable() {
            store = healthStore ?? HKHealthStore()
        } else {
            store = nil
        }
        self.healthStore = store
        self.workoutFetcher = workoutFetcher
            ?? LiveActualsHealthKitWorkoutFetcher(healthStore: store)
        if let raw = defaults.string(forKey: Keys.state),
           let stored = ActualsHealthKitReadAuthorizationState(rawValue: raw) {
            authorizationState = stored
        } else {
            authorizationState = .notDetermined
        }
    }

    func connect() async -> ActualsHealthKitAuthOutcome {
        switch authorizationState {
        case .authorized:
            return .granted
        case .denied:
            return .needsSettings
        case .promptCompleted:
            // AMA-2419: older builds left users here after the sheet with no ingest.
            // Retry evidence query without re-prompting; promote to authorized on success.
            do {
                _ = try await workoutFetcher.fetchWorkouts(daysBack: 30)
                authorizationState = .authorized
                return .granted
            } catch {
                return .needsSettings
            }
        case .notDetermined:
            break
        }

        guard let healthStore else {
            authorizationState = .denied
            return .denied
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: Self.readTypes)
            // Evidence: a workout sample query that completes (0+ rows). Empty is OK —
            // HealthKit still won't confess deny, but a successful query after the
            // user finished our primer + system sheet is the dogfood connect signal.
            _ = try await workoutFetcher.fetchWorkouts(daysBack: 30)
            authorizationState = .authorized
            return .granted
        } catch {
            authorizationState = .denied
            return .denied
        }
    }

    func openHealthSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }

    /// Test / debug helper — simulate Don't Allow without a system sheet.
    func markDeniedForTesting() {
        authorizationState = .denied
    }

    private static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) {
            types.insert(heartRate)
        }
        if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(energy)
        }
        return types
    }
}

// MARK: - Live workout fetcher

@MainActor
final class LiveActualsHealthKitWorkoutFetcher: ActualsHealthKitWorkoutFetching {
    private let healthStore: HKHealthStore?

    init(healthStore: HKHealthStore? = nil) {
        if let healthStore {
            self.healthStore = healthStore
        } else if HKHealthStore.isHealthDataAvailable() {
            self.healthStore = HKHealthStore()
        } else {
            self.healthStore = nil
        }
    }

    func fetchWorkouts(daysBack: Int) async throws -> [ActualsHealthKitWorkoutSample] {
        guard let healthStore else { return [] }
        let calendar = Calendar.current
        let end = Date()
        guard let start = calendar.date(byAdding: .day, value: -max(daysBack, 1), to: end) else {
            return []
        }
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: .strictStartDate
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let workouts = (samples as? [HKWorkout]) ?? []
                continuation.resume(returning: workouts)
            }
            healthStore.execute(query)
        }

        return workouts.map(ActualsHealthKitWorkoutMapping.sample(from:))
    }
}

// MARK: - Mock (tests)

@MainActor
final class MockActualsHealthKitConnector: ActualsHealthKitConnecting {
    var authorizationState: ActualsHealthKitReadAuthorizationState
    /// Outcomes returned by successive `connect()` calls (default: grant once).
    var connectOutcomes: [ActualsHealthKitAuthOutcome]
    private(set) var connectCallCount = 0
    private(set) var didOpenHealthSettings = false
    private(set) var openedURLs: [URL] = []

    init(
        authorizationState: ActualsHealthKitReadAuthorizationState = .notDetermined,
        connectOutcomes: [ActualsHealthKitAuthOutcome] = [.granted]
    ) {
        self.authorizationState = authorizationState
        self.connectOutcomes = connectOutcomes
    }

    func connect() async -> ActualsHealthKitAuthOutcome {
        connectCallCount += 1
        guard !connectOutcomes.isEmpty else {
            return .denied
        }
        let index = min(connectCallCount - 1, connectOutcomes.count - 1)
        let outcome = connectOutcomes[index]
        switch outcome {
        case .granted:
            authorizationState = .authorized
        case .denied:
            authorizationState = .denied
        case .promptCompleted:
            authorizationState = .promptCompleted
        case .needsSettings:
            break
        }
        return outcome
    }

    func openHealthSettings() {
        didOpenHealthSettings = true
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openedURLs.append(url)
        }
    }
}

@MainActor
final class MockActualsHealthKitWorkoutFetcher: ActualsHealthKitWorkoutFetching {
    var samples: [ActualsHealthKitWorkoutSample]
    var error: Error?

    init(samples: [ActualsHealthKitWorkoutSample] = [], error: Error? = nil) {
        self.samples = samples
        self.error = error
    }

    func fetchWorkouts(daysBack: Int) async throws -> [ActualsHealthKitWorkoutSample] {
        _ = daysBack
        if let error { throw error }
        return samples
    }
}
