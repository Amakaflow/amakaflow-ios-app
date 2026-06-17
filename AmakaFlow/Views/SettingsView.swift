//
//  SettingsView.swift
//  AmakaFlow
//
//  Settings screen with device selection, audio cues, and preferences
//

import SwiftUI

// MARK: - Audio Behavior

enum AudioBehavior: String, CaseIterable {
    case duck = "duck"
    case pause = "pause"

    var title: String {
        switch self {
        case .duck: return "Duck music"
        case .pause: return "Pause music"
        }
    }
}

struct ConnectedAppEntry: Identifiable, Equatable {
    let id: String
    let name: String
    let detail: String
    let icon: String
}

struct ConnectedAppsResolver {
    static func entries(
        calendars: [ConnectedCalendar],
        garminConnected: Bool,
        garminDeviceName: String?,
        telegramLinked: Bool,
        telegramIdentifier: String?
    ) -> [ConnectedAppEntry] {
        var entries: [ConnectedAppEntry] = calendars
            .filter { isConnectedCalendarStatus($0.status) }
            .map { calendar in
                ConnectedAppEntry(
                    id: "calendar-\(calendar.id)",
                    name: displayName(forCalendarProvider: calendar.provider, fallback: calendar.name),
                    detail: calendar.email ?? calendar.status.capitalized,
                    icon: "calendar"
                )
            }

        if garminConnected {
            entries.append(
                ConnectedAppEntry(
                    id: "garmin",
                    name: "Garmin",
                    detail: garminDeviceName ?? "Connected watch",
                    icon: "applewatch"
                )
            )
        }

        if telegramLinked {
            entries.append(
                ConnectedAppEntry(
                    id: "telegram",
                    name: "Telegram",
                    detail: telegramIdentifier.map { "Connected to \($0)" } ?? "Coach messages connected",
                    icon: "paperplane.fill"
                )
            )
        }

        return entries
    }

    private static func isConnectedCalendarStatus(_ status: String) -> Bool {
        switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "connected", "active", "syncing", "synced":
            return true
        default:
            return false
        }
    }

    private static func displayName(forCalendarProvider provider: String, fallback: String) -> String {
        switch provider.lowercased() {
        case "google": return "Google Calendar"
        case "outlook", "microsoft": return "Microsoft Outlook"
        case "runna": return "Runna"
        case "stryd": return "Stryd"
        case "ics", "ics_custom": return fallback.isEmpty ? "External calendar" : fallback
        default: return fallback.isEmpty ? provider.capitalized : fallback
        }
    }
}

struct SettingsView: View {
    @Binding var navigateToSyncDashboard: Bool
    @AppStorage(DefaultsKey.devicePreference.rawValue) private var deviceMode: DevicePreference = .appleWatchPhone
    @AppStorage(DefaultsKey.instagramImportMode.rawValue) private var instagramImportMode: InstagramImportMode = .manual
    // AMA-1649: prefer the local user.displayName override (set in
    // EditProfileView) over the Clerk profile name when rendering the
    // account summary card.
    @AppStorage(DefaultsKey.userDisplayName.rawValue) private var displayNameOverride: String = ""
    @State private var voiceCuesEnabled = true
    @State private var audioBehavior: AudioBehavior = .duck
    @State private var countdownBeepsEnabled = true
    @State private var hapticFeedbackEnabled = true
    @StateObject private var accountViewModel = AccountSectionViewModel()
    @State private var showingDisconnectAlert = false
    @State private var showingGarminDebugAlert = false
    @State private var garminDebugMessage = ""
    @State private var showingManualUUIDSheet = false
    @State private var manualUUID = ""
    @State private var manualDeviceName = ""
    @State private var showingDebugLog = false
    @State private var showingWorkoutDebugSheet = false
    @State private var showingVoiceTranscriptionSettings = false
    @StateObject private var nutritionViewModel = NutritionViewModel()
    @StateObject private var calendarSyncViewModel = CalendarSyncViewModel()
    @ObservedObject private var watchConnectivity = WatchConnectivityManager.shared
    @State private var syncQueueSummary = SyncQueueSummary.healthy
    @State private var showingNutritionSettings = false
    @State private var showingErrorLogSheet = false
    @State private var showDebugSettings = false
    @State private var debugTapCount = 0
    @State private var debugTapResetTask: DispatchWorkItem?
    @State private var showingTelegramSetup = false
    @State private var showingPaywall = false
    @State private var connectedTelegramId: Int?
    @EnvironmentObject private var garminConnectivity: GarminConnectManager
    @EnvironmentObject private var pairingService: PairingService
    @EnvironmentObject private var workoutsViewModel: WorkoutsViewModel
    @EnvironmentObject private var subscriptionAccess: SubscriptionAccessViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                AFTopBar(title: "Profile") {
                    EmptyView()
                } right: {
                    EmptyView()
                }

