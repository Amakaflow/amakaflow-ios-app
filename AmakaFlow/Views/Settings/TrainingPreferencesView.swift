//
//  TrainingPreferencesView.swift
//  AmakaFlow
//
//  Training and notification preferences settings view (AMA-1147)
//

import SwiftUI

struct TrainingPreferencesView: View {
    @StateObject private var viewModel = TrainingPreferencesViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                // Notification toggles
                notificationSection

                divider

                // Reminder timing
                reminderSection

                divider

                // Save button
                saveButton
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle("Training Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadPreferences()
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Colors.background.opacity(0.8))
            }
        }
    }

    // MARK: - Notification Section

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Notifications")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            toggleRow(
                "Workout Reminders",
                icon: "bell.fill",
                isOn: $viewModel.preferences.workoutReminders
            )

            toggleRow(
                "Coach Messages",
                icon: "bubble.left.fill",
                isOn: $viewModel.preferences.coachMessages
            )

            toggleRow(
                "Weekly Report",
                icon: "chart.bar.fill",
                isOn: $viewModel.preferences.weeklyReport
            )

            toggleRow(
                "Conflict Alerts",
                icon: "exclamationmark.triangle.fill",
                isOn: $viewModel.preferences.conflictAlerts
            )

            toggleRow(
                "Recovery Reminders",
                icon: "bed.double.fill",
                isOn: $viewModel.preferences.recoveryReminders
            )
        }
    }

    private func toggleRow(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(Theme.Colors.accentBlue)
                .frame(width: 28)

            Text(title)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textPrimary)

            Spacer()

            Toggle("", isOn: isOn)
                .tint(Theme.Colors.accentBlue)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    // MARK: - Reminder Section

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Reminder Timing")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            HStack {
                Text("Minutes before workout")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                Picker("", selection: $viewModel.preferences.reminderMinutesBefore) {
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                    Text("60 min").tag(60)
                    Text("120 min").tag(120)
                }
                .pickerStyle(.menu)
                .tint(Theme.Colors.accentBlue)
            }
        }
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
}

#Preview {
    NavigationStack {
        TrainingPreferencesView()
    }
    .preferredColorScheme(.dark)
}
