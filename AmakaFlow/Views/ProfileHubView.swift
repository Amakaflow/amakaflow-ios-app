//
//  ProfileHubView.swift
//  AmakaFlow
//
//  AMA-2292: Daily Driver Profile tab — identity + summary stubs + Settings.
//  Coach and History moved here from top-level tabs (see relocation note).
//

import SwiftUI

enum ProfileHubRoute: Hashable {
    case settings
    case history
    case coach
}

struct ProfileHubView: View {
    @Binding var navigateToSyncDashboard: Bool
    @Binding var path: NavigationPath

    @EnvironmentObject private var pairingService: PairingService
    @AppStorage(DefaultsKey.userDisplayName.rawValue) private var displayNameOverride: String = ""
    @StateObject private var historyViewModel = ActivityHistoryViewModel()

    private var displayName: String {
        let trimmed = displayNameOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let name = pairingService.userProfile?.name?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        return pairingService.userProfile?.email ?? "Athlete"
    }

    private var weekSummary: WeeklySummary {
        historyViewModel.weeklySummary
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    identityHeader
                    summaryGrid
                    destinationsSection
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.lg)
                .padding(.bottom, 100)
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationBarHidden(true)
            .navigationDestination(for: ProfileHubRoute.self) { route in
                switch route {
                case .settings:
                    SettingsView(navigateToSyncDashboard: $navigateToSyncDashboard)
                case .history:
                    ActivityHistoryView()
                case .coach:
                    CoachChatView()
                }
            }
            .task {
                await historyViewModel.loadCompletions()
            }
            .overlay(alignment: .top) {
                Text(" ")
                    .font(.system(size: 1))
                    .opacity(0.01)
                    .accessibilityIdentifier("profile_screen")
            }
        }
    }

    private var identityHeader: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.readyHigh.opacity(0.22))
                    .frame(width: 56, height: 56)
                Text(String(displayName.prefix(1)).uppercased())
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.textPrimary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .accessibilityIdentifier("af_profile_identity_name")
                Text("Daily Driver profile")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surfaceElevated)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous))
        .accessibilityIdentifier("af_profile_identity")
    }

    private var summaryGrid: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                summaryStub(
                    title: "Streak",
                    value: "—",
                    subtitle: "Coming soon",
                    identifier: "af_profile_summary_streak"
                ) {
                    path.append(ProfileHubRoute.history)
                }
                summaryStub(
                    title: "This week",
                    value: weekSummary.workoutCount > 0 ? "\(weekSummary.workoutCount)" : "—",
                    subtitle: weekSummary.workoutCount > 0 ? weekSummary.formattedDuration : "No sessions",
                    identifier: "af_profile_summary_week"
                ) {
                    path.append(ProfileHubRoute.history)
                }
            }
            HStack(spacing: Theme.Spacing.sm) {
                summaryStub(
                    title: "Calendar",
                    value: "Open",
                    subtitle: "Training calendar",
                    identifier: "af_profile_summary_calendar"
                ) {
                    path.append(ProfileHubRoute.settings)
                }
                summaryStub(
                    title: "Totals",
                    value: weekSummary.totalCalories > 0 ? weekSummary.formattedCalories : "—",
                    subtitle: "Week kcal",
                    identifier: "af_profile_summary_totals"
                ) {
                    path.append(ProfileHubRoute.history)
                }
            }
        }
        .accessibilityIdentifier("af_profile_summaries")
    }

    private func summaryStub(
        title: String,
        value: String,
        subtitle: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                AFLabel(text: title.uppercased())
                Text(value)
                    .font(.system(size: 22, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.surfaceElevated)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous)
                    .stroke(Theme.Colors.borderLight, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private var destinationsSection: some View {
        VStack(spacing: 0) {
            destinationRow(
                title: "Coach",
                subtitle: "Chat, fatigue, readiness — was top-level Coach tab",
                icon: "bubble.left.and.bubble.right.fill",
                identifier: "coach_tab"
            ) {
                path.append(ProfileHubRoute.coach)
            }

            SettingsRowDivider()

            destinationRow(
                title: "Activity History",
                subtitle: "Completed sessions — was top-level History tab",
                icon: "clock.arrow.circlepath",
                identifier: "history_tab"
            ) {
                path.append(ProfileHubRoute.history)
            }

            SettingsRowDivider()

            destinationRow(
                title: "Settings",
                subtitle: "Connections, coaching prefs, account",
                icon: "gearshape.fill",
                identifier: "af_profile_settings_entry"
            ) {
                path.append(ProfileHubRoute.settings)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Colors.surfaceElevated)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous))
        .accessibilityIdentifier("af_profile_destinations")
    }

    private func destinationRow(
        title: String,
        subtitle: String,
        icon: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Theme.Colors.readyHigh)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: Theme.Spacing.sm)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

#if DEBUG
#Preview("Profile hub") {
    ProfileHubView(
        navigateToSyncDashboard: .constant(false),
        path: .constant(NavigationPath())
    )
    .environmentObject(PairingService.shared)
}
#endif
