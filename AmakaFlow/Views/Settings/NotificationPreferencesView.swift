//
//  NotificationPreferencesView.swift
//  AmakaFlow
//
//  Push notification preferences and registration status (AMA-1133)
//

import SwiftUI
import UserNotifications

struct NotificationPreferencesView: View {
    @StateObject private var viewModel = TrainingPreferencesViewModel()
    @State private var pushEnabled = false
    @State private var pushAuthStatus: UNAuthorizationStatus = .notDetermined
    @State private var showingSystemSettings = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                // Push notification status
                pushStatusSection

                divider

                // Notification types
                notificationTypesSection

                divider

                // Save button
                saveButton
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadPreferences()
            await checkPushStatus()
        }
    }

    // MARK: - Push Status

    private var pushStatusSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Push Notifications")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: pushStatusIcon)
                    .font(.system(size: 24))
                    .foregroundColor(pushStatusColor)
                    .frame(width: 40, height: 40)
                    .background(pushStatusColor.opacity(0.15))
                    .cornerRadius(Theme.CornerRadius.md)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(pushStatusTitle)
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text(pushStatusSubtitle)
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

            if pushAuthStatus == .denied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "gear")
                        Text("Open System Settings")
                    }
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(Theme.Colors.accentBlue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.accentBlue.opacity(0.1))
                    .cornerRadius(Theme.CornerRadius.md)
                }
            } else if pushAuthStatus == .notDetermined {
                Button {
                    Task { await requestPushPermission() }
                } label: {
                    HStack {
                        Image(systemName: "bell.badge")
                        Text("Enable Push Notifications")
                    }
                    .font(Theme.Typography.captionBold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.accentBlue)
                    .cornerRadius(Theme.CornerRadius.md)
                }
            }
        }
    }

    // MARK: - Notification Types

    private var notificationTypesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Notification Types")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            Text("Choose which notifications you want to receive")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)

            notificationTypeRow(
                "Workout Reminders",
                subtitle: "Get reminded before scheduled workouts",
                icon: "bell.fill",
                iconColor: Theme.Colors.accentBlue,
                isOn: $viewModel.preferences.workoutReminders
            )

            notificationTypeRow(
                "Coach Messages",
                subtitle: "AI coach tips and check-ins",
                icon: "bubble.left.fill",
                iconColor: Color(hex: "9333EA"),
                isOn: $viewModel.preferences.coachMessages
            )

            notificationTypeRow(
                "Weekly Report",
                subtitle: "Sunday training summary",
                icon: "chart.bar.fill",
                iconColor: Theme.Colors.accentGreen,
                isOn: $viewModel.preferences.weeklyReport
            )

            notificationTypeRow(
                "Conflict Alerts",
                subtitle: "Schedule conflicts and overtraining warnings",
                icon: "exclamationmark.triangle.fill",
                iconColor: Theme.Colors.accentOrange,
                isOn: $viewModel.preferences.conflictAlerts
            )

            notificationTypeRow(
                "Recovery Reminders",
                subtitle: "Rest day and recovery suggestions",
                icon: "bed.double.fill",
                iconColor: Theme.Colors.accentBlue,
                isOn: $viewModel.preferences.recoveryReminders
            )
        }
    }

    private func notificationTypeRow(
        _ title: String,
        subtitle: String,
        icon: String,
        iconColor: Color,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(iconColor)
                .frame(width: 32, height: 32)
                .background(iconColor.opacity(0.15))
                .cornerRadius(Theme.CornerRadius.sm)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(Theme.Typography.footnote)
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .tint(Theme.Colors.accentBlue)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    // MARK: - Save Button

    private var saveButton: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Button {
                Task { await viewModel.savePreferences() }
            } label: {
                HStack {
                    if viewModel.isSaving {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Save Preferences")
                        .font(Theme.Typography.bodyBold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.Colors.accentBlue)
                .cornerRadius(Theme.CornerRadius.lg)
            }
            .disabled(viewModel.isSaving)

            if viewModel.saveSuccess {
                Text("Preferences saved")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.accentGreen)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.accentRed)
            }
        }
    }

    // MARK: - Divider

    private var divider: some View {
        Rectangle()
            .fill(Theme.Colors.borderLight)
            .frame(height: 1)
    }

    // MARK: - Helpers

    private func checkPushStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            pushAuthStatus = settings.authorizationStatus
            pushEnabled = settings.authorizationStatus == .authorized
        }
    }

    private func requestPushPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            await MainActor.run {
                pushEnabled = granted
                pushAuthStatus = granted ? .authorized : .denied
            }
            if granted {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        } catch {
            print("[NotificationPreferencesView] Push permission error: \(error)")
        }
    }

    private var pushStatusIcon: String {
        switch pushAuthStatus {
        case .authorized, .provisional: return "bell.badge.fill"
        case .denied: return "bell.slash.fill"
        case .notDetermined: return "bell.fill"
        @unknown default: return "bell.fill"
        }
    }

    private var pushStatusColor: Color {
        switch pushAuthStatus {
        case .authorized, .provisional: return Theme.Colors.accentGreen
        case .denied: return Theme.Colors.accentRed
        case .notDetermined: return Theme.Colors.accentOrange
        @unknown default: return Theme.Colors.textSecondary
        }
    }

    private var pushStatusTitle: String {
        switch pushAuthStatus {
        case .authorized, .provisional: return "Notifications Enabled"
        case .denied: return "Notifications Disabled"
        case .notDetermined: return "Not Set Up"
        @unknown default: return "Unknown"
        }
    }

    private var pushStatusSubtitle: String {
        switch pushAuthStatus {
        case .authorized, .provisional: return "You will receive push notifications"
        case .denied: return "Enable in System Settings to receive notifications"
        case .notDetermined: return "Tap below to enable push notifications"
        @unknown default: return ""
        }
    }
}

#Preview {
    NavigationStack {
        NotificationPreferencesView()
    }
    .preferredColorScheme(.dark)
}
