//
//  FatigueSettingsView.swift
//  AmakaFlow
//
//  Fatigue and readiness tracking preferences (AMA-1412)
//

import SwiftUI

struct FatigueSettingsView: View {
    @AppStorage("fatigue_tracking_enabled") private var isEnabled = true
    @AppStorage("fatigue_readiness_threshold") private var readinessThreshold = 40.0
    @AppStorage("fatigue_show_in_calendar") private var showInCalendar = true
    @AppStorage("fatigue_recovery_reminder") private var recoveryReminder = false

    var body: some View {
        List {
            Section {
                Toggle("Enable fatigue tracking", isOn: $isEnabled)
            } header: {
                Text("General")
            } footer: {
                Text("Track your daily readiness and fatigue levels based on training load.")
            }

            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack {
                        Text("Warning threshold")
                        Spacer()
                        Text("\(Int(readinessThreshold))")
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    Slider(value: $readinessThreshold, in: 20...80, step: 5)
                        .tint(Theme.Colors.accentBlue)
                }
            } header: {
                Text("Readiness")
            } footer: {
                Text("Show a warning when your readiness score drops below this level.")
            }

            Section {
                Toggle("Show readiness in calendar", isOn: $showInCalendar)
                Toggle("Recovery reminders", isOn: $recoveryReminder)
            } header: {
                Text("Display")
            } footer: {
                Text("Recovery reminders notify you when consecutive red days suggest you need rest.")
            }
        }
        .navigationTitle("Fatigue Tracking")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        FatigueSettingsView()
    }
    .preferredColorScheme(.dark)
}