                settingsHero
                connectionsSection
                profileTrainingSection
                coachingSection
                nutritionActivitySection
                appSection
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.lg)
            .padding(.bottom, 100)
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationBarHidden(true)
            .alert("Sign Out", isPresented: $accountViewModel.showSignOutAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) {
                    Task { await AuthViewModel.shared.signOut() }
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .alert("Garmin Debug", isPresented: $showingGarminDebugAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(garminDebugMessage)
            }
            .alert("Privacy", isPresented: $accountViewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(accountViewModel.errorMessage ?? "Something went wrong. Please try again.")
            }
            .confirmationDialog("Delete account?", isPresented: $accountViewModel.showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete permanently", role: .destructive) {
                    Task { await accountViewModel.deleteAccount { clearTelegramLinked() } }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes all your workouts, programs, profile, and connected data. This cannot be undone.")
            }
            .sheet(isPresented: $accountViewModel.showShareSheet) {
                if let url = accountViewModel.exportedFileURL {
                    ShareSheet(activityItems: [url])
                }
            }
            .sheet(isPresented: $showingManualUUIDSheet) {
                manualUUIDSheet
            }
            .sheet(isPresented: $showingDebugLog) {
                debugLogSheet
            }
            .sheet(isPresented: $showingWorkoutDebugSheet) {
                workoutDebugSheet
            }
            .sheet(isPresented: $showingVoiceTranscriptionSettings) {
                NavigationStack {
                    VoiceTranscriptionSettingsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    showingVoiceTranscriptionSettings = false
                                }
                            }
                        }
                }
            }
            .sheet(isPresented: $showingErrorLogSheet) {
                NavigationStack {
                    DebugLogView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    showingErrorLogSheet = false
                                }
                            }
                        }
                }
            }
            #if DEBUG
            .sheet(isPresented: $showDebugSettings) {
                NavigationStack {
                    DebugSettingsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    showDebugSettings = false
                                }
                            }
                        }
                }
            }
            #endif
            .fullScreenCover(isPresented: $showingPaywall) {
                PaywallView()
                    .environmentObject(subscriptionAccess)
            }
            .overlay(alignment: .top) {
                // Invisible marker for Maestro E2E tests (container views
                // don't expose accessibilityIdentifier on iOS 26)
                Text(" ")
                    .font(.system(size: 1))
                    .opacity(0.01)
                    .accessibilityIdentifier("settings_screen")
            }
            .navigationDestination(isPresented: $navigateToSyncDashboard) {
                ConnectionDetailView(item: connectionsItem(.sync)) {
                    SyncDashboardView()
                }
            }
            .task(id: pairingService.userProfile?.id) {
                await refreshTelegramConnectionState()
                await refreshConnectionSummaries()
            }
    }

    // MARK: - Refresh Header

    private var settingsHero: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Profile")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text("Profile, training, coaching, and app controls grouped for quick scanning.")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                ZStack {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                        .fill(Theme.Colors.accentBlue.opacity(0.14))
                        .frame(width: 56, height: 56)
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(Theme.Colors.accentBlue)
                }
            }

            HStack(spacing: Theme.Spacing.sm) {
                SettingsStatusPill(
                    icon: deviceMode.iconName,
                    title: deviceMode.title,
                    tint: deviceMode.accentColor
                )
                SettingsStatusPill(
                    icon: isTelegramLinked ? "paperplane.fill" : "paperplane",
                    title: isTelegramLinked ? "Telegram on" : "Telegram off",
                    tint: Color(hex: "29B6F6")
                )
                SettingsStatusPill(
                    icon: voiceCuesEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                    title: voiceCuesEnabled ? "Voice cues" : "Quiet mode",
                    tint: Theme.Colors.accentBlue
                )
            }
        }
        .padding(Theme.Spacing.lg)
        .background(
            LinearGradient(
                colors: [
                    Theme.Colors.surface,
                    Theme.Colors.surfaceElevated.opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.xl)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.xl))
        .accessibilityIdentifier("settings_refresh_header")
    }

    // MARK: - Grouped Profile Sections

    private var connectionsStatusSnapshot: ConnectionsHubStatusSnapshot {
        ConnectionsHubStatusSnapshot(
            appleWatchReachable: watchConnectivity.isWatchReachable,
            appleWatchInstalled: watchConnectivity.isWatchAppInstalled,
            devicePreference: deviceMode,
            garminConnected: garminConnectivity.isConnected,
            garminDeviceName: garminConnectivity.connectedDeviceName,
            telegramLinked: isTelegramLinked,
            telegramIdentifier: connectedTelegramId.map(String.init),
            syncSummary: syncQueueSummary,
            connectedCalendars: calendarSyncViewModel.calendars
        )
    }

    private func connectionsItem(_ kind: ConnectionKind) -> ConnectionItem {
        ConnectionsHubViewModel
            .makeItems(from: connectionsStatusSnapshot)
            .first { $0.kind == kind } ?? ConnectionItem(kind: kind, status: .off, meta: [])
    }

    private var connectionsHub: ConnectionsHubView {
        ConnectionsHubView(
            viewModel: ConnectionsHubViewModel(statusProvider: connectionsStatusSnapshot),
            statusProvider: { connectionsStatusSnapshot },
            telegramInitialID: connectedTelegramId,
            telegramInitiallyConnected: isTelegramLinked
        ) { telegramId in
            connectedTelegramId = telegramId
            TelegramLinkCache.markLinked(
                telegramId: telegramId,
                userID: pairingService.userProfile?.id
            )
        }
    }

    private var connectionsSection: some View {
        SettingsSectionCard(
            title: settingsSectionTitle("connections", fallback: "Connections"),
            subtitle: "Watches, messaging, delivery, and calendar in one status hub."
        ) {
            NavigationLink(destination: connectionsHub) {
                HStack(spacing: Theme.Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                            .fill(Theme.Colors.readyHigh.opacity(0.14))
                            .frame(width: 44, height: 44)
                        Image(systemName: "link")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Theme.Colors.readyHigh)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Connections")
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text(ConnectionsHubViewModel(statusProvider: connectionsStatusSnapshot).summaryText)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }

                    Spacer(minLength: Theme.Spacing.md)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings_row_connections")
        }
    }

    private var profileTrainingSection: some View {
        groupedSettingsSection(
            id: "profile_training",
            fallbackTitle: "Profile & Training",
            subtitle: "Goals, training defaults, and equipment."
        )
    }

    private var coachingSection: some View {
        SettingsSectionCard(
            title: settingsSectionTitle("coaching", fallback: "Coaching"),
            subtitle: "Readiness signals and how your coach reaches you."
        ) {
            VStack(spacing: 0) {
                let rows = settingsRows(in: "coaching", includeDebug: false)
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    settingsPreferenceRow(row)
                    if index < rows.count - 1 {
                        SettingsRowDivider()
                    }
                }

                audioCueControls
            }
        }
    }

    private var nutritionActivitySection: some View {
        groupedSettingsSection(
            id: "nutrition_activity",
            fallbackTitle: "Nutrition & Activity",
            subtitle: "Fueling, social activity, and comparison tools."
        )
    }

    private var appSection: some View {
        SettingsSectionCard(
            title: settingsSectionTitle("app", fallback: "App"),
            subtitle: "Diagnostics, privacy, export, and account actions."
        ) {
            VStack(spacing: 0) {
                #if DEBUG
                let debugRows = settingsRows(in: "debug", includeDebug: true)
                ForEach(Array(debugRows.enumerated()), id: \.element.id) { _, row in
                    settingsDebugRow(row)
                    SettingsRowDivider()
                }
                #endif

                let rows = settingsRows(in: "app", includeDebug: false)
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    settingsPreferenceRow(row)
                    if index < rows.count - 1 {
                        SettingsRowDivider()
                    }
                }
            }
        }
    }

    private func groupedSettingsSection(
        id: String,
        fallbackTitle: String,
        subtitle: String
    ) -> some View {
        SettingsSectionCard(
            title: settingsSectionTitle(id, fallback: fallbackTitle),
            subtitle: subtitle
        ) {
            VStack(spacing: 0) {
                let rows = settingsRows(in: id, includeDebug: false)
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    settingsPreferenceRow(row)
                    if index < rows.count - 1 {
                        SettingsRowDivider()
                    }
                }
            }
        }
    }

    private func refreshConnectionSummaries() async {
        await calendarSyncViewModel.fetchCalendars()
        do {
            syncQueueSummary = try SyncQueueRepository().summary()
        } catch {
            DebugLogService.shared.log("Connections hub sync summary failed", details: error.localizedDescription)
            syncQueueSummary = SyncQueueSummary(
                pendingCount: 0,
                inFlightCount: 0,
                failedCount: 1,
                poisonCount: 0,
                lastAttemptedAt: nil,
                latestError: error.localizedDescription
            )
        }
    }

    // MARK: - Preferences Hub

    private var preferencesHubSection: some View {
        SettingsSectionCard(
            title: settingsSectionTitle("preferences", fallback: "Preferences"),
            subtitle: "Keep the existing app settings organized by what they control."
        ) {
            VStack(spacing: 0) {
                let rows = settingsRows(in: "preferences", includeDebug: false)
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    settingsPreferenceRow(row)
                    if index < rows.count - 1 {
                        SettingsRowDivider()
                    }
                }

                audioCueControls
            }
        }
    }

    @ViewBuilder
    private func settingsPreferenceRow(_ row: SettingsRefreshRowModel) -> some View {
        switch row.destination {
        case .editProfile:
            NavigationLink(destination: EditProfileView(initialNameFallback: pairingService.userProfile?.name)) {
                SettingsNavigationRow(
                    icon: "person.crop.circle.fill",
                    tint: Theme.Colors.accentBlue,
                    title: row.title,
                    subtitle: row.subtitle
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings_row_edit_profile")

        case .connections:
            NavigationLink(destination: connectionsHub) {
                SettingsNavigationRow(
                    icon: "link",
                    tint: Theme.Colors.readyHigh,
                    title: row.title,
                    subtitle: row.subtitle
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings_row_connections")

        case .readinessSources:
            NavigationLink(destination: SourcesView()) {
                SettingsNavigationRow(
                    icon: "heart.text.square.fill",
                    tint: Theme.Colors.readyHigh,
                    title: row.title,
                    subtitle: row.subtitle
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings_row_readiness_sources")

        case .notifications:
            NavigationLink(destination: NotificationPreferencesView()) {
                SettingsNavigationRow(
                    icon: "bell.badge.fill",
                    tint: Color(hex: "9333EA"),
                    title: row.title,
                    subtitle: row.subtitle
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings_row_notifications")

        case .voice:
            Button {
                showingVoiceTranscriptionSettings = true
            } label: {
                SettingsNavigationRow(
                    icon: "waveform",
                    tint: .purple,
                    title: row.title,
                    subtitle: row.subtitle
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings_row_voice")

        case .fatigue:
            NavigationLink(destination: FatigueSettingsView()) {
                SettingsNavigationRow(
                    icon: "heart.text.square.fill",
                    tint: Theme.Colors.accentBlue,
                    title: row.title,
                    subtitle: row.subtitle
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings_row_fatigue")

        case .nutrition:
            NavigationLink(destination: NutritionSettingsView(viewModel: nutritionViewModel)) {
                SettingsNavigationRow(
                    icon: "leaf.fill",
                    tint: Theme.Colors.accentGreen,
                    title: row.title,
                    subtitle: row.subtitle
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings_row_nutrition")

        case .social:
            NavigationLink(destination: SocialSettingsView()) {
                SettingsNavigationRow(
                    icon: "person.2.fill",
                    tint: Theme.Colors.accentOrange,
                    title: row.title,
                    subtitle: row.subtitle
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings_row_social")

        case .trainingPreferences:
            NavigationLink(destination: TrainingPreferencesView()) {
                SettingsNavigationRow(
                    icon: "slider.horizontal.3",
                    tint: Theme.Colors.accentBlue,
                    title: row.title,
                    subtitle: row.subtitle
                )
            }
            .buttonStyle(.plain)

        case .equipment:
            NavigationLink(destination: EquipmentProfileView()) {
                SettingsNavigationRow(
                    icon: "dumbbell.fill",
                    tint: Theme.Colors.readyHigh,
                    title: row.title,
                    subtitle: row.subtitle
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings_row_equipment")

        case .paywall:
            Button {
                showingPaywall = true
            } label: {
                SettingsNavigationRow(
                    icon: "sparkles",
                    tint: Theme.Colors.readyHigh,
                    title: row.title,
                    subtitle: row.subtitle
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings_row_paywall")

        case .activityFeed:
            NavigationLink(destination: ActivityFeedView()) {
                SettingsNavigationRow(
                    icon: "bell.and.waves.left.and.right.fill",
                    tint: Theme.Colors.accentOrange,
                    title: row.title,
                    subtitle: row.subtitle
                )
            }
            .buttonStyle(.plain)

        case .syncDashboard:
            NavigationLink(destination: SyncDashboardView()) {
                SettingsNavigationRow(
                    icon: "arrow.triangle.2.circlepath",
                    tint: Theme.Colors.accentGreen,
                    title: row.title,
                    subtitle: row.subtitle
                )
            }
            .buttonStyle(.plain)

        case .shoeComparison:
            NavigationLink(destination: ShoeComparisonView()) {
                SettingsNavigationRow(
                    icon: "shoe.fill",
                    tint: Theme.Colors.accentGreen,
                    title: row.title,
                    subtitle: row.subtitle
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings_row_shoe_comparison")

        case .accountPrivacyData:
            Menu {
                Button {
                    Task { await accountViewModel.exportData() }
                } label: {
                    Label("Export my data", systemImage: "square.and.arrow.up")
                }

                Link(destination: URL(string: "https://app.amakaflow.com/privacy")!) {
                    Label("Privacy notice", systemImage: "doc.text")
                }

                Button(role: .destructive) {
                    accountViewModel.showSignOutAlert = true
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }

                Button(role: .destructive) {
                    accountViewModel.showDeleteConfirm = true
                } label: {
                    Label("Delete account", systemImage: "trash")
                }
            } label: {
                SettingsNavigationRow(
                    icon: "person.crop.circle.badge.checkmark",
                    tint: Theme.Colors.accentBlue,
                    title: row.title,
                    subtitle: row.subtitle
                )
            }
            .accessibilityIdentifier("settings_row_account_privacy")

        default:
            EmptyView()
        }
    }

    private var audioCueControls: some View {
        VStack(spacing: 0) {
            SettingsRowDivider()

            SettingsToggleRow(
                icon: "speaker.wave.2.fill",
                iconColor: Theme.Colors.accentBlue,
                title: "Voice Cues",
                subtitle: "Announce exercise names and transitions",
                isOn: $voiceCuesEnabled
            )
            .padding(.top, Theme.Spacing.sm)

            if voiceCuesEnabled {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("When music is playing")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)

                    HStack(spacing: 0) {
                        ForEach(AudioBehavior.allCases, id: \.self) { behavior in
                            Button {
                                audioBehavior = behavior
                            } label: {
                                Text(behavior.title)
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(audioBehavior == behavior ? .white : Theme.Colors.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, Theme.Spacing.sm)
                                    .background(audioBehavior == behavior ? Theme.Colors.accentBlue : Color.clear)
                                    .cornerRadius(Theme.CornerRadius.sm)
                            }
                        }
                    }
                    .padding(4)
                    .background(Theme.Colors.surfaceElevated)
                    .cornerRadius(Theme.CornerRadius.md)
                }
                .padding(.top, Theme.Spacing.sm)
            }

            SettingsToggleRow(
                icon: "timer",
                iconColor: Theme.Colors.accentBlue,
                title: "Countdown Beeps",
                subtitle: "Audio beeps for the last 5 seconds of timed intervals",
                isOn: $countdownBeepsEnabled
            )
            .padding(.top, Theme.Spacing.sm)

            SettingsToggleRow(
                icon: "iphone.radiowaves.left.and.right",
                iconColor: Theme.Colors.accentBlue,
                title: "Haptic Feedback",
                subtitle: "Vibrate on exercise transitions for watch and phone",
                isOn: $hapticFeedbackEnabled
            )
            .padding(.top, Theme.Spacing.sm)
        }
    }

    // MARK: - Debug Diagnostics

    #if DEBUG
    private var debugDiagnosticsSection: some View {
        SettingsSectionCard(
            title: settingsSectionTitle("debug", fallback: "Debug"),
            subtitle: "Existing developer-only diagnostics and support tools."
        ) {
            VStack(spacing: 0) {
                let rows = settingsRows(in: "debug", includeDebug: true)
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    settingsDebugRow(row)
                    if index < rows.count - 1 {
                        SettingsRowDivider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func settingsDebugRow(_ row: SettingsRefreshRowModel) -> some View {
        switch row.destination {
        case .debugSettings:
            Button {
                showDebugSettings = true
            } label: {
                SettingsNavigationRow(
                    icon: "wrench.and.screwdriver.fill",
                    tint: Theme.Colors.accentOrange,
                    title: row.title,
                    subtitle: row.subtitle
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings_row_debug_settings")

        case .errorLog:
            Button {
                showingErrorLogSheet = true
            } label: {
                SettingsNavigationRow(
                    icon: "ladybug.fill",
                    tint: Theme.Colors.accentOrange,
                    title: row.title,
                    subtitle: "\(DebugLogService.shared.entries.count) captured entries"
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings_row_error_log")

        case .workoutDebug:
            Button {
                showingWorkoutDebugSheet = true
            } label: {
                SettingsNavigationRow(
                    icon: "ant.fill",
                    tint: Theme.Colors.accentOrange,
                    title: row.title,
                    subtitle: workoutsViewModel.pendingWorkoutsStatus.isEmpty ? row.subtitle : workoutsViewModel.pendingWorkoutsStatus
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings_row_workout_debug")

        default:
            EmptyView()
        }
    }
    #endif

    private func settingsRows(in sectionID: String, includeDebug: Bool) -> [SettingsRefreshRowModel] {
        SettingsRefreshSectionModel
            .v1Sections(includeDebug: includeDebug)
            .first { $0.id == sectionID }?
            .rows ?? []
    }

    private func settingsSectionTitle(_ sectionID: String, fallback: String) -> String {
        SettingsRefreshSectionModel
            .v1Sections(includeDebug: true)
            .first { $0.id == sectionID }?
            .title ?? fallback
    }

    // MARK: - Workout Debug Sheet

    private var workoutDebugSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Action buttons
                HStack(spacing: Theme.Spacing.sm) {
                    Button {
                        Task {
                            await workoutsViewModel.checkPendingWorkouts()
                        }
                    } label: {
                        VStack {
                            Image(systemName: "arrow.down.circle")
                            Text("Fetch")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Colors.accentBlue.opacity(0.2))
                        .cornerRadius(Theme.CornerRadius.sm)
                    }

                    Button {
                        workoutsViewModel.addSampleWorkout()
                    } label: {
                        VStack {
                            Image(systemName: "plus.circle")
                            Text("Sample")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Colors.accentGreen.opacity(0.2))
                        .cornerRadius(Theme.CornerRadius.sm)
                    }

                    Button {
                        UIPasteboard.general.string = generateWorkoutDebugText()
                    } label: {
                        VStack {
                            Image(systemName: "doc.on.doc")
                            Text("Copy")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Color.purple.opacity(0.2))
                        .cornerRadius(Theme.CornerRadius.sm)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .foregroundColor(Theme.Colors.textPrimary)

                Divider()

                // Status
                VStack(alignment: .leading, spacing: 4) {
                    Text("Status: \(workoutsViewModel.pendingWorkoutsStatus.isEmpty ? "Not checked" : workoutsViewModel.pendingWorkoutsStatus)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .padding(Theme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colors.surfaceElevated)

                Divider()

                // Workout details
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        // Show all incoming workouts
                        if workoutsViewModel.incomingWorkouts.isEmpty {
                            Text("No incoming workouts loaded.\nTap 'Fetch' to check for pending workouts.")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textTertiary)
                                .padding()
                        } else {
                            ForEach(workoutsViewModel.incomingWorkouts) { workout in
                                workoutDebugCard(workout)
                            }
                        }
                    }
                    .padding(Theme.Spacing.md)
                }
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Workout Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showingWorkoutDebugSheet = false
                    }
                }
            }
        }
    }

    private func workoutDebugCard(_ workout: Workout) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Header
            HStack {
                Text(workout.name)
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Text(workout.sport.rawValue)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.Colors.accentBlue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.Colors.accentBlue.opacity(0.2))
                    .cornerRadius(4)
            }

            // Workout ID and duration
            Text("ID: \(workout.id)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Theme.Colors.textTertiary)
            Text("Duration: \(workout.duration)s (\(workout.formattedDuration))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Theme.Colors.textSecondary)

            Divider()

            // Raw Intervals
            Text("RAW INTERVALS (\(workout.intervals.count))")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.Colors.accentOrange)

            ForEach(Array(workout.intervals.enumerated()), id: \.offset) { index, interval in
                intervalDebugRow(index: index, interval: interval)
            }

            Divider()

            // Flattened Steps
            let flattened = flattenIntervals(workout.intervals)
            Text("FLATTENED STEPS (\(flattened.count))")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.Colors.accentGreen)

            ForEach(Array(flattened.enumerated()), id: \.offset) { index, step in
                flattenedStepDebugRow(index: index, step: step)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .cornerRadius(Theme.CornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
    }

    private func intervalDebugRow(index: Int, interval: WorkoutInterval) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            switch interval {
            case .warmup(let seconds, let target):
                Text("[\(index)] WARMUP")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange)
                Text("  seconds=\(seconds), target=\(target ?? "nil")")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.Colors.textSecondary)

            case .cooldown(let seconds, let target):
                Text("[\(index)] COOLDOWN")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
                Text("  seconds=\(seconds), target=\(target ?? "nil")")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.Colors.textSecondary)

            case .time(let seconds, let target):
                Text("[\(index)] TIME")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.blue)
                Text("  seconds=\(seconds), target=\(target ?? "nil")")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.Colors.textSecondary)

            case .reps(let sets, let reps, let name, let load, let restSec, let followAlongUrl):
                Text("[\(index)] REPS: \(name)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
                Text("  sets=\(sets.map { String($0) } ?? "nil")")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.Colors.textSecondary)
                Text("  reps=\(reps)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.Colors.textSecondary)
                Text("  restSec=\(restSec.map { String($0) } ?? "nil") ← \(restSecExplanation(restSec))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(restSec == nil ? .yellow : (restSec == 0 ? .red : Theme.Colors.textSecondary))
                Text("  load=\(load ?? "nil")")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.Colors.textSecondary)
                if let url = followAlongUrl {
                    Text("  followAlongUrl=\(url)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Theme.Colors.textTertiary)
                }

            case .distance(let meters, let target):
                Text("[\(index)] DISTANCE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.purple)
                Text("  meters=\(meters), target=\(target ?? "nil")")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.Colors.textSecondary)

            case .repeat(let reps, let subIntervals):
                Text("[\(index)] REPEAT x\(reps)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.pink)
                Text("  contains \(subIntervals.count) sub-intervals")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.Colors.textSecondary)

            case .rest(let seconds):
                Text("[\(index)] REST")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                if let secs = seconds {
                    Text("  seconds=\(secs) (timed rest)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Theme.Colors.textSecondary)
                } else {
                    Text("  seconds=nil (manual rest - tap when ready)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.yellow)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func restSecExplanation(_ restSec: Int?) -> String {
        if restSec == nil {
            return "MANUAL REST (tap when ready)"
        } else if restSec == 0 {
            return "NO REST (superset/HIIT)"
        } else {
            return "TIMED REST (\(restSec!)s countdown)"
        }
    }

    private func flattenedStepDebugRow(index: Int, step: FlattenedInterval) -> some View {
        HStack(spacing: 4) {
            Text("[\(index)]")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Theme.Colors.textTertiary)
                .frame(width: 24, alignment: .leading)

            if step.hasRestAfter {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.yellow)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(step.displayLabel)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.Colors.textPrimary)

                HStack(spacing: 8) {
                    Text("type=\(step.stepType == .timed ? "timed" : step.stepType == .reps ? "reps" : "distance")")
                    if let setNum = step.setNumber, let total = step.totalSets {
                        Text("set=\(setNum)/\(total)")
                    }
                    if step.hasRestAfter {
                        let restDesc = step.restAfterSeconds.map { $0 > 0 ? "\($0)s" : "manual" } ?? "manual"
                        Text("rest=\(restDesc)")
                            .foregroundColor(.yellow)
                    }
                }
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func generateWorkoutDebugText() -> String {
        var text = "=== WORKOUT DEBUG ===\n"
        text += "Status: \(workoutsViewModel.pendingWorkoutsStatus)\n\n"

        for workout in workoutsViewModel.incomingWorkouts {
            text += "WORKOUT: \(workout.name)\n"
            text += "ID: \(workout.id)\n"
            text += "Sport: \(workout.sport.rawValue)\n"
            text += "Duration: \(workout.duration)s\n\n"

            text += "RAW INTERVALS:\n"
            for (i, interval) in workout.intervals.enumerated() {
                text += formatIntervalForCopy(index: i, interval: interval)
            }

            text += "\nFLATTENED STEPS:\n"
            let flattened = flattenIntervals(workout.intervals)
            for (i, step) in flattened.enumerated() {
                let restDesc = step.hasRestAfter ? (step.restAfterSeconds.map { $0 > 0 ? "\($0)s" : "manual" } ?? "manual") : "none"
                text += "[\(i)] \(step.displayLabel) | type=\(step.stepType) | rest=\(restDesc)\n"
            }
            text += "\n---\n\n"
        }

        return text
    }

    private func formatIntervalForCopy(index: Int, interval: WorkoutInterval) -> String {
        switch interval {
        case .warmup(let seconds, let target):
            return "[\(index)] WARMUP: seconds=\(seconds), target=\(target ?? "nil")\n"
        case .cooldown(let seconds, let target):
            return "[\(index)] COOLDOWN: seconds=\(seconds), target=\(target ?? "nil")\n"
        case .time(let seconds, let target):
            return "[\(index)] TIME: seconds=\(seconds), target=\(target ?? "nil")\n"
        case .reps(let sets, let reps, let name, let load, let restSec, let followAlongUrl):
            return "[\(index)] REPS: \(name) | sets=\(sets.map { String($0) } ?? "nil") | reps=\(reps) | restSec=\(restSec.map { String($0) } ?? "nil") | load=\(load ?? "nil") | url=\(followAlongUrl ?? "nil")\n"
        case .distance(let meters, let target):
            return "[\(index)] DISTANCE: meters=\(meters), target=\(target ?? "nil")\n"
        case .repeat(let reps, let subIntervals):
            var text = "[\(index)] REPEAT x\(reps):\n"
            for (i, sub) in subIntervals.enumerated() {
                text += "  " + formatIntervalForCopy(index: i, interval: sub)
            }
            return text
        case .rest(let seconds):
            if let secs = seconds {
                return "[\(index)] REST: seconds=\(secs) (timed)\n"
            } else {
                return "[\(index)] REST: manual (tap when ready)\n"
            }
        }
    }

    // MARK: - Debug Log Sheet

    private var debugLogSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Action buttons - Row 1
                HStack(spacing: Theme.Spacing.sm) {
                    Button {
                        garminConnectivity.sendTestPing()
                    } label: {
                        VStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text("Ping")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Colors.accentBlue.opacity(0.2))
                        .cornerRadius(Theme.CornerRadius.sm)
                    }

                    Button {
                        garminConnectivity.sendOpenAppRequest()
                    } label: {
                        VStack {
                            Image(systemName: "play.circle")
                            Text("Wake")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Colors.accentGreen.opacity(0.2))
                        .cornerRadius(Theme.CornerRadius.sm)
                    }

                    Button {
                        garminConnectivity.openWatchApp()
                    } label: {
                        VStack {
                            Image(systemName: "bag")
                            Text("Store")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Colors.accentOrange.opacity(0.2))
                        .cornerRadius(Theme.CornerRadius.sm)
                    }

                    Button {
                        garminConnectivity.clearLog()
                    } label: {
                        VStack {
                            Image(systemName: "trash")
                            Text("Clear")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Colors.accentRed.opacity(0.2))
                        .cornerRadius(Theme.CornerRadius.sm)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .foregroundColor(Theme.Colors.textPrimary)

                // Action buttons - Row 2
                HStack(spacing: Theme.Spacing.sm) {
                    Button {
                        showingManualUUIDSheet = true
                    } label: {
                        VStack {
                            Image(systemName: "keyboard")
                            Text("Manual")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(Theme.CornerRadius.sm)
                    }

                    Button {
                        garminConnectivity.tryAlternativeDeviceDiscovery()
                    } label: {
                        VStack {
                            Image(systemName: "magnifyingglass")
                            Text("Discover")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Color.purple.opacity(0.2))
                        .cornerRadius(Theme.CornerRadius.sm)
                    }

                    Button {
                        garminConnectivity.reinitializeSDK()
                    } label: {
                        VStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Color.yellow.opacity(0.2))
                        .cornerRadius(Theme.CornerRadius.sm)
                    }

                    Button {
                        garminConnectivity.checkAppStatus()
                    } label: {
                        VStack {
                            Image(systemName: "questionmark.circle")
                            Text("Status")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Color.cyan.opacity(0.2))
                        .cornerRadius(Theme.CornerRadius.sm)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .foregroundColor(Theme.Colors.textPrimary)

                Divider()

                // Status summary
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        statusPill("SDK", garminConnectivity.getDetailedStatus()["sdkEnabled"] as? Bool ?? false)
                        statusPill("GCM", garminConnectivity.isGarminConnectInstalled())
                        statusPill("Device", garminConnectivity.isConnected)
                        statusPill("App", garminConnectivity.isAppInstalled)
                    }
                    Text("UUID: \(garminConnectivity.getDetailedStatus()["appUUID"] as? String ?? "?")")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                .padding(Theme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colors.surfaceElevated)

                // Bluetooth permission warning
                if garminConnectivity.isBluetoothUnauthorized {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Bluetooth permission denied")
                            .font(.caption)
                        Spacer()
                        Button("Open Settings") {
                            garminConnectivity.openIOSSettings()
                        }
                        .font(.caption.bold())
                        .foregroundColor(.blue)
                    }
                    .padding(Theme.Spacing.sm)
                    .background(Color.orange.opacity(0.15))
                }

                Divider()

                // Log entries
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if garminConnectivity.debugLog.isEmpty {
                            Text("No log entries yet. Tap 'Ping' to send a test message.")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textTertiary)
                                .padding()
                        } else {
                            ForEach(garminConnectivity.debugLog, id: \.self) { entry in
                                Text(entry)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(logColor(for: entry))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(Theme.Spacing.sm)
                }
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Garmin Debug Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showingDebugLog = false
                    }
                }
            }
        }
    }

    private func statusPill(_ label: String, _ isActive: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isActive ? Color.green : Color.red)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Theme.Colors.surface)
        .cornerRadius(4)
    }

    private func logColor(for entry: String) -> Color {
        if entry.contains("ERROR") || entry.contains("❌") || entry.contains("FAILED") {
            return Theme.Colors.accentRed
        } else if entry.contains("SUCCESS") || entry.contains("✅") || entry.contains("CONNECTED") {
            return Theme.Colors.accentGreen
        } else if entry.contains("WARNING") {
            return Theme.Colors.accentOrange
        }
        return Theme.Colors.textSecondary
    }

    private func formatRefreshDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Manual UUID Entry Sheet

    private var manualUUIDSheet: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("This is a workaround for when the Garmin Connect device picker doesn't work properly.")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)

                    Text("To find your Device UUID:")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .padding(.top, Theme.Spacing.md)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. Open Garmin Connect app")
                        Text("2. Go to Settings > Garmin Devices")
                        Text("3. Select your watch")
                        Text("4. Look for 'Device ID' or 'Unit ID'")
                    }
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                }
                .padding(.horizontal, Theme.Spacing.lg)

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Device Name")
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.textSecondary)

                    TextField("e.g. Forerunner 265", text: $manualDeviceName)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.words)
                }
                .padding(.horizontal, Theme.Spacing.lg)

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Device UUID")
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.textSecondary)

                    TextField("XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX", text: $manualUUID)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .font(.system(.body, design: .monospaced))
                }
                .padding(.horizontal, Theme.Spacing.lg)

                Spacer()

                Button {
                    let name = manualDeviceName.isEmpty ? "Garmin Watch" : manualDeviceName
                    if garminConnectivity.manuallyRegisterDevice(uuidString: manualUUID.trimmingCharacters(in: .whitespacesAndNewlines), friendlyName: name) {
                        showingManualUUIDSheet = false
                        manualUUID = ""
                        manualDeviceName = ""
                    }
                } label: {
                    Text("Connect Device")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.md)
                        .background(Theme.Colors.accentBlue)
                        .cornerRadius(Theme.CornerRadius.md)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.lg)
            }
            .padding(.top, Theme.Spacing.lg)
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Manual Device Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingManualUUIDSheet = false
                    }
                }
            }
        }
    }

    // MARK: - Device Section

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("WORKOUT DEVICE")
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textSecondary)
                .tracking(1)
                .padding(.horizontal, Theme.Spacing.xs)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(DevicePreference.allCases) { mode in
                    DeviceModeRow(
                        mode: mode,
                        isSelected: deviceMode == mode,
                        onSelect: { deviceMode = mode }
                    )
                }

                // Garmin connection UI when Garmin is selected
                if deviceMode == .garminPhone {
                    garminConnectionCard
                }
            }
        }
    }

    // MARK: - Garmin Connection Card

    private var garminConnectionCard: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                        .fill(Theme.Colors.garminBlue.opacity(0.1))
                        .frame(width: 48, height: 48)

                    Image(systemName: "applewatch")
                        .font(.system(size: 22))
                        .foregroundColor(Theme.Colors.garminBlue)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text("Garmin Watch")
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(Theme.Colors.textPrimary)

                        if garminConnectivity.isConnected {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Connected")
                                    .font(Theme.Typography.footnote)
                            }
                            .foregroundColor(Theme.Colors.accentGreen)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, 2)
                            .background(Theme.Colors.accentGreen.opacity(0.1))
                            .cornerRadius(Theme.CornerRadius.sm)
                        }
                    }

                    Text(garminConnectivity.connectedDeviceName ?? "No device connected")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer()
            }

            Button {
                garminConnectivity.showDeviceSelection()
            } label: {
                Text(garminConnectivity.isConnected ? "Change Device" : "Connect Garmin Watch")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.garminBlue.opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                            .stroke(Theme.Colors.garminBlue, lineWidth: 1)
                    )
                    .cornerRadius(Theme.CornerRadius.md)
            }

            // Saved device reconnect (alternative to broken picker)
            if let savedDevice = garminConnectivity.savedDeviceInfo, !garminConnectivity.isConnected {
                Button {
                    garminConnectivity.connectToSavedDevice()
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Reconnect to \(savedDevice.friendlyName)")
                    }
                    .font(Theme.Typography.body)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.accentGreen)
                    .cornerRadius(Theme.CornerRadius.md)
                }
            }

            // Action buttons - Row 1
            HStack(spacing: Theme.Spacing.md) {
                Button {
                    garminConnectivity.openGarminConnectApp()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.forward.app")
                        Text("Open GCM")
                    }
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.garminBlue)
                }

                Button {
                    showingDebugLog = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "ant")
                        Text("Garmin Debug")
                    }
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.accentOrange)
                }

                Button {
                    garminConnectivity.connectToMockDevice()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "ladybug")
                        Text("Test UI")
                    }
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.accentGreen)
                }
            }

            // Action buttons - Row 2
            HStack(spacing: Theme.Spacing.md) {
                if garminConnectivity.savedDeviceInfo != nil {
                    Button {
                        garminConnectivity.clearSavedDevice()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Forget Device")
                        }
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.accentRed)
                    }
                }

                if garminConnectivity.isConnected {
                    Button {
                        garminConnectivity.disconnect()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle")
                            Text("Disconnect")
                        }
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.accentRed)
                    }
                }
            }

            // Debug status section - tap to show full status
            Button {
                garminDebugMessage = garminConnectivity.getSDKStatus()
                showingGarminDebugAlert = true
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DEBUG STATUS (tap for details)")
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.textTertiary)

                    HStack(spacing: Theme.Spacing.md) {
                        statusIndicator("GC App", garminConnectivity.isGarminConnectInstalled())
                        statusIndicator("Device", garminConnectivity.isConnected)
                        statusIndicator("CIQ App", garminConnectivity.isAppInstalled)
                    }

                    if !garminConnectivity.knownDevices.isEmpty {
                        Text("Known: \(garminConnectivity.knownDevices.joined(separator: ", "))")
                            .font(Theme.Typography.footnote)
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                }
                .padding(Theme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colors.surfaceElevated)
                .cornerRadius(Theme.CornerRadius.sm)
            }
            .buttonStyle(.plain)

            // Info text
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Image(systemName: "info.circle")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.Colors.textTertiary)

                Text("Tap 'Connect Garmin Watch' to pair your watch via Garmin Connect Mobile. Once connected, it will be remembered for future sessions.")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(Theme.Colors.garminBlue.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.md)
    }

    private func statusIndicator(_ label: String, _ isActive: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isActive ? Theme.Colors.accentGreen : Theme.Colors.accentRed)
                .frame(width: 8, height: 8)
            Text(label)
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textTertiary)
        }
    }

    // MARK: - Integrations Section

    private var integrationsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("INTEGRATIONS")
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textSecondary)
                .tracking(1)
                .padding(.horizontal, Theme.Spacing.xs)

            connectedAppsCard

            VStack(spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                            .fill(Theme.Colors.accentOrange.opacity(0.1))
                            .frame(width: 48, height: 48)

                        Image(systemName: "heart.fill")
                            .font(.system(size: 22))
                            .foregroundColor(Theme.Colors.accentOrange)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: Theme.Spacing.sm) {
                            Text("Apple Health")
                                .font(Theme.Typography.bodyBold)
                                .foregroundColor(Theme.Colors.textPrimary)

                            HStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Connected")
                                    .font(Theme.Typography.footnote)
                            }
                            .foregroundColor(Theme.Colors.accentGreen)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, 2)
                            .background(Theme.Colors.accentGreen.opacity(0.1))
                            .cornerRadius(Theme.CornerRadius.sm)
                        }

                        Text("Sync workouts and activity data")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }

                    Spacer()
                }

                Button {} label: {
                    Text("Re-authorize Health")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Colors.surfaceElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                                .stroke(Theme.Colors.borderLight, lineWidth: 1)
                        )
                        .cornerRadius(Theme.CornerRadius.md)
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .stroke(Theme.Colors.borderLight, lineWidth: 1)
            )
            .cornerRadius(Theme.CornerRadius.md)

            // Instagram Import Mode
            instagramImportCard

            // Watch Delivery
            watchDeliveryCard

            // Telegram
            telegramCard
        }
    }

    private var connectedAppsCard: some View {
        let entries = ConnectedAppsResolver.entries(
            calendars: calendarSyncViewModel.calendars,
            garminConnected: garminConnectivity.isConnected,
            garminDeviceName: garminConnectivity.connectedDeviceName,
            telegramLinked: isTelegramLinked,
            telegramIdentifier: connectedTelegramId.map(String.init)
        )

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connected apps")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("Real linked services only")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Spacer()
                if calendarSyncViewModel.isLoading {
                    ProgressView().scaleEffect(0.8)
                }
            }

            if entries.isEmpty {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "link.badge.plus")
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text("No connected apps yet")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                    Spacer()
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                .accessibilityIdentifier("connected_apps_empty")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        connectedAppRow(entry)
                        if index < entries.count - 1 {
                            SettingsRowDivider()
                        }
                    }
                }
                .accessibilityIdentifier("connected_apps_list")
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
        .task {
            await calendarSyncViewModel.fetchCalendars()
        }
    }

    private func connectedAppRow(_ entry: ConnectedAppEntry) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.sm)
                    .fill(Theme.Colors.accentBlue.opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: entry.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.Colors.accentBlue)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(entry.detail)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            Spacer()
        }
        .padding(.vertical, Theme.Spacing.sm)
        .accessibilityIdentifier("connected_app_\(entry.id)")
    }


    // MARK: - Watch Delivery Card

    private var watchDeliveryCard: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .fill(Theme.Colors.garminBlue.opacity(0.1))
                    .frame(width: 48, height: 48)
                Image(systemName: "applewatch")
                    .font(.system(size: 22))
                    .foregroundColor(Theme.Colors.garminBlue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Watch Delivery")
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("Open a completed workout to view Garmin delivery and resend if needed")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Spacer()
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.md)
        .accessibilityIdentifier("settings_watch_delivery_info")
    }

    // MARK: - Telegram Card

    private var telegramCard: some View {
        Button(action: { showingTelegramSetup = true }) {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                        .fill(Color(hex: "29B6F6").opacity(0.1))
                        .frame(width: 48, height: 48)
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Color(hex: "29B6F6"))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Telegram")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(telegramStatusSubtitle)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer()

                if isTelegramLinked {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                        Text(connectedTelegramId.map { "Connected to \($0)" } ?? "Connected")
                            .font(Theme.Typography.footnote)
                    }
                    .foregroundColor(Theme.Colors.accentGreen)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 2)
                    .background(Theme.Colors.accentGreen.opacity(0.1))
                    .cornerRadius(Theme.CornerRadius.sm)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.md)
        .sheet(isPresented: $showingTelegramSetup) {
            NavigationStack {
                TelegramSetupView(
                    initialTelegramId: connectedTelegramId,
                    initiallyConnected: isTelegramLinked
                ) { telegramId in
                    connectedTelegramId = telegramId
                    TelegramLinkCache.markLinked(
                        telegramId: telegramId,
                        userID: pairingService.userProfile?.id
                    )
                    showingTelegramSetup = false
                }
            }
        }
        .task(id: pairingService.userProfile?.id) {
            await refreshTelegramConnectionState()
        }
    }

    // MARK: - Instagram Import Card

    private var instagramImportCard: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                        .fill(Color(hex: "E4405F").opacity(0.1))
                        .frame(width: 48, height: 48)

                    Image(systemName: "camera.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Color(hex: "E4405F"))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Instagram Import")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text(instagramImportMode.subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer()
            }

            Picker("Import Mode", selection: $instagramImportMode) {
                ForEach(InstagramImportMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("instagram_mode_picker")
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.md)
    }

    // MARK: - Privacy Section

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("PRIVACY")
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textSecondary)
                .tracking(1)
                .padding(.horizontal, Theme.Spacing.xs)

            VStack(spacing: 0) {
                Button {
                    Task { await accountViewModel.exportData() }
                } label: {
                    HStack {
                        Label("Export my data", systemImage: "square.and.arrow.up")
                            .foregroundColor(Theme.Colors.textPrimary)
                        Spacer()
                        if accountViewModel.isExporting {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "chevron.right")
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                    }
                    .padding(Theme.Spacing.md)
                }
                .disabled(accountViewModel.isExporting)
                .buttonStyle(.plain)

                Divider().padding(.leading, Theme.Spacing.lg)

                Link(destination: URL(string: "https://app.amakaflow.com/privacy")!) {
                    HStack {
                        Label("Privacy notice", systemImage: "doc.text")
                            .foregroundColor(Theme.Colors.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                    .padding(Theme.Spacing.md)
                }

                Divider().padding(.leading, Theme.Spacing.lg)

                Button {
                    accountViewModel.showDeleteConfirm = true
                } label: {
                    HStack {
                        Label("Delete my account", systemImage: "trash")
                            .foregroundColor(Theme.Colors.accentRed)
                        Spacer()
                    }
                    .padding(Theme.Spacing.md)
                }
                .buttonStyle(.plain)
            }
            .background(Theme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .stroke(Theme.Colors.borderLight, lineWidth: 1)
            )
            .cornerRadius(Theme.CornerRadius.md)
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("ACCOUNT")
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textSecondary)
                .tracking(1)
                .padding(.horizontal, Theme.Spacing.xs)

            privacySection

            VStack(spacing: Theme.Spacing.md) {
                // User Profile Card
                HStack(spacing: Theme.Spacing.md) {
                    // Profile image
                    if let avatarUrl = pairingService.userProfile?.avatarUrl,
                       let url = URL(string: avatarUrl) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            profilePlaceholder
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                    } else {
                        profilePlaceholder
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        if let profile = pairingService.userProfile {
                            // AMA-1649: prefer the user-edited displayName
                            // override; fall through to the Clerk profile
                            // name → email → generic placeholder.
                            Text(
                                displayNameOverride.isEmpty
                                ? (profile.name ?? profile.email ?? "AmakaFlow User")
                                : displayNameOverride
                            )
                                .font(Theme.Typography.bodyBold)
                                .foregroundColor(Theme.Colors.textPrimary)

                            if let email = profile.email {
                                Text(email)
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                        } else {
                            Text("Connected")
                                .font(Theme.Typography.bodyBold)
                                .foregroundColor(Theme.Colors.textPrimary)

                            Text("No profile data available")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    }

                    Spacer()

                    // Connection status badge
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Theme.Colors.accentGreen)
                                .frame(width: 8, height: 8)
                            Text("Connected")
                                .font(Theme.Typography.footnote)
                        }
                        .foregroundColor(Theme.Colors.accentGreen)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, 4)
                        .background(Theme.Colors.accentGreen.opacity(0.1))
                        .cornerRadius(Theme.CornerRadius.sm)

                        // Token refresh timestamp
                        if let refreshDate = pairingService.lastTokenRefresh {
                            Text("Refreshed: \(formatRefreshDate(refreshDate))")
                                .font(.system(size: 9))
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                    }
                }

                // AMA-1639: Edit Profile entry point — display name + units.
                // Persists locally via @AppStorage; backend sync is a future
                // ticket once the account API ships.
                NavigationLink {
                    EditProfileView(initialNameFallback: pairingService.userProfile?.name)
                } label: {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 18))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .frame(width: 24)
                        Text("Edit Profile")
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, Theme.Spacing.md)
                    .background(Theme.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                            .stroke(Theme.Colors.borderLight, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings_edit_profile")

                // Environment info
                #if DEBUG
                // Environment selector (DEBUG only)
                HStack {
                    Image(systemName: "server.rack")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text("Environment:")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                    Spacer()
                    Menu {
                        ForEach(AppEnvironment.allCases, id: \.self) { env in
                            Button {
                                AppEnvironment.current = env
                                // Force UI refresh
                                Task { @MainActor in
                                    // Re-check workouts with new environment
                                    await workoutsViewModel.checkPendingWorkouts()
                                }
                            } label: {
                                HStack {
                                    Text(env.displayName)
                                    if env == AppEnvironment.current {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(AppEnvironment.current.displayName)
                                .font(Theme.Typography.caption)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(Theme.Colors.accentBlue)
                    }
                }
                #else
                HStack {
                    Image(systemName: "server.rack")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text("Environment: \(AppEnvironment.current.displayName)")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                    Spacer()
                }
                #endif

                // App version (hidden 7-tap gesture for debug settings - AMA-271)
                HStack {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                    Spacer()
                    #if DEBUG
                    // Show tap progress hint after 3 taps
                    if debugTapCount >= 3 && debugTapCount < 7 {
                        Text("\(7 - debugTapCount) more...")
                            .font(.system(size: 9))
                            .foregroundColor(Theme.Colors.textTertiary.opacity(0.5))
                    }
                    #endif
                }
                #if DEBUG
                .contentShape(Rectangle())
                .onTapGesture {
                    // Cancel any pending reset
                    debugTapResetTask?.cancel()

                    debugTapCount += 1
                    if debugTapCount >= 7 {
                        debugTapCount = 0
                        showDebugSettings = true
                        return
                    }

                    // Schedule reset after 2 seconds of inactivity
                    let task = DispatchWorkItem { [self] in
                        debugTapCount = 0
                    }
                    debugTapResetTask = task
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: task)
                }
                #endif

                #if DEBUG
                // Debug: Copy API token for testing
                HStack {
                    Image(systemName: "key")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text("API Token")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                    Spacer()
                    Button {
                        if let token = pairingService.getToken() {
                            UIPasteboard.general.string = token
                        }
                    } label: {
                        Text("Copy")
                            .font(Theme.Typography.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, 4)
                            .background(Theme.Colors.accentBlue)
                            .cornerRadius(Theme.CornerRadius.sm)
                    }
                }

                // Debug: Refresh Token
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text("Refresh Token")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                    Spacer()
                    Button {
                        Task {
                            let success = await pairingService.refreshToken()
                            print("[Settings] Manual token refresh: \(success ? "SUCCESS" : "FAILED")")
                        }
                    } label: {
                        Text("Refresh")
                            .font(Theme.Typography.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, 4)
                            .background(Theme.Colors.accentGreen)
                            .cornerRadius(Theme.CornerRadius.sm)
                    }
                }

                // Debug: Error Log
                Button {
                    showingErrorLogSheet = true
                } label: {
                    HStack {
                        Image(systemName: "ladybug")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.Colors.accentOrange)
                        Text("Error Log")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textTertiary)
                        Spacer()
                        Text("\(DebugLogService.shared.entries.count)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Theme.Colors.accentOrange)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                }
                .buttonStyle(.plain)
                #endif

                // Debug: Pending workouts status
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.Colors.textTertiary)
                        Text("Pending Workouts:")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textTertiary)
                        Spacer()
                    }
                    Text(workoutsViewModel.pendingWorkoutsStatus.isEmpty ? "Not checked yet" : workoutsViewModel.pendingWorkoutsStatus)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.Colors.accentBlue)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: Theme.Spacing.sm) {
                        Button {
                            Task {
                                await workoutsViewModel.checkPendingWorkouts()
                            }
                        } label: {
                            Text("Check Now")
                                .font(Theme.Typography.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.vertical, Theme.Spacing.xs)
                                .background(Theme.Colors.accentBlue)
                                .cornerRadius(Theme.CornerRadius.sm)
                        }

                        Button {
                            showingWorkoutDebugSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "ant")
                                Text("Workout Debug")
                            }
                            .font(Theme.Typography.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.xs)
                            .background(Theme.Colors.accentOrange)
                            .cornerRadius(Theme.CornerRadius.sm)
                        }
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .stroke(Theme.Colors.borderLight, lineWidth: 1)
            )
            .cornerRadius(Theme.CornerRadius.md)

            // Disconnect button
            Button {
                showingDisconnectAlert = true
            } label: {
                HStack(spacing: Theme.Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                            .fill(Theme.Colors.accentRed.opacity(0.1))
                            .frame(width: 48, height: 48)

                        Image(systemName: "link.badge.minus")
                            .font(.system(size: 22))
                            .foregroundColor(Theme.Colors.accentRed)
                    }

                    Text("Disconnect Account")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)

                    Spacer()
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                        .stroke(Theme.Colors.borderLight, lineWidth: 1)
                )
                .cornerRadius(Theme.CornerRadius.md)
            }
            .buttonStyle(.plain)
        }
        .confirmationDialog("Disconnect Account?", isPresented: $showingDisconnectAlert, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                clearTelegramLinked()
                pairingService.unpair()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to pair again to sync workouts from AmakaFlow.")
        }
    }

    private var telegramLinkedKey: String {
        TelegramLinkCache.linkedKey(userID: pairingService.userProfile?.id)
    }

    private var telegramIdKey: String {
        TelegramLinkCache.idKey(userID: pairingService.userProfile?.id)
    }

    private var telegramStatusSubtitle: String {
        if let connectedTelegramId {
            return "Connected to \(connectedTelegramId)"
        }
        return isTelegramLinked ? "Morning briefings & coach messages" : "Connect for morning briefings"
    }

    private var isTelegramLinked: Bool {
        get { UserDefaults.standard.bool(forKey: telegramLinkedKey) }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: telegramLinkedKey) }
    }

    private func refreshTelegramConnectionState() async {
        if let storedId = UserDefaults.standard.object(forKey: telegramIdKey) as? Int {
            connectedTelegramId = storedId
            isTelegramLinked = true
        } else if isTelegramLinked {
            connectedTelegramId = nil
        }
    }

    private func clearTelegramLinked() {
        TelegramLinkCache.clear(userID: pairingService.userProfile?.id)
        connectedTelegramId = nil
    }



    private var profilePlaceholder: some View {
        ZStack {
            Circle()
                .fill(Theme.Colors.accentBlue.opacity(0.2))
                .frame(width: 56, height: 56)
            Image(systemName: "person.fill")
                .font(.system(size: 24))
                .foregroundColor(Theme.Colors.accentBlue)
        }
    }

    // MARK: - Legal Section

    private var legalSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("LEGAL")
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textSecondary)
                .tracking(1)
                .padding(.horizontal, Theme.Spacing.xs)

            Button {} label: {
                HStack(spacing: Theme.Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                            .fill(Theme.Colors.accentBlue.opacity(0.1))
                            .frame(width: 48, height: 48)

                        Image(systemName: "info.circle")
                            .font(.system(size: 22))
                            .foregroundColor(Theme.Colors.accentBlue)
                    }

                    Text("About")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)

                    Spacer()
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                        .stroke(Theme.Colors.borderLight, lineWidth: 1)
                )
                .cornerRadius(Theme.CornerRadius.md)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Settings Refresh Row Model

