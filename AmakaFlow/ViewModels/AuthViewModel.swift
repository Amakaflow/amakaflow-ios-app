import ClerkKit
import Combine
import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    static let shared = AuthViewModel()

    @Published private(set) var isAuthenticated: Bool = false
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
                case .signedOut, .accountDeleted, .sessionChanged:
                    self.refreshFromClerk()
                case .tokenRefreshed(let token):
                    self.cachedToken = token
                    self.lastTokenRefresh = Date()
                    self.refreshFromClerk()
                case .signInCompleted, .signUpCompleted:
                    self.needsReauth = false
                    self.refreshFromClerk()
                }
            }
        }
    }

    func refreshFromClerk() {
        let clerkUser = Clerk.shared.user
        isAuthenticated = Clerk.shared.session != nil && clerkUser != nil
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
           Date().timeIntervalSince(lastTokenRefresh) < 50 {
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
            return try await token(skipCache: true) != nil
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
