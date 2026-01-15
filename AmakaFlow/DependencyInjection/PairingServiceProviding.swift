//
//  PairingServiceProviding.swift
//  AmakaFlow
//
//  Protocol abstraction for PairingService to enable dependency injection and testing.
//

import Foundation
import Combine

/// Protocol defining the pairing service interface for dependency injection
/// Note: Implementations should be @MainActor for thread safety with UI bindings
@MainActor
protocol PairingServiceProviding: AnyObject {
    // MARK: - Published Properties (Observable)

    /// Whether the device is currently paired with a user account
    var isPaired: Bool { get }

    /// The current user's profile, if paired
    var userProfile: UserProfile? { get }

    /// Whether re-authentication is required (e.g., after 401 response)
    var needsReauth: Bool { get }

    /// Timestamp of last successful token refresh
    var lastTokenRefresh: Date? { get }

    // MARK: - Publishers for SwiftUI observation

    /// Publisher for isPaired changes
    var isPairedPublisher: Published<Bool>.Publisher { get }

    /// Publisher for userProfile changes
    var userProfilePublisher: Published<UserProfile?>.Publisher { get }

    /// Publisher for needsReauth changes
    var needsReauthPublisher: Published<Bool>.Publisher { get }

    // MARK: - Authentication State

    /// Mark authentication as invalid (e.g., on 401 response)
    func markAuthInvalid()

    /// Called after successful re-pairing to clear the needsReauth flag
    func authRestored()

    // MARK: - Pairing Operations

    /// Exchange a pairing code (from QR or manual entry) for a JWT
    func pair(code: String) async throws -> PairingResponse

    /// Silently refresh the JWT using device ID
    func refreshToken() async -> Bool

    // MARK: - Token Management

    /// Get the current JWT token, if available
    func getToken() -> String?

    /// Remove pairing and clear stored credentials
    func unpair()

    // MARK: - Test Mode (DEBUG only)

    #if DEBUG
    /// Enable E2E test mode with provided credentials
    func enableTestMode(authSecret: String, userId: String)

    /// Disable E2E test mode and clear stored credentials
    func disableTestMode()

    /// Check if currently in E2E test mode
    var isInTestMode: Bool { get }
    #endif
}

// MARK: - PairingService Conformance

extension PairingService: PairingServiceProviding {
    var isPairedPublisher: Published<Bool>.Publisher { $isPaired }
    var userProfilePublisher: Published<UserProfile?>.Publisher { $userProfile }
    var needsReauthPublisher: Published<Bool>.Publisher { $needsReauth }
}