struct SettingsRefreshRowModel: Equatable, Identifiable {
    enum Destination: String {
        case connections
        case editProfile
        case notifications
        case fatigue
        case voice
        case readinessSources
        case social
        case nutrition
        case trainingPreferences
        case equipment
        case paywall
        case activityFeed
        case syncDashboard
        case shoeComparison
        case accountPrivacyData
        case debugSettings
        case errorLog
        case workoutDebug
        case about
    }

    let id: String
    let title: String
    let subtitle: String
    let destination: Destination
}

struct SettingsRefreshSectionModel: Equatable, Identifiable {
    let id: String
    let title: String
    let rows: [SettingsRefreshRowModel]

    static func v1Sections(includeDebug: Bool) -> [SettingsRefreshSectionModel] {
        var sections = [
            SettingsRefreshSectionModel(
                id: "connections",
                title: "Connections",
                rows: [
                    SettingsRefreshRowModel(id: "connections_hub", title: "Connections", subtitle: "Watches, messaging, delivery, and calendar", destination: .connections)
                ]
            ),
            SettingsRefreshSectionModel(
                id: "profile_training",
                title: "Profile & Training",
                rows: [
                    SettingsRefreshRowModel(id: "edit_profile", title: "Edit Profile", subtitle: "Goals, experience, and sessions per week", destination: .editProfile),
                    SettingsRefreshRowModel(id: "training_preferences", title: "Training Preferences", subtitle: "Disciplines, auto-swap, and rest days", destination: .trainingPreferences),
                    SettingsRefreshRowModel(id: "equipment", title: "Equipment", subtitle: "Dumbbells, pull-up bar, foam roller, and more", destination: .equipment),
                    SettingsRefreshRowModel(id: "upgrade_pro", title: "AmakaFlow Pro", subtitle: "Adaptive coaching, swaps, and readiness insights", destination: .paywall)
                ]
            ),
            SettingsRefreshSectionModel(
                id: "coaching",
                title: "Coaching",
                rows: [
                    SettingsRefreshRowModel(id: "readiness_sources", title: "Readiness Sources", subtitle: "HRV, sleep, resting HR, and source badges", destination: .readinessSources),
                    SettingsRefreshRowModel(id: "fatigue", title: "Fatigue", subtitle: "Readiness threshold and fatigue tracking", destination: .fatigue),
                    SettingsRefreshRowModel(id: "notifications", title: "Notifications", subtitle: "Reminders, nudges, and coach alerts", destination: .notifications),
                    SettingsRefreshRowModel(id: "voice", title: "Voice Transcription", subtitle: "Provider, accent, and dictionary", destination: .voice)
                ]
            ),
            SettingsRefreshSectionModel(
                id: "nutrition_activity",
                title: "Nutrition & Activity",
                rows: [
                    SettingsRefreshRowModel(id: "nutrition", title: "Nutrition", subtitle: "Targets and fueling reminders", destination: .nutrition),
                    SettingsRefreshRowModel(id: "activity_feed", title: "Activity Feed", subtitle: "Review recent training activity", destination: .activityFeed),
                    SettingsRefreshRowModel(id: "social", title: "Activity / Social", subtitle: "Feed visibility, friends, and sharing", destination: .social),
                    SettingsRefreshRowModel(id: "shoe_comparison", title: "Shoe Comparison", subtitle: "Compare running shoes from your analytics", destination: .shoeComparison)
                ]
            ),
            SettingsRefreshSectionModel(
                id: "app",
                title: "App",
                rows: [
                    SettingsRefreshRowModel(id: "account_privacy_data", title: "Account, privacy & data", subtitle: "Export, privacy notice, sign out, and account deletion", destination: .accountPrivacyData)
                ]
            )
        ]

        if includeDebug {
            sections.insert(
                SettingsRefreshSectionModel(
                    id: "debug",
                    title: "Debug",
                    rows: [
                        SettingsRefreshRowModel(id: "debug_settings", title: "Debug & Diagnostics", subtitle: "Simulation and fixture controls", destination: .debugSettings),
                        SettingsRefreshRowModel(id: "error_log", title: "Error Log", subtitle: "Captured app errors", destination: .errorLog),
                        SettingsRefreshRowModel(id: "workout_debug", title: "Workout Debug", subtitle: "Pending workouts not checked yet", destination: .workoutDebug)
                    ]
                ),
                at: sections.count - 1
            )
        }

        return sections
    }
}

