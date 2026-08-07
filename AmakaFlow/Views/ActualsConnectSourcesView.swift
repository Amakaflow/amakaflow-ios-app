//
//  ActualsConnectSourcesView.swift
//  AmakaFlow
//
//  AMA-2387: Connect Sources screen — Apple Health / Garmin / Strava, read-only.
//  Copy law: "we only read; we never post" (design-handoff/ACTUALS.md).
//

import SwiftUI

/// Strava brand red — the one non-lime Connect CTA (design-handoff/reference/screens-actuals.jsx).
private let stravaBrandColor = Color(hex: "FC4C02")

struct ActualsConnectSourcesView<Store: ActualsSourceConnecting>: View where Store: ObservableObject {
    @ObservedObject var store: Store
    var onConnect: (ActualsSourceProvider) -> Void
    var healthKit: any ActualsHealthKitConnecting
    var providerAuth: any ActualsProviderAuthProviding

    @State private var showAppleHealthPrimer = false
    @State private var oauthProvider: ActualsSourceProvider?

    init(
        store: Store,
        healthKit: (any ActualsHealthKitConnecting)? = nil,
        providerAuth: (any ActualsProviderAuthProviding)? = nil,
        onConnect: ((ActualsSourceProvider) -> Void)? = nil
    ) {
        self.store = store
        self.healthKit = healthKit ?? LiveActualsHealthKitConnector()
        self.providerAuth = providerAuth ?? StubActualsProviderAuth()
        self.onConnect = onConnect ?? { [store] provider in store.markConnected(provider) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 8)

                VStack(spacing: 9) {
                    ForEach(ActualsSourceProvider.allCases) { provider in
                        sourceRow(provider)
                    }
                }
                .padding(.top, 16)

                dedupeFooter
                    .padding(.top, 6)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 96)
        }
        .background(DailyDriver.screenBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .ddSuppressFloatingChrome()
        .navigationDestination(isPresented: $showAppleHealthPrimer) {
            ActualsAppleHealthPrimerView(store: store, healthKit: healthKit)
        }
        .navigationDestination(item: $oauthProvider) { provider in
            ActualsOAuthScopeView(provider: provider, store: store, auth: providerAuth)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(ActualsCopy.connectTitle)
                .ddDisplayText(26, weight: .heavy)
                .foregroundColor(DailyDriver.foreground)

            Text(ActualsCopy.connectSubhead)
                .font(.system(size: 11.5))
                .foregroundColor(DailyDriver.foregroundMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Source row

    private func sourceRow(_ provider: ActualsSourceProvider) -> some View {
        let connected = store.isConnected(provider)

        return HStack(alignment: .center, spacing: 12) {
            DDIconChip(
                systemName: iconName(for: provider),
                background: iconBackground(for: provider),
                size: 40
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(ActualsCopy.sourceDisplayName(provider))
                    .ddDisplayText(14.5, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)

                Text(ActualsCopy.sourceOneLiner(provider))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundDim)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minWidth: 0)

            Spacer(minLength: 8)

            if connected {
                Text(
                    store.isFreshlyLinked(provider)
                        ? ActualsCopy.linkedJustNowBadge
                        : ActualsCopy.connectedBadge
                )
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(DailyDriver.lime)
                    .fixedSize()
            } else {
                Button {
                    connectTapped(provider)
                } label: {
                    Text(ActualsCopy.connectButton)
                        .ddDisplayText(12, weight: .bold)
                        .foregroundColor(DailyDriver.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(connectButtonBackground(for: provider))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityIdentifier(provider.accessibilityConnectID)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(provider.accessibilityRowID)
    }

    private func iconName(for provider: ActualsSourceProvider) -> String {
        switch provider {
        case .appleHealth, .garmin: return "applewatch"
        case .strava: return "figure.run"
        }
    }

    private func iconBackground(for provider: ActualsSourceProvider) -> Color {
        switch provider {
        case .appleHealth: return DailyDriver.card2
        case .garmin: return DailyDriver.blue
        case .strava: return stravaBrandColor
        }
    }

    /// Connect CTA background — Strava keeps its brand red; other sources use lime.
    private func connectButtonBackground(for provider: ActualsSourceProvider) -> Color {
        provider == .strava ? stravaBrandColor : DailyDriver.lime
    }

    private func connectTapped(_ provider: ActualsSourceProvider) {
        switch provider {
        case .appleHealth:
            // Retry after Don't Allow: iOS never re-prompts — jump straight to Settings.
            if healthKit.authorizationState == .denied {
                healthKit.openHealthSettings()
            } else {
                showAppleHealthPrimer = true
            }
        case .garmin, .strava:
            oauthProvider = provider
        }
    }

    // MARK: - Dedupe footer

    private var dedupeFooter: some View {
        Text(ActualsCopy.connectDedupeFooter)
            .font(.system(size: 8.5, design: .monospaced))
            .foregroundColor(DailyDriver.foregroundMuted)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundColor(DailyDriver.border)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

extension ActualsConnectSourcesView where Store == ActualsSourceConnectionStore {
    init() {
        self.init(store: ActualsSourceConnectionStore())
    }
}

#if DEBUG
#Preview("Connect sources") {
    ActualsConnectSourcesView(store: ActualsSourceConnectionStore())
}
#endif
