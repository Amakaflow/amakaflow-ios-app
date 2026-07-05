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

    // AMA-1843: UITest mock bypass. When `UITEST_CLERK_TEST_SESSION`
    // is set on a DEBUG build, skip Clerk entirely and pretend the
    // user is signed in. No real JWT — backend API calls return 401.
    // Useful for UI-only journey validation.
    //
    // AMA-1849: UITest REAL-session bypass. When
    // `UITEST_CLERK_REAL_SESSION_EMAIL` is set on a DEBUG build,
    // create an actual Clerk session via the Frontend API (using
    // Clerk's universal test code 424242) and plumb it into
    // `Clerk.shared` via the public `setActive(sessionId:)` API.
    // `AuthViewModel.token()` then returns a valid Clerk JWT and
    // backend calls authenticate as the test user. Removes the
    // 401-everywhere limit of the mock bypass.
    //
    // Both are gated by `#if DEBUG` so Release builds do not compile
    // the bypass code (DoD inspected via PlistBuddy on the IPA).
    #if DEBUG
    if AuthViewModel.uiTestRealSessionRequested() {
      // AMA-2269: Resolve the launch shell immediately. While bypass runs,
      // Maestro must see mental-model / sign-in UI — not the black spinner.
      refreshFromClerk()
      subscribeToAuthEvents()
      Task { [weak self] in
        await self?.applyUITestRealSessionBypass()
      }
      return
    }
    if AuthViewModel.uiTestBypassRequested() {
      applyUITestBypass()
      return
    }
    #endif

    refreshFromClerk()
    subscribeToAuthEvents()
  }

  /// Shared Clerk event-subscription loop. Called from both the normal
  /// `start()` path and from the AMA-1849 bypass after it activates a
  /// session. CR-suggested DRY extraction (PR #219) — keeps event
  /// handling in one place so future changes only need to be applied
  /// once.
  private func subscribeToAuthEvents() {
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
    !(UITestEnvironment.value(for: "UITEST_CLERK_TEST_SESSION") ?? "").isEmpty
  }

  private func applyUITestBypass() {
    let raw = UITestEnvironment.value(for: "UITEST_CLERK_TEST_SESSION") ?? ""
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

  /// AMA-1849: real-session bypass probe. Format:
  ///   `UITEST_CLERK_REAL_SESSION_EMAIL=claude+clerk_test@amakaflow.dev`
  /// (the `+clerk_test` subaddress is how Clerk routes to its universal
  /// test code 424242 on dev/staging instances.)
  static func uiTestRealSessionRequested() -> Bool {
    !(UITestEnvironment.value(for: "UITEST_CLERK_REAL_SESSION_EMAIL") ?? "").isEmpty
  }

  /// Poll briefly so CI password bypass does not race an empty Maestro launch-arg read.
  private func uiTestClerkPassword(maxWaitSeconds: TimeInterval = 10) async -> String? {
    let deadline = Date().addingTimeInterval(maxWaitSeconds)
    while Date() < deadline {
      if let password = UITestEnvironment.value(for: "UITEST_CLERK_PASSWORD"), !password.isEmpty {
        return password
      }
      try? await Task.sleep(nanoseconds: 200_000_000)
    }
    return UITestEnvironment.value(for: "UITEST_CLERK_PASSWORD")
  }

  /// AMA-1849: bypass that creates a REAL Clerk session via the
  /// Frontend API, then hands it to the SDK via `setActive`. Unlike
  /// the mock bypass, `Clerk.shared.session` is populated and
  /// `AuthViewModel.token()` returns a valid JWT — backend API calls
  /// authenticate as the test user.
  ///
  /// Three-step flow:
  ///   1. POST /v1/client/sign_ins (strategy: email_code)
  ///   2. POST /v1/client/sign_ins/<id>/attempt_first_factor with code=424242
  ///   3. await Clerk.shared.auth.setActive(sessionId: createdSessionId)
  ///
  /// Frontend API URL is derived from `Clerk.shared.publishableKey`
  /// (matches Clerk SDK's own `extractFrontendApiUrl` logic — the
  /// part after `pk_test_` / `pk_live_` is base64-encoded host).
  private func applyUITestRealSessionBypass() async {
    defer {
      // Never leave the launch screen stuck on black if bypass fails
      // (AMA-2269: CI Maestro timed out waiting for af_tabbar).
      if !hasResolvedInitialSession {
        refreshFromClerk()
        if authEventsTask == nil {
          subscribeToAuthEvents()
        }
      }
    }

    let email = UITestEnvironment.value(for: "UITEST_CLERK_REAL_SESSION_EMAIL") ?? ""
    let password = await uiTestClerkPassword()

    guard !email.isEmpty else {
      print("[AuthViewModel] AMA-1849 bypass FAILED: UITEST_CLERK_REAL_SESSION_EMAIL is empty")
      return
    }

    let hasPassword = password?.isEmpty == false
    #if DEBUG
    let pwdKeyPresent = UITestEnvironment.value(for: "UITEST_CLERK_PASSWORD") != nil
    print("[AuthViewModel] AMA-1849 bypass starting for \(email) (password=\(hasPassword), pwdKeyPresent=\(pwdKeyPresent))")
    #else
    print("[AuthViewModel] AMA-1849 bypass starting for \(email) (password=\(hasPassword))")
    #endif

    do {
      let sessionId: String
      if hasPassword, let password {
        // Staging CI test user (claude+clerk_test@amakaflow.dev) is password-first
        // per AMA-2250. Use Clerk SDK signInWithPassword — single create call with
        // identifier+password (not strategy=password on sign_ins create).
        let signIn = try await Clerk.shared.auth.signInWithPassword(
          identifier: email,
          password: password
        )
        guard let created = signIn.createdSessionId else {
          throw NSError(
            domain: "AMA-1849",
            code: -3,
            userInfo: [NSLocalizedDescriptionKey: "no created_session_id after password sign-in"]
          )
        }
        sessionId = created
      } else {
        // AMA-2271: HTTP email_code bypass races Maestro Clerk UI on fresh CI sims and
        // leaves expired verifications. When password is unavailable, defer to the
        // Maestro UI fallback in clerk-signin.yaml instead of opening a sign-in here.
        print("[AuthViewModel] AMA-1849 bypass deferred — no UITEST_CLERK_PASSWORD (Maestro UI)")
        return
      }

      try await Clerk.shared.auth.setActive(sessionId: sessionId)

      print("[AuthViewModel] AMA-1849 bypass OK: session \(sessionId) active for \(email)")

      refreshFromClerk()
    } catch {
      print("[AuthViewModel] AMA-1849 bypass FAILED: \(error)")
    }
  }

  private func createClerkSession(
    base: String,
    email: String,
    signInBody: String,
    attemptBody: String
  ) async throws -> String {
    let signIn = try await postClerkForm(
      url: URL(string: "\(base)/v1/client/sign_ins?_is_native=true")!,
      body: signInBody
    )
    guard let signInId = Self.extractClerkSignInID(from: signIn) else {
      throw NSError(
        domain: "AMA-1849",
        code: -2,
        userInfo: [NSLocalizedDescriptionKey: "no sign-in id for \(email)"]
      )
    }

    let verified = try await postClerkForm(
      url: URL(string: "\(base)/v1/client/sign_ins/\(signInId)/attempt_first_factor?_is_native=true")!,
      body: attemptBody
    )
    guard let sessionId = Self.extractClerkCreatedSessionID(from: verified) else {
      throw NSError(
        domain: "AMA-1849",
        code: -3,
        userInfo: [NSLocalizedDescriptionKey: "no created_session_id for \(email)"]
      )
    }
    return sessionId
  }

  private static func extractClerkSignInID(from payload: [String: Any]) -> String? {
    (payload["response"] as? [String: Any])?["id"] as? String ?? payload["id"] as? String
  }

  private static func extractClerkCreatedSessionID(from payload: [String: Any]) -> String? {
    (payload["response"] as? [String: Any])?["created_session_id"] as? String
      ?? payload["created_session_id"] as? String
  }

  /// Decode the frontend-api host (`solid-chicken-50.clerk.accounts.dev`)
  /// from `pk_test_<base64>` / `pk_live_<base64>`. Matches the logic in
  /// `ConfigurationManager.extractFrontendApiUrl` (private in the SDK)
  /// — including SDK behavior of using **Base64URL** decoding (handles
  /// `-` and `_` chars) rather than standard Base64.
  static func deriveClerkFrontendHost(from publishableKey: String) -> String? {
    let payload: String
    if publishableKey.hasPrefix("pk_test_") {
      payload = String(publishableKey.dropFirst("pk_test_".count))
    } else if publishableKey.hasPrefix("pk_live_") {
      payload = String(publishableKey.dropFirst("pk_live_".count))
    } else {
      return nil
    }
    // Base64URL → standard Base64 conversion: substitute URL-safe
    // alphabet back, then pad with `=` to a multiple of 4. Matches
    // Clerk SDK's String.base64String() helper.
    var b64 = payload
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    let pad = (4 - b64.count % 4) % 4
    b64.append(String(repeating: "=", count: pad))
    guard let data = Data(base64Encoded: b64),
          var decoded = String(data: data, encoding: .utf8) else {
      return nil
    }
    // Clerk encodes a trailing `$`; strip it.
    if decoded.hasSuffix("$") { decoded.removeLast() }
    return decoded.isEmpty ? nil : decoded
  }

  /// Minimal application/x-www-form-urlencoded POST helper for the
  /// two Clerk Frontend API calls. Returns the decoded JSON dict.
  /// Throws on transport, HTTP, or JSON errors. 10-second timeout
  /// so a slow Clerk API can't hang UITest startup indefinitely.
  private func postClerkForm(url: URL, body: String) async throws -> [String: Any] {
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.timeoutInterval = 10  // bound UITest blast radius if Clerk slow
    req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    req.setValue("AmakaFlowCompanion/UITest-AMA-1849", forHTTPHeaderField: "User-Agent")
    req.httpBody = body.data(using: .utf8)

    let (data, response) = try await URLSession.shared.data(for: req)
    if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
      // Truncate response body in error message — Clerk responses can
      // include session tokens or partial user data; keep the snippet
      // short enough to diagnose without spilling secrets to logs.
      let snippet = (String(data: data, encoding: .utf8) ?? "<binary>").prefix(200)
      throw NSError(
        domain: "AMA-1849",
        code: http.statusCode,
        userInfo: [NSLocalizedDescriptionKey: "Clerk \(url.path) -> \(http.statusCode): \(snippet)"]
      )
    }
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw NSError(domain: "AMA-1849", code: -1, userInfo: [NSLocalizedDescriptionKey: "non-JSON response"])
    }
    return json
  }

  /// Stricter percent-encoding for application/x-www-form-urlencoded
  /// bodies — only unreserved RFC 3986 characters (alphanumeric +
  /// `-._~`) pass through unencoded. `.urlQueryAllowed` would let
  /// `&` and `=` through, which corrupts form pairs.
  private func urlEncode(_ s: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
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

#if DEBUG
// UserDefaultsClerkTokenPersistence is test-only. Production code uses
// KeychainClerkTokenPersistence (AMA-1809). This type must never be
// wired into the production DI graph — the #if DEBUG guard prevents a
// Release-reachable caller from accidentally regressing that invariant.
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
#endif
