//
//  ActualsProviderAuthProviding.swift
//  AmakaFlow
//
//  AMA-2387 / AMA-2391: Strava / Garmin OAuth via BFF.
//  Default scope is read-only; AMA-2396 write-back reconnect requests
//  activity:write via `includeWrite: true` on authorize.
//  Live: `BFFActualsProviderAuth`. Stub: previews + AF_USE_FIXTURES.
//

import Foundation

enum ActualsProviderAuthOutcome: Equatable {
    /// - Parameter grantedWrite: Strava returned `activity:write` in the grant.
    case success(grantedWrite: Bool)
    case cancelled
    /// Authorize failed or OAuth is unavailable — stay on the scope screen.
    case failed

    /// Convenience for call sites that only care about link vs cancel/fail.
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var grantedWrite: Bool {
        if case .success(let write) = self { return write }
        return false
    }
}

protocol ActualsProviderAuthProviding: AnyObject {
    /// Starts provider OAuth (ASWebAuthenticationSession + BFF for Strava).
    /// - Parameter includeWrite: request `activity:write` (write-back reconnect).
    func authorize(
        _ provider: ActualsSourceProvider,
        includeWrite: Bool
    ) async -> ActualsProviderAuthOutcome
}

extension ActualsProviderAuthProviding {
    func authorize(_ provider: ActualsSourceProvider) async -> ActualsProviderAuthOutcome {
        await authorize(provider, includeWrite: false)
    }
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
        case .cancelled, .failed:
            break
        }
    }
}

// MARK: - Stub (no network — UI drives cancel/authorize)

/// Stub auth for previews / UITEST fixtures (and DEBUG dogfood when selected).
/// DEBUG Authorize → `.success`. Release → `.failed` (never fake a link).
@MainActor
final class StubActualsProviderAuth: ActualsProviderAuthProviding {
    /// Test override — when set, consumed once on the next `authorize`.
    var nextOutcome: ActualsProviderAuthOutcome?

    func authorize(
        _ provider: ActualsSourceProvider,
        includeWrite: Bool
    ) async -> ActualsProviderAuthOutcome {
        _ = provider
        if let nextOutcome {
            self.nextOutcome = nil
            return nextOutcome
        }
        #if DEBUG
        return .success(grantedWrite: includeWrite)
        #else
        return .failed
        #endif
    }
}

// MARK: - Mock (tests)

@MainActor
final class MockActualsProviderAuth: ActualsProviderAuthProviding {
    var outcomes: [ActualsSourceProvider: ActualsProviderAuthOutcome]
    private(set) var authorizeCalls: [(ActualsSourceProvider, Bool)] = []

    init(outcomes: [ActualsSourceProvider: ActualsProviderAuthOutcome] = [:]) {
        self.outcomes = outcomes
    }

    func authorize(
        _ provider: ActualsSourceProvider,
        includeWrite: Bool
    ) async -> ActualsProviderAuthOutcome {
        authorizeCalls.append((provider, includeWrite))
        return outcomes[provider] ?? .cancelled
    }
}
