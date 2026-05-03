import ClerkKit
import Combine
import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
  static let shared = AuthViewModel()

  @Published private(set) var isAuthenticated: Bool = false
  @Published private(set) var hasResolvedInitialSession: Bool = false
  @Published private(set) var userProfile: UserProfile?
  @Published private(set) var needsReauth: Bool = false
  @Published private(set) var lastTokenRefresh: Date?

  private var cachedToken: String?
  private var authEventsTask: Task<Void, Never>?

  private init() {}

  func start() {
    guard authEventsTask == nil else { return }
    refreshFromClerk()
    authEventsTask = Task { [weak self] in
      for await event in Clerk.shared.auth.events {
        guard let self else { return }
        switch event {
        case .signedOut, .accountDeleted:
          self.cachedToken = nil
          self.refreshFromClerk()
        case .sessionChanged:
          self.cachedToken = nil
          self.refreshFromClerk()
        case .tokenRefreshed(let token):
          self.cachedToken = token
          self.lastTokenRefresh = Date()
          self.refreshFromClerk()
        case .signInCompleted, .signUpCompleted:
          self.cachedToken = nil
          self.needsReauth = false
          self.refreshFromClerk()
        }
      }
    }
  }

  func refreshFromClerk() {
    let clerkUser = Clerk.shared.user
    isAuthenticated = Clerk.shared.session != nil && clerkUser != nil
    hasResolvedInitialSession = true
    userProfile = clerkUser.map { user in
      let name = [user.firstName, user.lastName]
        .compactMap { $0 }
        .joined(separator: " ")
      return UserProfile(
        id: user.id,
        email: user.primaryEmailAddress?.emailAddress,
        name: name.isEmpty ? nil : name,
        avatarUrl: user.imageUrl
      )
    }

    if !isAuthenticated {
      cachedToken = nil
      lastTokenRefresh = nil
    }
  }

  func token(skipCache: Bool = false) async throws -> String? {
    guard let session = Clerk.shared.session else {
      refreshFromClerk()
      return nil
    }

    if !skipCache,
      let cachedToken,
      let lastTokenRefresh,
      Date().timeIntervalSince(lastTokenRefresh) < 50
    {
      return cachedToken
    }

    let token = try await session.getToken(.init(skipCache: skipCache))
    cachedToken = token
    lastTokenRefresh = token == nil ? nil : Date()
    refreshFromClerk()
    return token
  }

  var hasActiveSession: Bool { Clerk.shared.session != nil }

  func cachedBearerToken() -> String? { cachedToken }

  func markAuthInvalid() { needsReauth = true }
  func authRestored() { needsReauth = false }

  @discardableResult
  func refreshToken() async -> Bool {
    do {
      let result = try await token(skipCache: true) != nil
      if result { needsReauth = false }
      return result
    } catch {
      needsReauth = true
      return false
    }
  }

  func signOut() async {
    do {
      try await Clerk.shared.auth.signOut()
    } catch {
      print("[AuthViewModel] Sign out failed: \(error.localizedDescription)")
    }
    cachedToken = nil
    refreshFromClerk()
  }
}

// MARK: - Clerk token refresh state machine

struct ClerkAuthToken: Codable, Equatable, Sendable {
  let value: String
  let expiresAt: Date
}

protocol ClerkTokenRefreshClient: Sendable {
  func refreshClerkToken() async throws -> ClerkAuthToken
}

protocol ClerkTokenPersistence: Sendable {
  func loadClerkToken() -> ClerkAuthToken?
  func saveClerkToken(_ token: ClerkAuthToken)
  func clearClerkToken()
}

enum ClerkTokenRefreshCoordinatorError: Error, Equatable {
  case reauthRequired
}

actor ClerkTokenRefreshCoordinator {
  private let client: ClerkTokenRefreshClient
  private let persistence: ClerkTokenPersistence
  private let refreshBeforeExpiry: TimeInterval
  private let clockSkewTolerance: TimeInterval
  private let now: @Sendable () -> Date
  private var inFlightRefresh: Task<ClerkAuthToken, Error>?

  private(set) var needsReauth = false

  init(
    client: ClerkTokenRefreshClient,
    persistence: ClerkTokenPersistence,
    refreshBeforeExpiry: TimeInterval = 60,
    clockSkewTolerance: TimeInterval = 30,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.client = client
    self.persistence = persistence
    self.refreshBeforeExpiry = refreshBeforeExpiry
    self.clockSkewTolerance = clockSkewTolerance
    self.now = now
  }

  func bearerToken() async throws -> String {
    if let token = persistence.loadClerkToken(), !shouldRefresh(token) {
      needsReauth = false
      return token.value
    }

    return try await refreshToken().value
  }

  func refreshAfterUnauthorized() async throws -> String {
    try await refreshToken().value
  }

  func restorePersistedToken() -> ClerkAuthToken? {
    persistence.loadClerkToken()
  }

  func tokenAfterForeground() async throws -> String? {
    guard persistence.loadClerkToken() != nil else { return nil }
    return try await bearerToken()
  }

  func markReauthRequired() {
    needsReauth = true
    persistence.clearClerkToken()
  }

  func isReauthRequired() -> Bool {
    needsReauth
  }

  private func shouldRefresh(_ token: ClerkAuthToken) -> Bool {
    token.expiresAt <= now().addingTimeInterval(refreshBeforeExpiry + clockSkewTolerance)
  }

  private func refreshToken() async throws -> ClerkAuthToken {
    if let inFlightRefresh {
      return try await inFlightRefresh.value
    }

    let task = Task { [client, persistence] in
      let token = try await client.refreshClerkToken()
      persistence.saveClerkToken(token)
      return token
    }
    inFlightRefresh = task
    defer { inFlightRefresh = nil }

    do {
      let token = try await task.value
      needsReauth = false
      return token
    } catch {
      needsReauth = true
      persistence.clearClerkToken()
      throw error
    }
  }
}

final class UserDefaultsClerkTokenPersistence: ClerkTokenPersistence, @unchecked Sendable {
  private let userDefaults: UserDefaults
  private let key: String
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(
    userDefaults: UserDefaults = .standard,
    key: String = "clerk_auth_token"
  ) {
    self.userDefaults = userDefaults
    self.key = key
  }

  func loadClerkToken() -> ClerkAuthToken? {
    guard let data = userDefaults.data(forKey: key) else { return nil }
    return try? decoder.decode(ClerkAuthToken.self, from: data)
  }

  func saveClerkToken(_ token: ClerkAuthToken) {
    guard let data = try? encoder.encode(token) else { return }
    userDefaults.set(data, forKey: key)
  }

  func clearClerkToken() {
    userDefaults.removeObject(forKey: key)
  }
}
