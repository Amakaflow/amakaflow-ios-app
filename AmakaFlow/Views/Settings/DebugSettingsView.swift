//
//  DebugSettingsView.swift
//  AmakaFlow
//
//  Debug settings UI for workout simulation mode.
//  Accessed via hidden 7-tap gesture on settings icon.
//  Part of AMA-271: Workout Simulation Mode
//

import SwiftUI
import ClerkKit
#if canImport(UIKit)
import UIKit
#endif

struct DebugSettingsView: View {
    @StateObject private var settings = SimulationSettings.shared
    @Environment(\.dismiss) private var dismiss
    @State private var lastJWT: String?
    @State private var jwtError: String?

    var body: some View {
        NavigationView {
            Form {
                // MARK: - Simulation Mode Section
                Section {
                    Toggle("Enable Simulation Mode", isOn: $settings.isEnabled)
                        .tint(Theme.Colors.accentBlue)

                    if settings.isEnabled {
                        // Speed Picker
                        Picker("Speed", selection: $settings.speed) {
                            ForEach(SimulationSettings.speedOptions, id: \.value) { option in
                                Text(option.label).tag(option.value)
                            }
                        }

                        // Behavior Profile Picker
                        Picker("User Behavior", selection: $settings.profileName) {
                            ForEach(SimulationSettings.profileOptions, id: \.value) { option in
                                Text(option.label).tag(option.value)
                            }
                        }

                        // Health Data Toggle
                        Toggle("Generate Fake Health Data", isOn: $settings.generateHealthData)
                            .tint(Theme.Colors.accentBlue)
                    }
                } header: {
                    Text("Workout Simulation")
                } footer: {
                    Text("Simulation mode runs workouts at accelerated speed with simulated user behavior. Use for testing without physically exercising.")
                }

                // MARK: - HR Profile Section (when health data enabled)
                if settings.isEnabled && settings.generateHealthData {
                    Section {
                        Stepper(
                            "Resting HR: \(settings.restingHR) bpm",
                            value: $settings.restingHR,
                            in: 50...90
                        )

                        Stepper(
                            "Max HR: \(settings.maxHR) bpm",
                            value: $settings.maxHR,
                            in: 150...200
                        )
                    } header: {
                        Text("Heart Rate Profile")
                    } footer: {
                        Text("Customize the simulated heart rate range. Athletic users typically have lower resting HR.")
                    }
                }

                // MARK: - Weight Simulation Section (AMA-308)
                if settings.isEnabled {
                    Section {
                        Toggle("Auto-Select Weights", isOn: $settings.simulateWeight)
                            .tint(Theme.Colors.accentBlue)

                        if settings.simulateWeight {
                            Picker("Strength Level", selection: $settings.weightProfileName) {
                                ForEach(SimulationSettings.weightProfileOptions, id: \.value) { option in
                                    Text("\(option.label) (\(option.description))").tag(option.value)
                                }
                            }
                        }
                    } header: {
                        Text("Weight Simulation")
                    } footer: {
                        Text("Automatically select realistic weights for strength exercises based on your strength level.")
                    }
                }

                // MARK: - Behavior Details (info section)
                if settings.isEnabled {
                    Section {
                        BehaviorDetailRow(
                            title: "Profile",
                            value: settings.profileName.capitalized
                        )

                        BehaviorDetailRow(
                            title: "Rest Time",
                            value: formatRestMultiplier(settings.behaviorProfile.restTimeMultiplier)
                        )

                        BehaviorDetailRow(
                            title: "Reaction Time",
                            value: formatReactionTime(settings.behaviorProfile.reactionTime)
                        )

                        BehaviorDetailRow(
                            title: "Pause Probability",
                            value: "\(Int(settings.behaviorProfile.pauseProbability * 100))%"
                        )

                        BehaviorDetailRow(
                            title: "Skip Probability",
                            value: "\(Int(settings.behaviorProfile.skipProbability * 100))%"
                        )
                    } header: {
                        Text("Behavior Details")
                    }
                }

                #if DEBUG
                // MARK: - Clerk JWT (AMA-1650 diagnostic — DEBUG builds only)
                Section {
                    Button {
                        Task { await captureJWT() }
                    } label: {
                        Label("Print & copy Clerk JWT", systemImage: "key.fill")
                    }

                    if let token = lastJWT {
                        Text(token)
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(4)
                            .truncationMode(.middle)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .textSelection(.enabled)
                    }

                    if let err = jwtError {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                } header: {
                    Text("Clerk JWT (AMA-1650)")
                } footer: {
                    Text("Prints the active Clerk session JWT to the Xcode console and copies it to the clipboard. Used to inspect Clerk Billing claim shape via /debug/jwt-claims on staging. DEBUG builds only.")
                }
                #endif

                // MARK: - Access Info
                Section {
                    HStack {
                        Image(systemName: "hand.tap")
                            .foregroundColor(Theme.Colors.textTertiary)
                        Text("Access this menu by tapping the gear icon 7 times")
                            .font(.caption)
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                }
            }
            .navigationTitle("Debug Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Formatting Helpers

    private func formatRestMultiplier(_ range: ClosedRange<Double>) -> String {
        let lower = Int(range.lowerBound * 100)
        let upper = Int(range.upperBound * 100)
        return "\(lower)% - \(upper)%"
    }

    private func formatReactionTime(_ range: ClosedRange<TimeInterval>) -> String {
        return String(format: "%.1f - %.1f sec", range.lowerBound, range.upperBound)
    }

    #if DEBUG
    @MainActor
    private func captureJWT() async {
        jwtError = nil
        guard let session = Clerk.shared.session else {
            jwtError = "No active Clerk session — sign in first."
            lastJWT = nil
            return
        }
        do {
            guard let jwt = try await session.getToken(.init(skipCache: true)) else {
                jwtError = "Clerk returned nil token."
                lastJWT = nil
                return
            }
            lastJWT = jwt
            print("CLERK_JWT: \(jwt)")
            #if canImport(UIKit)
            UIPasteboard.general.string = jwt
            #endif
        } catch {
            jwtError = "Failed to fetch token: \(error.localizedDescription)"
            lastJWT = nil
        }
    }
    #endif
}

// MARK: - Behavior Detail Row

private struct BehaviorDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .foregroundColor(Theme.Colors.textPrimary)
        }
    }
}

// MARK: - Preview

#Preview {
    DebugSettingsView()
        .preferredColorScheme(.dark)
}
