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
                // Planner constraints (AMA-1133)
                plannerSection

                divider

                // Goal race (AMA-1133)
                goalRaceSection

                divider

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

    // MARK: - Planner Section (AMA-1133)

    private var plannerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Training Plan")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            // Weekly volume slider
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Text("Weekly Volume")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Spacer()
                    Text("\(viewModel.preferences.weeklyVolume) km")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.accentBlue)
                }

                Slider(
                    value: Binding(
                        get: { Double(viewModel.preferences.weeklyVolume) },
                        set: { viewModel.preferences.weeklyVolume = Int($0) }
                    ),
                    in: 10...150,
                    step: 5
                )
                .tint(Theme.Colors.accentBlue)

                Text("Target weekly running volume in kilometers")
                    .font(Theme.Typography.footnote)
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            // Hard day cap
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Text("Hard Day Cap")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Spacer()
                    Picker("", selection: $viewModel.preferences.hardDayCap) {
                        ForEach(1...5, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.Colors.accentBlue)
                }
                Text("Maximum hard sessions per week")
                    .font(Theme.Typography.footnote)
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            // Run days per week
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Text("Run Days Per Week")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Spacer()
                    Picker("", selection: $viewModel.preferences.runDaysPerWeek) {
                        ForEach(2...7, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.Colors.accentBlue)
                }
            }

            // Preferred long run day
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Text("Long Run Day")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { viewModel.preferences.preferredLongRunDay ?? 0 },
                        set: { viewModel.preferences.preferredLongRunDay = $0 == 0 ? nil : $0 }
                    )) {
                        Text("Any").tag(0)
                        Text("Mon").tag(2)
                        Text("Tue").tag(3)
                        Text("Wed").tag(4)
                        Text("Thu").tag(5)
                        Text("Fri").tag(6)
                        Text("Sat").tag(7)
                        Text("Sun").tag(1)
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.Colors.accentBlue)
                }
            }
        }
    }

    // MARK: - Goal Race Section (AMA-1133)

    private var goalRaceSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Goal Race")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Race Distance")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)

                Picker("", selection: Binding(
                    get: { viewModel.preferences.goalRace ?? "none" },
                    set: { viewModel.preferences.goalRace = $0 == "none" ? nil : $0 }
                )) {
                    Text("None").tag("none")
                    Text("5K").tag("5k")
                    Text("10K").tag("10k")
                    Text("Half Marathon").tag("half_marathon")
                    Text("Marathon").tag("marathon")
                    Text("Ultra").tag("ultra")
                }
                .pickerStyle(.segmented)
            }

            if viewModel.preferences.goalRace != nil {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Race Date")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)

                    DatePicker(
                        "",
                        selection: Binding(
                            get: {
                                if let dateStr = viewModel.preferences.goalRaceDate {
                                    let formatter = ISO8601DateFormatter()
                                    formatter.formatOptions = [.withFullDate]
                                    return formatter.date(from: dateStr) ?? Date()
                                }
                                return Date()
                            },
                            set: {
                                let formatter = ISO8601DateFormatter()
                                formatter.formatOptions = [.withFullDate]
                                viewModel.preferences.goalRaceDate = formatter.string(from: $0)
                            }
                        ),
                        in: Date()...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .tint(Theme.Colors.accentBlue)
                }
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
