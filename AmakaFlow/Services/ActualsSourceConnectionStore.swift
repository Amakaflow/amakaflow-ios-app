//
//  ActualsSourceConnectionStore.swift
//  AmakaFlow
//
//  AMA-2387: tracks Apple Health / Garmin / Strava connection for Today teach card.
//

import Combine
import Foundation

enum ActualsSourceProvider: String, CaseIterable, Identifiable, Codable, Hashable {
    case appleHealth
    case garmin
    case strava

    var id: String { rawValue }

    var accessibilityRowID: String { "af_actuals_source_row_\(rawValue)" }
    var accessibilityConnectID: String { "af_actuals_connect_\(rawValue)" }
}

protocol ActualsSourceConnecting: AnyObject {
    var hasAnySourceConnected: Bool { get }
    var hasEverConnected: Bool { get }
    func isConnected(_ provider: ActualsSourceProvider) -> Bool
    func markConnected(_ provider: ActualsSourceProvider)
    func markDisconnected(_ provider: ActualsSourceProvider)
}

@MainActor
final class ActualsSourceConnectionStore: ObservableObject, ActualsSourceConnecting {
    private enum Keys {
        static let connected = "ama2387.actuals.connectedProviders"
        static let everConnected = "ama2387.actuals.hasEverConnected"
    }

    private let defaults: UserDefaults

    @Published private(set) var connectedProviders: Set<ActualsSourceProvider>

    /// Providers linked in this process — drives `LINKED ✓ JUST NOW` badge.
    @Published private(set) var freshlyLinkedProviders: Set<ActualsSourceProvider> = []

    var hasAnySourceConnected: Bool { !connectedProviders.isEmpty }

    private(set) var hasEverConnected: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.stringArray(forKey: Keys.connected) ?? []
        let connected = Set(raw.compactMap(ActualsSourceProvider.init(rawValue:)))
        connectedProviders = connected
        // Assign stored props without didSet — persist via markConnected / explicit write.
        hasEverConnected = defaults.bool(forKey: Keys.everConnected) || !connected.isEmpty
    }

    func isConnected(_ provider: ActualsSourceProvider) -> Bool {
        connectedProviders.contains(provider)
    }

    func isFreshlyLinked(_ provider: ActualsSourceProvider) -> Bool {
        freshlyLinkedProviders.contains(provider)
    }

    func markConnected(_ provider: ActualsSourceProvider) {
        connectedProviders.insert(provider)
        freshlyLinkedProviders.insert(provider)
        hasEverConnected = true
        defaults.set(true, forKey: Keys.everConnected)
        persistConnected()
    }

    func markDisconnected(_ provider: ActualsSourceProvider) {
        connectedProviders.remove(provider)
        freshlyLinkedProviders.remove(provider)
        persistConnected()
    }

    func clearFreshLink(_ provider: ActualsSourceProvider) {
        freshlyLinkedProviders.remove(provider)
    }

    private func persistConnected() {
        defaults.set(connectedProviders.map(\.rawValue).sorted(), forKey: Keys.connected)
    }
}
