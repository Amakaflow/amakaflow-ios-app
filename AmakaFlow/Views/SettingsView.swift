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

struct SettingsView: View {
    @AppStorage("devicePreference") private var deviceMode: DevicePreference = .appleWatchPhone
    @State private var voiceCuesEnabled = true
    @State private var audioBehavior: AudioBehavior = .duck
    @State private var countdownBeepsEnabled = true
    @State private var hapticFeedbackEnabled = true
    @State private var showingSignOutAlert = false
    @EnvironmentObject private var garminConnectivity: GarminConnectManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    // Workout Device Section
                    deviceSection

                    divider

                    // Audio Cues Section
                    audioCuesSection

                    divider

                    // Integrations Section
                    integrationsSection

                    divider

                    // Account Section
                    accountSection

                    divider

                    // Legal Section
                    legalSection
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.lg)
                .padding(.bottom, 100)
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .alert("Sign Out", isPresented: $showingSignOutAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) {
                    print("User signed out")
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
        }
    }

    // MARK: - Divider

    private var divider: some View {
        Rectangle()
            .fill(Theme.Colors.borderLight)
            .frame(height: 1)
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

            // Info text
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Image(systemName: "info.circle")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.Colors.textTertiary)

                Text("Opens Garmin Connect Mobile to select your watch. Make sure Garmin Connect is installed.")
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

    // MARK: - Audio Cues Section

    private var audioCuesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("AUDIO CUES")
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textSecondary)
                .tracking(1)
                .padding(.horizontal, Theme.Spacing.xs)

            VStack(spacing: Theme.Spacing.sm) {
                // Voice Cues Toggle
                VStack(spacing: 0) {
                    HStack(spacing: Theme.Spacing.md) {
                        ZStack {
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                                .fill(Theme.Colors.accentBlue.opacity(0.1))
                                .frame(width: 40, height: 40)

                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 18))
                                .foregroundColor(Theme.Colors.accentBlue)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Voice Cues")
                                .font(Theme.Typography.bodyBold)
                                .foregroundColor(Theme.Colors.textPrimary)

                            Text("Announce exercise names and transitions")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }

                        Spacer()

                        Toggle("", isOn: $voiceCuesEnabled)
                            .labelsHidden()
                            .tint(Theme.Colors.accentBlue)
                    }
                    .padding(Theme.Spacing.md)

                    // Audio behavior segmented control
                    if voiceCuesEnabled {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Rectangle()
                                .fill(Theme.Colors.borderLight)
                                .frame(height: 1)

                            Text("When music is playing:")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                                .padding(.horizontal, Theme.Spacing.md)

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
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.bottom, Theme.Spacing.md)
                        }
                    }
                }
                .background(Theme.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                        .stroke(Theme.Colors.borderLight, lineWidth: 1)
                )
                .cornerRadius(Theme.CornerRadius.md)

                // Countdown Beeps
                SettingsToggleRow(
                    icon: "timer",
                    iconColor: Theme.Colors.accentBlue,
                    title: "Countdown Beeps",
                    subtitle: "Audio beeps for last 5 seconds of timed intervals",
                    isOn: $countdownBeepsEnabled
                )

                // Haptic Feedback
                SettingsToggleRow(
                    icon: "iphone.radiowaves.left.and.right",
                    iconColor: Theme.Colors.accentBlue,
                    title: "Haptic Feedback",
                    subtitle: "Vibrate on exercise transitions (watch & phone)",
                    isOn: $hapticFeedbackEnabled
                )

                // Info card
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.Colors.textSecondary)

                    Text("Audio cues work with any music app. Your music controls remain accessible via headphones, Control Center, or lock screen.")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
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
    }

    // MARK: - Integrations Section

    private var integrationsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("INTEGRATIONS")
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textSecondary)
                .tracking(1)
                .padding(.horizontal, Theme.Spacing.xs)

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

            Button {
                showingSignOutAlert = true
            } label: {
                HStack(spacing: Theme.Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                            .fill(Theme.Colors.accentOrange.opacity(0.1))
                            .frame(width: 48, height: 48)

                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 22))
                            .foregroundColor(Theme.Colors.accentOrange)
                    }

                    Text("Sign Out")
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
    SettingsView()
        .environmentObject(GarminConnectManager.shared)
        .preferredColorScheme(.dark)
}
