//
//  ActualsHealthKitConnecting.swift
//  AmakaFlow
//
//  AMA-2387: Apple Health read-only connect for Actuals (primer → HK prompt).
//

import Foundation
import HealthKit
import UIKit

/// Result of an Actuals Apple Health connect attempt.
enum ActualsHealthKitAuthOutcome: Equatable {
    /// User granted read access — caller should `markConnected(.appleHealth)`.
    case granted
    /// User denied (or HealthKit unavailable) — leave disconnected.
    case denied
    /// Already determined denied; iOS will not re-prompt — open Settings → Health.
    case needsSettings
}

/// Read-authorization state we persist locally (HealthKit does not expose read grant/deny).
enum ActualsHealthKitReadAuthorizationState: String, Equatable {
    case notDetermined
    case authorized
    case denied
}

protocol ActualsHealthKitConnecting: AnyObject {
    var authorizationState: ActualsHealthKitReadAuthorizationState { get }
    /// First prompt → system sheet; retry after deny → `.needsSettings`.
    func connect() async -> ActualsHealthKitAuthOutcome
    func openHealthSettings()
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
        case .denied:
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
    private let openURL: (URL) -> Void

    private(set) var authorizationState: ActualsHealthKitReadAuthorizationState {
        didSet { defaults.set(authorizationState.rawValue, forKey: Keys.state) }
    }

    init(
        defaults: UserDefaults = .standard,
        healthStore: HKHealthStore? = nil,
        openURL: @escaping (URL) -> Void = { UIApplication.shared.open($0) }
    ) {
        self.defaults = defaults
        self.openURL = openURL
        if HKHealthStore.isHealthDataAvailable() {
            self.healthStore = healthStore ?? HKHealthStore()
        } else {
            self.healthStore = nil
        }
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
        case .notDetermined:
            break
        }

        guard let healthStore else {
            authorizationState = .denied
            return .denied
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: Self.readTypes)
            // HealthKit does not report read grant/deny. Treat a successful prompt as granted;
            // ingest will no-op if the user toggled types off. Deny path is covered by mock +
            // UITEST / explicit markDenied for dogfood.
            authorizationState = .authorized
            return .granted
        } catch {
            authorizationState = .denied
            return .denied
        }
    }

    func openHealthSettings() {
        // App Settings is where the user re-enables Health access after Don't Allow.
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
        let index = min(connectCallCount - 1, connectOutcomes.count - 1)
        let outcome = connectOutcomes[index]
        switch outcome {
        case .granted:
            authorizationState = .authorized
        case .denied:
            authorizationState = .denied
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
