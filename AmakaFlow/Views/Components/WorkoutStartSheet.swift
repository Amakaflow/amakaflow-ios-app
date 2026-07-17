//
//  WorkoutStartSheet.swift
//  AmakaFlow
//
//  AMA-2291: Daily Driver Start session sheet — gym pills + device rows (StartSheet).
//

import SwiftUI

struct WorkoutStartSheet: View {
    let workout: Workout
    let garminPaired: Bool
    let appleWatchReachable: Bool
    let onConfirm: (WorkoutStartGym, WorkoutStartDevice) -> Void
    let onClose: () -> Void

    @State private var selectedGym: WorkoutStartGym = .home

    init(
        workout: Workout,
        garminPaired: Bool,
        appleWatchReachable: Bool,
        initialGym: WorkoutStartGym = .home,
        onConfirm: @escaping (WorkoutStartGym, WorkoutStartDevice) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.workout = workout
        self.garminPaired = garminPaired
        self.appleWatchReachable = appleWatchReachable
        self.onConfirm = onConfirm
        self.onClose = onClose
        _selectedGym = State(initialValue: initialGym == .unset ? .home : initialGym)
    }

    private var defaultDevice: WorkoutStartDevice {
        WorkoutStartDefaults.preferredDevice(garminPaired: garminPaired)
    }

    private var sportTag: String {
        switch workout.sport {
        case .strength: return "STRENGTH"
        case .running: return "RUN"
        case .cycling: return "RIDE"
        case .cardio: return "HIIT"
        case .mobility: return "MOBILITY"
        case .swimming: return "SWIM"
        case .other: return "WORKOUT"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(DailyDriver.borderStrong)
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            HStack(alignment: .top) {
                Text("Start session")
                    .ddDisplayText(17, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close start sheet")
                .accessibilityIdentifier("af_start_sheet_close")
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    gymSection
                        .padding(.top, 8)

                    deviceSection
                        .padding(.top, 16)

                    Text("Defaults come from Settings › Connected wearables.")
                        .font(.system(size: 10))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .padding(.top, 12)

                    unsetGymLink
                        .padding(.top, 10)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
        }
        .background(DailyDriver.screenBackground)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("af_start_sheet")
    }

    private var gymSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHERE ARE YOU?")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundMuted)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(WorkoutStartGym.startSheetPills) { gym in
                        Button {
                            selectedGym = gym
                        } label: {
                            Text(gym.pillLabel)
                                .ddDisplayText(12.5, weight: .semibold)
                                .foregroundColor(selectedGym == gym ? DailyDriver.ink : DailyDriver.foregroundMuted)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 9)
                                .background(selectedGym == gym ? DailyDriver.lime : DailyDriver.card)
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(selectedGym == gym ? Color.clear : DailyDriver.border, lineWidth: 1)
                                )
                                .clipShape(Capsule(style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(gym.accessibilityIdentifier)
                        .accessibilityAddTraits(selectedGym == gym ? .isSelected : [])
                    }
                }
            }

            Text(gymSwapNote)
                .font(.system(size: 10.5))
                .foregroundColor(selectedGym == .home ? DailyDriver.amber : DailyDriver.foregroundDim)
                .padding(.top, 2)
        }
    }

    private var gymSwapNote: String {
        switch selectedGym {
        case .home:
            return "2 swaps applied — no barbell, no sled here"
        case .commercial, .hotel:
            return "All exercises fit — no swaps needed"
        case .unset:
            return "No gym profile — swaps skipped"
        }
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ON WHAT?")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(DailyDriver.foregroundMuted)

            deviceRow(
                device: .phone,
                icon: "iphone",
                iconBackground: DailyDriver.card2,
                iconForeground: .white,
                title: "This phone",
                subtitle: "Follow-along player · always works",
                tag: nil
            )

            deviceRow(
                device: .apple,
                icon: "applewatch",
                iconBackground: defaultDevice == .apple ? DailyDriver.lime : DailyDriver.card2,
                iconForeground: defaultDevice == .apple ? DailyDriver.ink : .white,
                title: "Apple Watch",
                subtitle: appleWatchReachable ? "Reachable now" : "Try — Watch optional",
                tag: defaultDevice == .apple ? "DEFAULT · \(sportTag)" : "TRY"
            )

            deviceRow(
                device: .garmin,
                icon: "applewatch.side.right",
                iconBackground: DailyDriver.blue,
                iconForeground: .white,
                title: "Garmin",
                subtitle: garminPaired ? "Push via FIT" : "Pair in Settings to push",
                tag: defaultDevice == .garmin ? "DEFAULT · \(sportTag)" : nil
            )
        }
    }

    private var unsetGymLink: some View {
        Button {
            selectedGym = .unset
            onConfirm(.unset, defaultDevice)
        } label: {
            Text("Continue without a gym")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DailyDriver.foregroundDim)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("af_start_gym_unset")
    }

    private func deviceRow(
        device: WorkoutStartDevice,
        icon: String,
        iconBackground: Color,
        iconForeground: Color,
        title: String,
        subtitle: String,
        tag: String?
    ) -> some View {
        let isGarminUnavailable = device == .garmin && !garminPaired
        return Button {
            if isGarminUnavailable {
                return
            }
            onConfirm(selectedGym, device)
        } label: {
            HStack(spacing: 13) {
                ZStack {
                    Circle()
                        .fill(iconBackground)
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(iconForeground)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .ddDisplayText(14, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundColor(DailyDriver.foregroundMuted)
                }

                Spacer(minLength: 0)

                if let tag {
                    Text(tag)
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundColor(DailyDriver.lime)
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .background(DailyDriver.card)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(DailyDriver.border, lineWidth: 1)
            )
            .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isGarminUnavailable)
        .opacity(isGarminUnavailable ? 0.45 : 1)
        .accessibilityIdentifier(device.accessibilityIdentifier)
    }
}

#if DEBUG
#Preview {
    WorkoutStartSheet(
        workout: Workout(
            name: "Lower body — posterior",
            sport: .strength,
            duration: 3120,
            intervals: [],
            source: .coach,
            sourceUrl: "Coach Mike"
        ),
        garminPaired: true,
        appleWatchReachable: false,
        onConfirm: { _, _ in },
        onClose: {}
    )
    .presentationDetents([.large])
}
#endif
