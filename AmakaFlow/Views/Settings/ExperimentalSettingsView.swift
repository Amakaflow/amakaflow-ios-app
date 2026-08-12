//
//  ExperimentalSettingsView.swift
//  AmakaFlow
//
//  AMA-2420 — Experimental feature toggles (Strength auto-capture).
//

import SwiftUI

struct ExperimentalSettingsView: View {
    @State private var strengthAutoCapture = StrengthAutoCaptureSettings.isEnabled

    var body: some View {
        List {
            Section {
                Toggle("Strength auto-capture", isOn: $strengthAutoCapture)
                    .tint(Theme.Colors.accentBlue)
                    .accessibilityIdentifier("settings_toggle_strength_auto_capture")
                    .onChange(of: strengthAutoCapture) { _, newValue in
                        StrengthAutoCaptureSettings.isEnabled = newValue
                        WatchConnectivityManager.shared.syncExperimentalFlagsToWatch()
                    }
            } header: {
                Text("Watch strength")
            } footer: {
                Text(
                    "Adds Start strength on Watch Today — no calendar plan required. "
                        + "Starts an AmakaFlow Watch session (Traditional Strength Training), "
                        + "auto-captures what it can, then fill and correct on Today with Actuals. "
                        + "Does not remote-start Apple Fitness. Off by default."
                )
            }
        }
        .navigationTitle("Experimental")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            strengthAutoCapture = StrengthAutoCaptureSettings.isEnabled
        }
    }
}

#Preview {
    NavigationStack {
        ExperimentalSettingsView()
    }
}
