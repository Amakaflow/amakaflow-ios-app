//
//  ActualsProviderAuthProviding.swift
//  AmakaFlow
//
//  AMA-2387: Strava / Garmin OAuth via BFF — stub until backend ships.
//  Never request activity:write / upload scopes (design-handoff/ACTUALS.md).
//

import Foundation

enum ActualsProviderAuthOutcome: Equatable {
    case success
    case cancelled
}

protocol ActualsProviderAuthProviding: AnyObject {
    /// Starts provider OAuth (real ASWebAuthenticationSession + BFF later).
    /// Stub returns cancel/success without network.
    func authorize(_ provider: ActualsSourceProvider) async -> ActualsProviderAuthOutcome
}

// MARK: - Outcome applicator

enum ActualsProviderAuthAction {
    @MainActor
    static func apply(
        outcome: ActualsProviderAuthOutcome,
        provider: ActualsSourceProvider,
        store: ActualsSourceConnecting
    ) {
        switch outcome {
        case .success:
            store.markConnected(provider)
        case .cancelled:
            break
        }
    }
}

// MARK: - Stub (no network — UI drives cancel/authorize)

/// Stub auth used until the mobile-BFF OAuth endpoints exist.
/// Authorize button → `.success` (no network). Cancel never calls this.
@MainActor
final class StubActualsProviderAuth: ActualsProviderAuthProviding {
    /// Test override — when set, consumed once on the next `authorize`.
    var nextOutcome: ActualsProviderAuthOutcome?

    func authorize(_ provider: ActualsSourceProvider) async -> ActualsProviderAuthOutcome {
        _ = provider
        if let nextOutcome {
            self.nextOutcome = nil
            return nextOutcome
        }
        return .success
    }
}

// MARK: - Mock (tests)

@MainActor
final class MockActualsProviderAuth: ActualsProviderAuthProviding {
    var outcomes: [ActualsSourceProvider: ActualsProviderAuthOutcome]
    private(set) var authorizeCalls: [ActualsSourceProvider] = []

    init(outcomes: [ActualsSourceProvider: ActualsProviderAuthOutcome] = [:]) {
        self.outcomes = outcomes
    }

    func authorize(_ provider: ActualsSourceProvider) async -> ActualsProviderAuthOutcome {
        authorizeCalls.append(provider)
        return outcomes[provider] ?? .cancelled
    }
}
