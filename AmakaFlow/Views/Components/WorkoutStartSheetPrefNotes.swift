//
//  WorkoutStartSheetPrefNotes.swift
//  AmakaFlow
//
//  AMA-2360 — extracted from WorkoutStartSheet to satisfy type_body_length.
//

import SwiftUI

/// AMA-2360: delivery prefs this Apple Start will send to mapper.
struct WorkoutStartApplePrefsNote: View {
    let summary: String
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(summary)
                    .font(.system(size: 10.5))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Text("Edit")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(DailyDriver.lime)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Apple Watch delivery settings")
        .accessibilityIdentifier("af_start_apple_prefs_note")
    }
}

/// AMA-2317: the watch prefs this push will apply, before the user taps.
struct WorkoutStartGarminPrefsNote: View {
    let displayPrefs: GarminWatchDisplayPrefs
    let hasConfiguredDisplayPrefs: Bool
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(
                        GarminLifecycleCopy.startSheetPrefsNote(
                            prefs: displayPrefs,
                            hasConfigured: hasConfiguredDisplayPrefs
                        )
                    )
                    .font(.system(size: 10.5))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .multilineTextAlignment(.leading)
                    .monospacedDigit()

                    Spacer(minLength: 0)

                    Text(GarminLifecycleCopy.startSheetPrefsAction)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(DailyDriver.lime)
                }

                if let hint = GarminLifecycleCopy.startSheetPrefsHint(
                    prefs: displayPrefs,
                    hasConfigured: hasConfiguredDisplayPrefs
                ) {
                    Text(hint)
                        .font(.system(size: 10))
                        .foregroundColor(DailyDriver.amber)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Garmin watch display settings")
        .accessibilityIdentifier("af_start_garmin_prefs_note")
    }
}
