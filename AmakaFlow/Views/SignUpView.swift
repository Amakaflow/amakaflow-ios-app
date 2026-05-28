//
//  SignUpView.swift
//  AmakaFlow
//
//  AMA-2007: pre-auth sign-up screen with pure SwiftUI demo.
//

import ClerkKit
import ClerkKitUI
import SwiftUI

struct SignUpView: View {
    @StateObject private var viewModel: SignUpViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @MainActor
    init(viewModel: SignUpViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? SignUpViewModel())
    }

    var body: some View {
        GeometryReader { proxy in
            let heroHeight = max(proxy.size.height * 0.58, 360)

            VStack(spacing: 0) {
                SignUpDemoHeroView(playback: .mode(reduceMotion: reduceMotion))
                    .frame(height: min(heroHeight, proxy.size.height * 0.64))
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, max(proxy.safeAreaInsets.top + 10, 18))
                    .padding(.bottom, Theme.Spacing.md)
                    .accessibilityIdentifier("signup_demo_hero")

                bottomPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.lg)
                    .padding(.bottom, max(proxy.safeAreaInsets.bottom + 12, 24))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Theme.Colors.background.ignoresSafeArea())
        }
        .overlay(alignment: .top) {
            if let error = viewModel.error, let failedAction = viewModel.failedAction {
                ErrorToast(
                    actionTitle: failedAction.toastTitle,
                    error: error,
                    onRetry: error.isRetryable ? { retry(failedAction) } : nil,
                    onReport: { viewModel.reportCurrentError() },
                    onDismiss: { viewModel.dismissError() }
                )
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, 14)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.error != nil)
        .sheet(isPresented: $viewModel.isEmailAuthPresented) {
            AuthView(mode: .signInOrUp, isDismissable: true)
                .environment(Clerk.shared)
        }
        .accessibilityIdentifier("signup_screen")
    }

    private var bottomPanel: some View {
        VStack(spacing: 18) {
            VStack(spacing: 9) {
                Text("Train on the right day")
                    .font(Font.geist(32, .semibold))
                    .multilineTextAlignment(.center)
                    .lineSpacing(-2)
                    .minimumScaleFactor(0.86)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text("Your AI coach adapts every session")
                    .font(Font.geist(16, .regular))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            .padding(.top, 2)

            VStack(spacing: 12) {
                Button {
                    Task { await viewModel.signInWithApple() }
                } label: {
                    SignUpButtonLabel(
                        systemImage: "apple.logo",
                        title: "Sign in with Apple",
                        isLoading: viewModel.inFlightAction == .apple,
                        loadingText: SignUpViewModel.Action.apple.loadingLabel
                    )
                }
                .buttonStyle(SignUpAppleButtonStyle())
                .disabled(viewModel.isBusy)
                .accessibilityIdentifier("signup_apple_button")

                Button {
                    Task { await viewModel.continueWithEmail() }
                } label: {
                    SignUpButtonLabel(
                        systemImage: "envelope",
                        title: "Continue with email",
                        isLoading: viewModel.inFlightAction == .email,
                        loadingText: SignUpViewModel.Action.email.loadingLabel
                    )
                }
                .buttonStyle(SignUpEmailButtonStyle())
                .disabled(viewModel.isBusy)
                .accessibilityIdentifier("signup_email_button")
            }

            Text("By continuing, you agree to AmakaFlow's Terms and Privacy Policy.")
                .font(Theme.Typography.footnote)
                .multilineTextAlignment(.center)
                .foregroundColor(Theme.Colors.textTertiary)
                .padding(.horizontal, 10)
                .accessibilityIdentifier("signup_legal_text")
        }
    }

    private func retry(_ action: SignUpViewModel.Action) {
        Task {
            switch action {
            case .apple: await viewModel.signInWithApple()
            case .email: await viewModel.continueWithEmail()
            }
        }
    }
}

private struct SignUpButtonLabel: View {
    let systemImage: String
    let title: String
    let isLoading: Bool
    let loadingText: String

    var body: some View {
        HStack(spacing: 9) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(loadingText)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
            }
            Text(isLoading ? loadingText : title)
                .lineLimit(1)
                .minimumScaleFactor(0.88)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .contentShape(Rectangle())
    }
}

private struct SignUpAppleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.geist(16, .semibold))
            .foregroundColor(.white)
            .background(Color.black)
            .clipShape(Capsule())
            .opacity(isEnabled ? 1 : 0.58)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

private struct SignUpEmailButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.geist(16, .semibold))
            .foregroundColor(Theme.Colors.textPrimary)
            .background(configuration.isPressed ? Theme.Colors.accentBackground : Color.clear)
            .overlay(Capsule().stroke(Theme.Colors.borderMedium, lineWidth: 1))
            .clipShape(Capsule())
            .opacity(isEnabled ? 1 : 0.58)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

#if DEBUG
private final class PreviewSignUpAuth: SignUpAuthenticating {
    func signInWithApple() async throws {}
    func prepareEmailAuthentication() async throws {}
}

#Preview("Sign-up — light") {
    SignUpView(viewModel: SignUpViewModel(auth: PreviewSignUpAuth()))
        .preferredColorScheme(.light)
}

#Preview("Sign-up — dark") {
    SignUpView(viewModel: SignUpViewModel(auth: PreviewSignUpAuth()))
        .preferredColorScheme(.dark)
}
#endif
