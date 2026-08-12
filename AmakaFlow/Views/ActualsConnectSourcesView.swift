//
//  ActualsConnectSourcesView.swift
//  AmakaFlow
//
//  AMA-2387: Connect Sources screen — Apple Health / Garmin / Strava, read-only.
//  Copy law: "we only read; we never post" (design-handoff/ACTUALS.md).
//

import SwiftUI

struct ActualsConnectSourcesView<Store: ActualsSourceConnecting>: View where Store: ObservableObject {
    @ObservedObject var store: Store
    var onConnect: (ActualsSourceProvider) -> Void
    var healthKit: any ActualsHealthKitConnecting
    var providerAuth: any ActualsProviderAuthProviding

    @State private var showAppleHealthPrimer = false
    @State private var oauthProvider: ActualsSourceProvider?
    /// AMA-2396: next Strava OAuth must request `activity:write` (write-back reconnect).
    @State private var oauthIncludeWrite = false
    /// AMA-2396: Strava row → write-back settings, once connected.
    @State private var showStravaWriteBack = false
    @ObservedObject private var writeBackSettings: StravaWriteBackSettingsStore

    init(
        store: Store,
        healthKit: (any ActualsHealthKitConnecting)? = nil,
        providerAuth: (any ActualsProviderAuthProviding)? = nil,
        writeBackSettings: StravaWriteBackSettingsStore? = nil,
        onConnect: ((ActualsSourceProvider) -> Void)? = nil
    ) {
        self.store = store
        self.healthKit = healthKit ?? LiveActualsHealthKitConnector()
        self.providerAuth = providerAuth ?? ActualsProviderAuthFactory.makeDefault()
        self.writeBackSettings = writeBackSettings ?? .shared
        // Children already markConnected on grant/success — default is parent UI only.
        self.onConnect = onConnect ?? { _ in }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 8)

                VStack(spacing: 9) {
                    ForEach(ActualsSourceProvider.allCases) { provider in
                        sourceRow(provider)
                        if provider == .strava, store.isConnected(.strava) {
                            stravaWriteBackEntryRow
                        }
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
            ActualsAppleHealthPrimerView(store: store, healthKit: healthKit) {
                onConnect(.appleHealth)
            }
        }
        .navigationDestination(item: $oauthProvider) { provider in
            // Capture includeWrite for this push — clearing the flag later must not
            // change what Authorize requests / what we unlock on success.
            let requestedWrite = oauthIncludeWrite
            ActualsOAuthScopeView(
                provider: provider,
                store: store,
                auth: providerAuth,
                includeWrite: requestedWrite
            ) { outcome in
                if provider == .strava {
                    // Prefer parsed scope; if Strava/redirect omitted scope after a
                    // write reconnect, still unlock — Authorize was for write.
                    let unlock = outcome.grantedWrite || (requestedWrite && outcome.isSuccess)
                    writeBackSettings.applyWriteGrantFromOAuth(grantedWrite: unlock)
                    oauthIncludeWrite = false
                    if unlock {
                        DDToastCenter.shared.success("Strava write-back enabled")
                    }
                }
                onConnect(provider)
            }
        }
        .navigationDestination(isPresented: $showStravaWriteBack) {
            ActualsStravaWriteBackView(store: writeBackSettings) {
                startWriteBackReconnect()
            }
        }
    }

    /// Pop write-back settings, then push Strava OAuth with `activity:write`.
    private func startWriteBackReconnect() {
        showStravaWriteBack = false
        oauthIncludeWrite = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            oauthProvider = .strava
        }
    }

    // MARK: - Strava write-back entry

    private var stravaWriteBackEntryRow: some View {
        Button {
            showStravaWriteBack = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DailyDriver.foregroundMuted)
                Text("Write-back settings")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(DailyDriver.foregroundMuted)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DailyDriver.foregroundDim)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(DailyDriver.card2)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("af_actuals_strava_writeback_entry")
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
                VStack(alignment: .trailing, spacing: 6) {
                    Text(
                        store.isFreshlyLinked(provider)
                            ? ActualsCopy.linkedJustNowBadge
                            : ActualsCopy.connectedBadge
                    )
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(DailyDriver.lime)
                    .fixedSize()
                    // Re-auth without looking "not connected" — Connect CTA was confusing dogfood.
                    if provider == .strava || provider == .garmin {
                        Button {
                            connectTapped(provider)
                        } label: {
                            Text(ActualsCopy.reconnectButton)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(DailyDriver.foregroundMuted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(provider.accessibilityConnectID)
                    }
                }
            } else {
                let opensSettings = provider == .appleHealth
                    && (healthKit.authorizationState == .denied
                        || healthKit.authorizationState == .promptCompleted)
                Button {
                    connectTapped(provider)
                } label: {
                    Text(
                        opensSettings
                            ? ActualsCopy.openHealthSettingsButton
                            : ActualsCopy.connectButton
                    )
                        .ddDisplayText(12, weight: .bold)
                        .foregroundColor(DailyDriver.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(connectButtonBackground(for: provider))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityIdentifier(
                    opensSettings
                        ? ActualsCopy.appleHealthSettingsAccessibilityID
                        : provider.accessibilityConnectID
                )
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
        case .strava: return DailyDriver.stravaBrand
        }
    }

    /// Connect CTA background — Strava keeps its brand red; other sources use lime.
    private func connectButtonBackground(for provider: ActualsSourceProvider) -> Color {
        provider == .strava ? DailyDriver.stravaBrand : DailyDriver.lime
    }

    private func connectTapped(_ provider: ActualsSourceProvider) {
        switch provider {
        case .appleHealth:
            if healthKit.authorizationState == .denied {
                healthKit.openHealthSettings()
            } else if healthKit.authorizationState == .promptCompleted {
                // AMA-2419: older installs stuck on promptCompleted — retry evidence query.
                Task { @MainActor in
                    let outcome = await healthKit.connect()
                    ActualsAppleHealthConnectAction.apply(
                        outcome: outcome,
                        store: store
                    ) {
                        healthKit.openHealthSettings()
                    }
                    if outcome == .granted {
                        ActualsLinkFeedback.announceLinked(.appleHealth)
                        onConnect(.appleHealth)
                    }
                }
            } else {
                showAppleHealthPrimer = true
            }
        case .garmin:
            oauthIncludeWrite = false
            oauthProvider = provider
        case .strava:
            // Fresh Connect stays read-only. Write-back Reconnect sets oauthIncludeWrite
            // before pushing this destination — don't clear it here.
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
        self.init(store: ActualsSourceConnectionStore.shared)
    }
}

#if DEBUG
#Preview("Connect sources") {
    ActualsConnectSourcesView(store: ActualsSourceConnectionStore())
}
#endif