// MARK: - Settings Refresh Components

struct SettingsSectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title.uppercased())
                    .font(Theme.Typography.footnote)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .tracking(1)

                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Theme.Spacing.xs)

            content
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                        .stroke(Theme.Colors.borderLight, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
        }
    }
}

struct SettingsNavigationRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .fill(tint.opacity(0.12))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(tint)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)

                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Theme.Spacing.md)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .contentShape(Rectangle())
    }
}

struct SettingsRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Colors.borderLight)
            .frame(height: 1)
            .padding(.leading, 56)
            .padding(.vertical, Theme.Spacing.sm)
    }
}

private struct SettingsStatusPill: View {
    let icon: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(Theme.Typography.footnote)
                .lineLimit(1)
        }
        .foregroundColor(tint)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - Device Mode Row

private struct DeviceModeRow: View {
    let mode: DevicePreference
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Theme.Spacing.md) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                        .fill(mode.accentColor.opacity(0.1))
                        .frame(width: 48, height: 48)

                    Image(systemName: mode.iconName)
                        .font(.system(size: 22))
                        .foregroundColor(mode.accentColor)

                    // Phone badge for watch + phone options
                    if mode != .phoneOnly && mode != .appleWatchOnly {
                        Image(systemName: "iphone")
                            .font(.system(size: 10))
                            .foregroundColor(mode.accentColor)
                            .padding(3)
                            .background(Theme.Colors.surfaceElevated)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Theme.Colors.borderLight, lineWidth: 1)
                            )
                            .offset(x: 14, y: 14)
                    }
                }

                // Text
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(mode.title)
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(Theme.Colors.textPrimary)

                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Theme.Colors.accentBlue)
                        }
                    }

                    Text(mode.subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                Spacer()
            }
            .padding(Theme.Spacing.md)
            .background(isSelected ? Theme.Colors.surfaceElevated : Theme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .stroke(isSelected ? Theme.Colors.accentBlue : Theme.Colors.borderLight, lineWidth: 1)
            )
            .cornerRadius(Theme.CornerRadius.md)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings Toggle Row

private struct SettingsToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .fill(iconColor.opacity(0.1))
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)

                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Theme.Colors.accentBlue)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .cornerRadius(Theme.CornerRadius.md)
    }
}

// MARK: - Preview

#Preview {
    SettingsView(navigateToSyncDashboard: .constant(false))
        .environmentObject(GarminConnectManager.shared)
        .environmentObject(PairingService.shared)
        .environmentObject(WorkoutsViewModel())
        .preferredColorScheme(.dark)
}

// AMA-1639: EditProfileView and DistanceUnit live in their own file
// (`AmakaFlow/Views/EditProfileView.swift`) — extracted to keep this
// file under SwiftLint's file_length cap.
