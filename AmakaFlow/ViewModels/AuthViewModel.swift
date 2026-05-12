import ClerkKit
import Combine
import Foundation
import Sentry

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

    // AMA-1843: UITest bypass. When the `UITEST_CLERK_TEST_SESSION` env
    // var is set on a DEBUG build, skip the real Clerk subscription
    // entirely and pretend the user is signed in. This lets XCUITest
    // drive screens past PairingView/AuthView without depending on
    // ClerkKitUI's WKWebView (which ships zero accessibilityIdentifier
    // values — see clerk-ios#413 / blueprint L3 limitations).
    //
    // Mock-only — there is no real Clerk JWT, so any backend API call
    // from the running test will 401. That is the documented limit of
    // Option B in AMA-1843; the proper bypass (real session via raw
    // Clerk Frontend API + setActive) is filed as a follow-up.
    //
    // Gated by both `#if DEBUG` and the env var so Release builds do
    // not compile the bypass code at all (DoD).
    #if DEBUG
    if AuthViewModel.uiTestBypassRequested() {
      applyUITestBypass()
      return
    }
    #endif

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

  #if DEBUG
  /// AMA-1843: env-var probe + payload parser.
  /// Format: `UITEST_CLERK_TEST_SESSION=user_id=<id>,email=<email>`
  /// (commas in values are not supported; not needed for sign-in mock).
  /// Anything non-empty enables the bypass — payload fields are
  /// optional and fall back to a synthetic test identity.
  static func uiTestBypassRequested() -> Bool {
    !(ProcessInfo.processInfo.environment["UITEST_CLERK_TEST_SESSION"] ?? "").isEmpty
  }

  private func applyUITestBypass() {
    let raw = ProcessInfo.processInfo.environment["UITEST_CLERK_TEST_SESSION"] ?? ""
    var fields: [String: String] = [:]
    for pair in raw.split(separator: ",") {
      let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
      if kv.count == 2 {
        fields[kv[0].trimmingCharacters(in: .whitespaces)] = kv[1].trimmingCharacters(in: .whitespaces)
      }
    }
    let mockId = fields["user_id"] ?? "user_uitest_ama1843"
    let mockEmail = fields["email"] ?? "claude+clerk_test@amakaflow.dev"
    let mockName = fields["name"] ?? "UITest User"

    userProfile = UserProfile(
      id: mockId,
      email: mockEmail,
      name: mockName,
      avatarUrl: nil
    )
    isAuthenticated = true
    hasResolvedInitialSession = true
    needsReauth = false
    // No cachedToken — `token()` will return nil so any backend call
    // surfaces a real failure rather than masquerading as success.
  }
  #endif

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
      // AMA-1810: Clerk silent token refresh failed. The user will be
      // routed to the re-auth flow next time `needsReauth` is read,
      // but ops needs a Sentry breadcrumb tagged the same way as
      // AMA-1805's server-side capture so a flurry of these is
      // visible in the alert stream alongside any matching backend
      // 401s. Earlier path swallowed the error silently — only the
      // user noticed when the sign-in screen reappeared.
      AuthViewModel.captureSentryBreadcrumb(
        message: "auth.refresh_token_failed",
        error: error
      )
      needsReauth = true
      return false
    }
  }

  func signOut() async {
    do {
      try await Clerk.shared.auth.signOut()
    } catch {
      // AMA-1810: sign-out failures previously only printed to the
      // console. They're rare but matter — a half-completed sign-out
      // can leave a stale session token in Clerk and an empty UI
      // state in the app. Drop a Sentry breadcrumb so support can
      // correlate user reports of "I signed out but I'm still
      // signed in."
      print("[AuthViewModel] Sign out failed: \(error.localizedDescription)")
      AuthViewModel.captureSentryBreadcrumb(
        message: "auth.sign_out_failed",
        error: error
      )
    }
    cachedToken = nil
    refreshFromClerk()
  }

  /// AMA-1810: shared helper so all three Clerk-side catch blocks
  /// produce the same tag set. Keeps the Sentry call signature
  /// consistent with AMA-1805's server-side schema (subsystem=auth,
  /// level=warning) so alerts can join across both sides.
  private static func captureSentryBreadcrumb(
    message: String,
    error: Error,
    file: String = #file,
    line: Int = #line
  ) {
    SentrySDK.capture(message: message) { scope in
      scope.setTag(value: "auth", key: "subsystem")
      scope.setTag(value: "AuthViewModel", key: "source")
      scope.setLevel(SentryLevel.warning)
      scope.setExtra(value: error.localizedDescription, key: "error")
      scope.setExtra(value: "\(file):\(line)", key: "site")
    }
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
      // AMA-1810: token-refresh-coordinator failure path. The error
      // re-throws so the caller surfaces it via CTAError.unauthenticated,
      // but we also drop a Sentry breadcrumb here so the *coordinator's*
      // perspective on the failure is visible in alerts (separate from
      // the per-call-site captures the actor's callers might add).
      SentrySDK.capture(message: "auth.refresh_coordinator_failed") { scope in
        scope.setTag(value: "auth", key: "subsystem")
        scope.setTag(value: "ClerkTokenRefreshCoordinator", key: "source")
        scope.setLevel(SentryLevel.warning)
        scope.setExtra(value: error.localizedDescription, key: "error")
      }
      needsReauth = true
      persistence.clearClerkToken()
      throw error
    }
  }
}

final class UserDefaultsClerkTokenPersistence: ClerkTokenPersistence, @unchecked Sendable {
  private let userDefaults: UserDefaults
  private let key: String

  init(
    userDefaults: UserDefaults = .standard,
    key: String = "clerk_auth_token"
  ) {
    self.userDefaults = userDefaults
    self.key = key
  }

  func loadClerkToken() -> ClerkAuthToken? {
    guard let data = userDefaults.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(ClerkAuthToken.self, from: data)
  }

  func saveClerkToken(_ token: ClerkAuthToken) {
    guard let data = try? JSONEncoder().encode(token) else { return }
    userDefaults.set(data, forKey: key)
  }

  func clearClerkToken() {
    userDefaults.removeObject(forKey: key)
  }
}
