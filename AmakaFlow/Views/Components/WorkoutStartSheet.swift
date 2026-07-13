//
//  WorkoutStartSheet.swift
//  AmakaFlow
//
//  AMA-2291: Choose gym + device at Start (Garmin primary when paired).
//

import SwiftUI

struct WorkoutStartSheet: View {
    let workout: Workout
    let garminPaired: Bool
    let appleWatchReachable: Bool
    let onConfirm: (WorkoutStartGym, WorkoutStartDevice) -> Void
    let onClose: () -> Void

    @State private var selectedGym: WorkoutStartGym = .unset
    @State private var selectedDevice: WorkoutStartDevice

    init(
        workout: Workout,
        garminPaired: Bool,
        appleWatchReachable: Bool,
        initialGym: WorkoutStartGym = .unset,
        onConfirm: @escaping (WorkoutStartGym, WorkoutStartDevice) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.workout = workout
        self.garminPaired = garminPaired
        self.appleWatchReachable = appleWatchReachable
        self.onConfirm = onConfirm
        self.onClose = onClose
        _selectedGym = State(initialValue: initialGym)
        _selectedDevice = State(initialValue: WorkoutStartDefaults.preferredDevice(garminPaired: garminPaired))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    deviceSection
                    gymSection
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.lg)
            }
            confirmFooter
        }
        .background(Theme.Colors.surface)
        .accessibilityIdentifier("af_start_sheet")
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Start")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(workout.name)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Theme.Colors.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
            }
            .accessibilityLabel("Close start sheet")
            .accessibilityIdentifier("af_start_sheet_close")
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.lg)
        .overlay(
            Rectangle()
                .fill(Theme.Colors.borderLight)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private var gymSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Gym")
                .font(Theme.Typography.captionBold)
                .foregroundColor(Theme.Colors.textSecondary)

            ForEach(WorkoutStartGym.allCases) { gym in
                selectionRow(
                    title: gym.title,
                    subtitle: gym.subtitle,
                    selected: selectedGym == gym,
                    badge: gym == .unset ? "Continue anyway" : nil,
                    identifier: gym.accessibilityIdentifier
                ) {
                    selectedGym = gym
                }
            }
        }
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Device")
                .font(Theme.Typography.captionBold)
                .foregroundColor(Theme.Colors.textSecondary)

            ForEach(WorkoutStartDevice.allCases) { device in
                let isDefault = device == WorkoutStartDefaults.preferredDevice(garminPaired: garminPaired)
                selectionRow(
                    title: device.title,
                    subtitle: deviceSubtitle(device),
                    selected: selectedDevice == device,
                    badge: badge(for: device, isDefault: isDefault),
                    identifier: device.accessibilityIdentifier,
                    disabled: false
                ) {
                    selectedDevice = device
                }
            }
        }
    }

    private func deviceSubtitle(_ device: WorkoutStartDevice) -> String {
        switch device {
        case .garmin:
            return garminPaired ? "Paired · primary delivery" : "Not paired — still selectable for later push"
        case .apple:
            return WorkoutStartDefaults.appleAvailabilityLabel(watchReachable: appleWatchReachable)
        case .phone:
            return "Phone follow-along"
        }
    }

    private func badge(for device: WorkoutStartDevice, isDefault: Bool) -> String? {
        if isDefault { return "Default" }
        if device == .apple { return "Try" }
        if device == .garmin && garminPaired { return "Paired" }
        return nil
    }

    private var confirmFooter: some View {
        Button {
            onConfirm(selectedGym, selectedDevice)
        } label: {
            Text("Start on \(selectedDevice.title)")
                .font(Theme.Typography.bodyBold)
                .foregroundColor(Theme.Colors.primaryForeground)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Theme.Colors.readyHigh)
                .cornerRadius(Theme.CornerRadius.md)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .accessibilityIdentifier("af_start_sheet_confirm")
        .overlay(
            Rectangle()
                .fill(Theme.Colors.borderLight)
                .frame(height: 1),
            alignment: .top
        )
    }

    private func selectionRow(
        title: String,
        subtitle: String,
        selected: Bool,
        badge: String?,
        identifier: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(selected ? Theme.Colors.readyHigh : Theme.Colors.textTertiary)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(title)
                            .font(Theme.Typography.bodyBold)
                            .foregroundColor(Theme.Colors.textPrimary)
                        if let badge {
                            Text(badge)
                                .font(Theme.Typography.footnote)
                                .foregroundColor(Theme.Colors.accentBlue)
                                .padding(.horizontal, Theme.Spacing.sm)
                                .padding(.vertical, 2)
                                .background(Theme.Colors.accentBlue.opacity(0.1))
                                .cornerRadius(Theme.CornerRadius.sm)
                        }
                    }
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surfaceElevated)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .stroke(selected ? Theme.Colors.readyHigh : Theme.Colors.borderLight, lineWidth: selected ? 2 : 1)
            )
            .cornerRadius(Theme.CornerRadius.md)
            .opacity(disabled ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#if DEBUG
#Preview {
    WorkoutStartSheet(
        workout: Workout(
            name: "IG Push Day",
            sport: .strength,
            duration: 2400,
            intervals: [],
            source: .instagram,
            sourceUrl: "https://instagram.com/reel/abc"
        ),
        garminPaired: true,
        appleWatchReachable: false,
        onConfirm: { _, _ in },
        onClose: {}
    )
    .presentationDetents([.large])
}
#endif
