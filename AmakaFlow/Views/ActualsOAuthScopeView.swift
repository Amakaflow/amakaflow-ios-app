//
//  ActualsOAuthScopeView.swift
//  AmakaFlow
//
//  AMA-2387: in-app OAuth scope confirm for Strava / Garmin.
//  Upload scope is struck-through NOT REQUESTED (screens-actuals3.jsx).
//

import SwiftUI

struct ActualsOAuthScopeView<Store: ActualsSourceConnecting>: View where Store: ObservableObject {
    let provider: ActualsSourceProvider
    @ObservedObject var store: Store
    var auth: any ActualsProviderAuthProviding
    var onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isWorking = false
    @State private var authorizeError: String?

    init(
        provider: ActualsSourceProvider,
        store: Store,
        auth: (any ActualsProviderAuthProviding)? = nil,
        onFinished: @escaping () -> Void = {}
    ) {
        self.provider = provider
        self.store = store
        self.auth = auth ?? StubActualsProviderAuth()
        self.onFinished = onFinished
    }

    var body: some View {
        VStack(spacing: 0) {
            browserChrome

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    providerHeader
                        .padding(.top, 18)

                    scopeCard
                        .padding(.top, 14)

                    if let authorizeError {
                        Text(authorizeError)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(DailyDriver.amber)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 12)
                    }

                    Button(action: authorizeTapped) {
                        Text(ActualsCopy.oauthAuthorizeCTA)
                            .ddDisplayText(13.5, weight: .bold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(authorizeColor)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)
                    .padding(.top, 14)
                    .accessibilityIdentifier(ActualsCopy.oauthAuthorizeAccessibilityID)

                    Button(action: cancelTapped) {
                        Text(ActualsCopy.oauthCancelCTA)
                            .font(.system(size: 12))
                            .foregroundColor(DailyDriver.foregroundMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)
                    .accessibilityIdentifier(ActualsCopy.oauthCancelAccessibilityID)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 48)
            }
        }
        .background(DailyDriver.screenBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .ddSuppressFloatingChrome()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ActualsCopy.oauthScopeAccessibilityID)
    }

    // MARK: - Chrome (ASWebAuthenticationSession stand-in)

    private var browserChrome: some View {
        HStack(spacing: 10) {
            Button(ActualsCopy.oauthCancelCTA, action: cancelTapped)
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "0A84FF"))
                .buttonStyle(.plain)

            Text(ActualsCopy.oauthHostChrome(for: provider))
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(DailyDriver.card2)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Image(systemName: "arrow.clockwise")
                .font(.system(size: 13))
                .foregroundColor(DailyDriver.foregroundDim)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DailyDriver.border).frame(height: 1)
        }
    }

    private var providerHeader: some View {
        HStack(spacing: 10) {
            DDIconChip(
                systemName: provider == .strava ? "figure.run" : "applewatch",
                background: provider == .strava ? DailyDriver.stravaBrand : DailyDriver.blue,
                size: 34
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(ActualsCopy.sourceDisplayName(provider))
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundColor(DailyDriver.foreground)
                Text(ActualsCopy.oauthAuthorizeHeadline(for: provider))
                    .font(.system(size: 10))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var scopeCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(ActualsCopy.oauthScopes(for: provider).enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Rectangle().fill(DailyDriver.border).frame(height: 1)
                }
                HStack(alignment: .top, spacing: 10) {
                    Text(row.granted ? "✓" : "✕")
                        .font(.system(size: 13))
                        .foregroundColor(row.granted ? DailyDriver.lime : DailyDriver.foregroundDim)
                        .frame(width: 14)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(row.granted ? DailyDriver.foreground : DailyDriver.foregroundDim)
                            .strikethrough(!row.granted, color: DailyDriver.foregroundDim)
                        Text(row.subtitle)
                            .font(.system(size: 10))
                            .foregroundColor(DailyDriver.foregroundMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 10)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var authorizeColor: Color {
        provider == .strava ? DailyDriver.stravaBrand : DailyDriver.blue
    }

    // MARK: - Actions

    private func authorizeTapped() {
        guard !isWorking else { return }
        isWorking = true
        authorizeError = nil
        Task { @MainActor in
            // Stub today; real ASWebAuthenticationSession + BFF later.
            let outcome = await auth.authorize(provider)
            ActualsProviderAuthAction.apply(outcome: outcome, provider: provider, store: store)
            isWorking = false
            switch outcome {
            case .success:
                ActualsLinkFeedback.announceLinked(provider)
                onFinished()
                dismiss()
            case .cancelled:
                dismiss()
            case .failed:
                authorizeError = ActualsCopy.oauthAuthorizeFailed
            }
        }
    }

    private func cancelTapped() {
        guard !isWorking else { return }
        // Cancel = nothing linked (no authorize call, no markConnected).
        dismiss()
    }
}

#if DEBUG
#Preview("Strava OAuth scope") {
    ActualsOAuthScopeView(provider: .strava, store: ActualsSourceConnectionStore())
}
#endif
