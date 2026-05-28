//
//  SignUpViewModel.swift
//  AmakaFlow
//
//  AMA-2007: Auth CTA state for the pre-auth sign-up screen.
//

import ClerkKit
import Combine
import Foundation

@MainActor
protocol SignUpAuthenticating: AnyObject {
    func signInWithApple() async throws
    func prepareEmailAuthentication() async throws
}

extension AuthViewModel: SignUpAuthenticating {
    /// Real Clerk Sign in with Apple flow. Transferable=true lets Clerk route
    /// first-time users into sign-up without a separate mock onboarding path.
    func signInWithApple() async throws {
        try await Clerk.shared.auth.signInWithApple(transferable: true)
        refreshFromClerk()
    }

    /// Preflight the Clerk environment before presenting ClerkKitUI's email
    /// auth flow so CTA failures can still surface through the CTAError stack.
    func prepareEmailAuthentication() async throws {
        try await Clerk.shared.refreshEnvironment()
    }
}

@MainActor
final class SignUpViewModel: ObservableObject {
    enum Action: Equatable {
        case apple
        case email

        var loadingLabel: String {
            switch self {
            case .apple: return "Starting Apple sign-in…"
            case .email: return "Opening email sign-in…"
            }
        }

        var toastTitle: String {
            switch self {
            case .apple: return "Couldn't sign in with Apple"
            case .email: return "Couldn't open email sign-in"
            }
        }

        var reportAction: String {
            switch self {
            case .apple: return "auth_sign_in_apple"
            case .email: return "auth_sign_in_email"
            }
        }
    }

    @Published private(set) var inFlightAction: Action?
    @Published private(set) var error: CTAError?
    @Published private(set) var failedAction: Action?
    @Published var isEmailAuthPresented = false

    private let auth: SignUpAuthenticating
    private let errorReporter: ErrorReporting
    private let userIdProvider: () -> String?

    init(
        auth: SignUpAuthenticating? = nil,
        errorReporter: ErrorReporting? = nil,
        userIdProvider: @escaping () -> String? = { nil }
    ) {
        self.auth = auth ?? AuthViewModel.shared
        self.errorReporter = errorReporter ?? ErrorReporter.shared
        self.userIdProvider = userIdProvider
    }

    var isBusy: Bool { inFlightAction != nil }

    func signInWithApple() async {
        await run(.apple) {
            try await auth.signInWithApple()
        }
    }

    func continueWithEmail() async {
        await run(.email) {
            try await auth.prepareEmailAuthentication()
            isEmailAuthPresented = true
        }
    }

    func dismissError() {
        error = nil
        failedAction = nil
    }

    func reportCurrentError() {
        guard let error, let failedAction else { return }
        errorReporter.report(
            action: failedAction.reportAction,
            error: error,
            endpoint: nil,
            userId: userIdProvider()
        )
    }

    private func run(_ action: Action, operation: () async throws -> Void) async {
        guard inFlightAction == nil else { return }

        inFlightAction = action
        error = nil
        failedAction = nil

        do {
            try await operation()
        } catch {
            self.error = CTAError.map(error)
            self.failedAction = action
        }

        inFlightAction = nil
    }
}
