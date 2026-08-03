//
//  WorkoutStartSheetPrefNotes.swift
//  AmakaFlow
//
//  AMA-2360 — extracted from WorkoutStartSheet to satisfy type_body_length.
//  AMA-2371 — the per-device Apple/Garmin "Edit" prefs rows this file used to
//  render were removed from the Start sheet in favor of one Settings pointer.
//  Editing still lives in the full prefs sheets (GarminWatchDisplayPrefsSheet /
//  AppleWatchDeliveryPrefsSheet, both reachable from Settings › Connected
//  wearables) — this file now only hosts that single footer pointer.
//

import SwiftUI

/// AMA-2371: single Settings pointer that replaced the per-device prefs rows.
struct WorkoutStartSettingsPointerFooter: View {
    var body: some View {
        Text("Watch display defaults live in Settings › Connected wearables.")
            .font(.system(size: 10))
            .foregroundColor(DailyDriver.foregroundDim)
            .accessibilityIdentifier("af_start_settings_pointer")
    }
}
