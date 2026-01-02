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
    @State private var showingGarminDebugAlert = false
    @State private var garminDebugMessage = ""
    @State private var showingManualUUIDSheet = false
    @State private var manualUUID = ""
    @State private var manualDeviceName = ""
    @State private var showingDebugLog = false
    @State private var showingDisconnectAlert = false
    @State private var showingWorkoutDebugSheet = false
    @EnvironmentObject private var garminConnectivity: GarminConnectManager
    @EnvironmentObject private var pairingService: PairingService
    @EnvironmentObject private var workoutsViewModel: WorkoutsViewModel

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
            .alert("Garmin Debug", isPresented: $showingGarminDebugAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(garminDebugMessage)
            }
            .sheet(isPresented: $showingManualUUIDSheet) {
                manualUUIDSheet
            }
            .sheet(isPresented: $showingDebugLog) {
                debugLogSheet
            }
            .sheet(isPresented: $showingWorkoutDebugSheet) {
                workoutDebugSheet
            }
        }
    }

    // MARK: - Workout Debug Sheet

    private var workoutDebugSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Action buttons
                HStack(spacing: Theme.Spacing.sm) {
                    Button {
                        Task {
                            await workoutsViewModel.checkPendingWorkouts()
                        }
                    } label: {
                        VStack {
                            Image(systemName: "arrow.down.circle")
                            Text("Fetch")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Colors.accentBlue.opacity(0.2))
                        .cornerRadius(Theme.CornerRadius.sm)
                    }

                    Button {
                        workoutsViewModel.addSampleWorkout()
                    } label: {
                        VStack {
                            Image(systemName: "plus.circle")
                            Text("Sample")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Colors.accentGreen.opacity(0.2))
                        .cornerRadius(Theme.CornerRadius.sm)
                    }

                    Button {
                        UIPasteboard.general.string = generateWorkoutDebugText()
                    } label: {
                        VStack {
                            Image(systemName: "doc.on.doc")
                            Text("Copy")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Color.purple.opacity(0.2))
                        .cornerRadius(Theme.CornerRadius.sm)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .foregroundColor(Theme.Colors.textPrimary)

                Divider()

                // Status
                VStack(alignment: .leading, spacing: 4) {
                    Text("Status: \(workoutsViewModel.pendingWorkoutsStatus.isEmpty ? "Not checked" : workoutsViewModel.pendingWorkoutsStatus)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .padding(Theme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colors.surfaceElevated)

                Divider()

                // Workout details
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        // Show all incoming workouts
                        if workoutsViewModel.incomingWorkouts.isEmpty {
                            Text("No incoming workouts loaded.\nTap 'Fetch' to check for pending workouts.")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textTertiary)
                                .padding()
                        } else {
                            ForEach(workoutsViewModel.incomingWorkouts) { workout in
                                workoutDebugCard(workout)
                            }
                        }
                    }
                    .padding(Theme.Spacing.md)
                }
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Workout Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showingWorkoutDebugSheet = false
                    }
                }
            }
        }
    }

    private func workoutDebugCard(_ workout: Workout) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Header
            HStack {
                Text(workout.name)
                    .font(Theme.Typography.bodyBold)
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                Text(workout.sport.rawValue)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.Colors.accentBlue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.Colors.accentBlue.opacity(0.2))
                    .cornerRadius(4)
            }

            // Workout ID and duration
            Text("ID: \(workout.id)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Theme.Colors.textTertiary)
            Text("Duration: \(workout.duration)s (\(workout.formattedDuration))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Theme.Colors.textSecondary)

            Divider()

            // Raw Intervals
            Text("RAW INTERVALS (\(workout.intervals.count))")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.Colors.accentOrange)

            ForEach(Array(workout.intervals.enumerated()), id: \.offset) { index, interval in
                intervalDebugRow(index: index, interval: interval)
            }

            Divider()

            // Flattened Steps
            let flattened = flattenIntervals(workout.intervals)
            Text("FLATTENED STEPS (\(flattened.count))")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.Colors.accentGreen)

            ForEach(Array(flattened.enumerated()), id: \.offset) { index, step in
                flattenedStepDebugRow(index: index, step: step)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .cornerRadius(Theme.CornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
    }

    private func intervalDebugRow(index: Int, interval: WorkoutInterval) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            switch interval {
            case .warmup(let seconds, let target):
                Text("[\(index)] WARMUP")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange)
                Text("  seconds=\(seconds), target=\(target ?? "nil")")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.Colors.textSecondary)

            case .cooldown(let seconds, let target):
                Text("[\(index)] COOLDOWN")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
                Text("  seconds=\(seconds), target=\(target ?? "nil")")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.Colors.textSecondary)

            case .time(let seconds, let target):
                Text("[\(index)] TIME")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.blue)
                Text("  seconds=\(seconds), target=\(target ?? "nil")")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.Colors.textSecondary)

            case .reps(let sets, let reps, let name, let load, let restSec, let followAlongUrl):
                Text("[\(index)] REPS: \(name)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
                Text("  sets=\(sets.map { String($0) } ?? "nil")")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.Colors.textSecondary)
                Text("  reps=\(reps)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.Colors.textSecondary)
                Text("  restSec=\(restSec.map { String($0) } ?? "nil") ← \(restSecExplanation(restSec))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(restSec == nil ? .yellow : (restSec == 0 ? .red : Theme.Colors.textSecondary))
                Text("  load=\(load ?? "nil")")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.Colors.textSecondary)
                if let url = followAlongUrl {
                    Text("  followAlongUrl=\(url)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Theme.Colors.textTertiary)
                }

            case .distance(let meters, let target):
                Text("[\(index)] DISTANCE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.purple)
                Text("  meters=\(meters), target=\(target ?? "nil")")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.Colors.textSecondary)

            case .repeat(let reps, let subIntervals):
                Text("[\(index)] REPEAT x\(reps)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.pink)
                Text("  contains \(subIntervals.count) sub-intervals")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func restSecExplanation(_ restSec: Int?) -> String {
        if restSec == nil {
            return "MANUAL REST (tap when ready)"
        } else if restSec == 0 {
            return "NO REST (superset/HIIT)"
        } else {
            return "TIMED REST (\(restSec!)s countdown)"
        }
    }

    private func flattenedStepDebugRow(index: Int, step: FlattenedInterval) -> some View {
        HStack(spacing: 4) {
            Text("[\(index)]")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Theme.Colors.textTertiary)
                .frame(width: 24, alignment: .leading)

            if step.hasRestAfter {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.yellow)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(step.displayLabel)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.Colors.textPrimary)

                HStack(spacing: 8) {
                    Text("type=\(step.stepType == .timed ? "timed" : step.stepType == .reps ? "reps" : "distance")")
                    if let setNum = step.setNumber, let total = step.totalSets {
                        Text("set=\(setNum)/\(total)")
                    }
                    if step.hasRestAfter {
                        let restDesc = step.restAfterSeconds.map { $0 > 0 ? "\($0)s" : "manual" } ?? "manual"
                        Text("rest=\(restDesc)")
                            .foregroundColor(.yellow)
                    }
                }
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func generateWorkoutDebugText() -> String {
        var text = "=== WORKOUT DEBUG ===\n"
        text += "Status: \(workoutsViewModel.pendingWorkoutsStatus)\n\n"

        for workout in workoutsViewModel.incomingWorkouts {
            text += "WORKOUT: \(workout.name)\n"
            text += "ID: \(workout.id)\n"
            text += "Sport: \(workout.sport.rawValue)\n"
            text += "Duration: \(workout.duration)s\n\n"

            text += "RAW INTERVALS:\n"
            for (i, interval) in workout.intervals.enumerated() {
                text += formatIntervalForCopy(index: i, interval: interval)
            }

            text += "\nFLATTENED STEPS:\n"
            let flattened = flattenIntervals(workout.intervals)
            for (i, step) in flattened.enumerated() {
                let restDesc = step.hasRestAfter ? (step.restAfterSeconds.map { $0 > 0 ? "\($0)s" : "manual" } ?? "manual") : "none"
                text += "[\(i)] \(step.displayLabel) | type=\(step.stepType) | rest=\(restDesc)\n"
            }
            text += "\n---\n\n"
        }

        return text
    }

    private func formatIntervalForCopy(index: Int, interval: WorkoutInterval) -> String {
        switch interval {
        case .warmup(let seconds, let target):
            return "[\(index)] WARMUP: seconds=\(seconds), target=\(target ?? "nil")\n"
        case .cooldown(let seconds, let target):
            return "[\(index)] COOLDOWN: seconds=\(seconds), target=\(target ?? "nil")\n"
        case .time(let seconds, let target):
            return "[\(index)] TIME: seconds=\(seconds), target=\(target ?? "nil")\n"
        case .reps(let sets, let reps, let name, let load, let restSec, let followAlongUrl):
            return "[\(index)] REPS: \(name) | sets=\(sets.map { String($0) } ?? "nil") | reps=\(reps) | restSec=\(restSec.map { String($0) } ?? "nil") | load=\(load ?? "nil") | url=\(followAlongUrl ?? "nil")\n"
        case .distance(let meters, let target):
            return "[\(index)] DISTANCE: meters=\(meters), target=\(target ?? "nil")\n"
        case .repeat(let reps, let subIntervals):
            var text = "[\(index)] REPEAT x\(reps):\n"
            for (i, sub) in subIntervals.enumerated() {
                text += "  " + formatIntervalForCopy(index: i, interval: sub)
            }
            return text
        }
    }

    // MARK: - Debug Log Sheet

    private var debugLogSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Action buttons - Row 1
                HStack(spacing: Theme.Spacing.sm) {
                    Button {
                        garminConnectivity.sendTestPing()
                    } label: {
                        VStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text("Ping")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Colors.accentBlue.opacity(0.2))
                        .cornerRadius(Theme.CornerRadius.sm)
                    }

                    Button {
                        garminConnectivity.sendOpenAppRequest()
                    } label: {
                        VStack {
                            Image(systemName: "play.circle")
                            Text("Wake")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Colors.accentGreen.opacity(0.2))
                        .cornerRadius(Theme.CornerRadius.sm)
                    }

                    Button {
                        garminConnectivity.openWatchApp()
                    } label: {
                        VStack {
                            Image(systemName: "bag")
                            Text("Store")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Colors.accentOrange.opacity(0.2))
                        .cornerRadius(Theme.CornerRadius.sm)
                    }

                    Button {
                        garminConnectivity.clearLog()
                    } label: {
                        VStack {
                            Image(systemName: "trash")
                            Text("Clear")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Colors.accentRed.opacity(0.2))
                        .cornerRadius(Theme.CornerRadius.sm)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .foregroundColor(Theme.Colors.textPrimary)

                // Action buttons - Row 2
                HStack(spacing: Theme.Spacing.sm) {
                    Button {
                        showingManualUUIDSheet = true
                    } label: {
                        VStack {
                            Image(systemName: "keyboard")
                            Text("Manual")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(Theme.CornerRadius.sm)
                    }

                    Button {
                        garminConnectivity.tryAlternativeDeviceDiscovery()
                    } label: {
                        VStack {
                            Image(systemName: "magnifyingglass")
                            Text("Discover")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Color.purple.opacity(0.2))
                        .cornerRadius(Theme.CornerRadius.sm)
                    }

                    Button {
                        garminConnectivity.reinitializeSDK()
                    } label: {
                        VStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Color.yellow.opacity(0.2))
                        .cornerRadius(Theme.CornerRadius.sm)
                    }

                    Button {
                        garminConnectivity.checkAppStatus()
                    } label: {
                        VStack {
                            Image(systemName: "questionmark.circle")
                            Text("Status")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Color.cyan.opacity(0.2))
                        .cornerRadius(Theme.CornerRadius.sm)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .foregroundColor(Theme.Colors.textPrimary)

                Divider()

                // Status summary
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        statusPill("SDK", garminConnectivity.getDetailedStatus()["sdkEnabled"] as? Bool ?? false)
                        statusPill("GCM", garminConnectivity.isGarminConnectInstalled())
                        statusPill("Device", garminConnectivity.isConnected)
                        statusPill("App", garminConnectivity.isAppInstalled)
                    }
                    Text("UUID: \(garminConnectivity.getDetailedStatus()["appUUID"] as? String ?? "?")")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                .padding(Theme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colors.surfaceElevated)

                // Bluetooth permission warning
                if garminConnectivity.isBluetoothUnauthorized {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Bluetooth permission denied")
                            .font(.caption)
                        Spacer()
                        Button("Open Settings") {
                            garminConnectivity.openIOSSettings()
                        }
                        .font(.caption.bold())
                        .foregroundColor(.blue)
                    }
                    .padding(Theme.Spacing.sm)
                    .background(Color.orange.opacity(0.15))
                }

                Divider()

                // Log entries
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if garminConnectivity.debugLog.isEmpty {
                            Text("No log entries yet. Tap 'Ping' to send a test message.")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textTertiary)
                                .padding()
                        } else {
                            ForEach(garminConnectivity.debugLog, id: \.self) { entry in
                                Text(entry)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(logColor(for: entry))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(Theme.Spacing.sm)
                }
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Garmin Debug Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showingDebugLog = false
                    }
                }
            }
        }
    }

    private func statusPill(_ label: String, _ isActive: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isActive ? Color.green : Color.red)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Theme.Colors.surface)
        .cornerRadius(4)
    }

    private func logColor(for entry: String) -> Color {
        if entry.contains("ERROR") || entry.contains("❌") || entry.contains("FAILED") {
            return Theme.Colors.accentRed
        } else if entry.contains("SUCCESS") || entry.contains("✅") || entry.contains("CONNECTED") {
            return Theme.Colors.accentGreen
        } else if entry.contains("WARNING") {
            return Theme.Colors.accentOrange
        }
        return Theme.Colors.textSecondary
    }

    private func formatRefreshDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Manual UUID Entry Sheet

    private var manualUUIDSheet: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("This is a workaround for when the Garmin Connect device picker doesn't work properly.")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)

                    Text("To find your Device UUID:")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .padding(.top, Theme.Spacing.md)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. Open Garmin Connect app")
                        Text("2. Go to Settings > Garmin Devices")
                        Text("3. Select your watch")
                        Text("4. Look for 'Device ID' or 'Unit ID'")
                    }
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                }
                .padding(.horizontal, Theme.Spacing.lg)

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Device Name")
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.textSecondary)

                    TextField("e.g. Forerunner 265", text: $manualDeviceName)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.words)
                }
                .padding(.horizontal, Theme.Spacing.lg)

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Device UUID")
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.textSecondary)

                    TextField("XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX", text: $manualUUID)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .font(.system(.body, design: .monospaced))
                }
                .padding(.horizontal, Theme.Spacing.lg)

                Spacer()

                Button {
                    let name = manualDeviceName.isEmpty ? "Garmin Watch" : manualDeviceName
                    if garminConnectivity.manuallyRegisterDevice(uuidString: manualUUID.trimmingCharacters(in: .whitespacesAndNewlines), friendlyName: name) {
                        showingManualUUIDSheet = false
                        manualUUID = ""
                        manualDeviceName = ""
                    }
                } label: {
                    Text("Connect Device")
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.md)
                        .background(Theme.Colors.accentBlue)
                        .cornerRadius(Theme.CornerRadius.md)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.lg)
            }
            .padding(.top, Theme.Spacing.lg)
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Manual Device Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingManualUUIDSheet = false
                    }
                }
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

            // Saved device reconnect (alternative to broken picker)
            if let savedDevice = garminConnectivity.savedDeviceInfo, !garminConnectivity.isConnected {
                Button {
                    garminConnectivity.connectToSavedDevice()
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Reconnect to \(savedDevice.friendlyName)")
                    }
                    .font(Theme.Typography.body)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.accentGreen)
                    .cornerRadius(Theme.CornerRadius.md)
                }
            }

            // Action buttons - Row 1
            HStack(spacing: Theme.Spacing.md) {
                Button {
                    garminConnectivity.openGarminConnectApp()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.forward.app")
                        Text("Open GCM")
                    }
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.garminBlue)
                }

                Button {
                    showingDebugLog = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "ant")
                        Text("Debug Log")
                    }
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.accentOrange)
                }

                Button {
                    garminConnectivity.connectToMockDevice()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "ladybug")
                        Text("Test UI")
                    }
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.accentGreen)
                }
            }

            // Action buttons - Row 2
            HStack(spacing: Theme.Spacing.md) {
                if garminConnectivity.savedDeviceInfo != nil {
                    Button {
                        garminConnectivity.clearSavedDevice()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Forget Device")
                        }
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.accentRed)
                    }
                }

                if garminConnectivity.isConnected {
                    Button {
                        garminConnectivity.disconnect()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle")
                            Text("Disconnect")
                        }
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.accentRed)
                    }
                }
            }

            // Debug status section - tap to show full status
            Button {
                garminDebugMessage = garminConnectivity.getSDKStatus()
                showingGarminDebugAlert = true
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DEBUG STATUS (tap for details)")
                        .font(Theme.Typography.footnote)
                        .foregroundColor(Theme.Colors.textTertiary)

                    HStack(spacing: Theme.Spacing.md) {
                        statusIndicator("GC App", garminConnectivity.isGarminConnectInstalled())
                        statusIndicator("Device", garminConnectivity.isConnected)
                        statusIndicator("CIQ App", garminConnectivity.isAppInstalled)
                    }

                    if !garminConnectivity.knownDevices.isEmpty {
                        Text("Known: \(garminConnectivity.knownDevices.joined(separator: ", "))")
                            .font(Theme.Typography.footnote)
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                }
                .padding(Theme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colors.surfaceElevated)
                .cornerRadius(Theme.CornerRadius.sm)
            }
            .buttonStyle(.plain)

            // Info text
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Image(systemName: "info.circle")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.Colors.textTertiary)

                Text("Tap 'Connect Garmin Watch' to pair your watch via Garmin Connect Mobile. Once connected, it will be remembered for future sessions.")
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

    private func statusIndicator(_ label: String, _ isActive: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isActive ? Theme.Colors.accentGreen : Theme.Colors.accentRed)
                .frame(width: 8, height: 8)
            Text(label)
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textTertiary)
        }
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

            VStack(spacing: Theme.Spacing.md) {
                // User Profile Card
                HStack(spacing: Theme.Spacing.md) {
                    // Profile image
                    if let avatarUrl = pairingService.userProfile?.avatarUrl,
                       let url = URL(string: avatarUrl) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            profilePlaceholder
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                    } else {
                        profilePlaceholder
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        if let profile = pairingService.userProfile {
                            Text(profile.name ?? profile.email ?? "AmakaFlow User")
                                .font(Theme.Typography.bodyBold)
                                .foregroundColor(Theme.Colors.textPrimary)

                            if let email = profile.email {
                                Text(email)
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                        } else {
                            Text("Connected")
                                .font(Theme.Typography.bodyBold)
                                .foregroundColor(Theme.Colors.textPrimary)

                            Text("No profile data available")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    }

                    Spacer()

                    // Connection status badge
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Theme.Colors.accentGreen)
                                .frame(width: 8, height: 8)
                            Text("Connected")
                                .font(Theme.Typography.footnote)
                        }
                        .foregroundColor(Theme.Colors.accentGreen)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, 4)
                        .background(Theme.Colors.accentGreen.opacity(0.1))
                        .cornerRadius(Theme.CornerRadius.sm)

                        // Token refresh timestamp
                        if let refreshDate = pairingService.lastTokenRefresh {
                            Text("Refreshed: \(formatRefreshDate(refreshDate))")
                                .font(.system(size: 9))
                                .foregroundColor(Theme.Colors.textTertiary)
                        }
                    }
                }

                // Environment info
                HStack {
                    Image(systemName: "server.rack")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text("Environment: \(AppEnvironment.current.displayName)")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                    Spacer()
                }

                // App version
                HStack {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                    Spacer()
                }

                #if DEBUG
                // Debug: Copy API token for testing
                HStack {
                    Image(systemName: "key")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text("API Token")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                    Spacer()
                    Button {
                        if let token = pairingService.getToken() {
                            UIPasteboard.general.string = token
                        }
                    } label: {
                        Text("Copy")
                            .font(Theme.Typography.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, 4)
                            .background(Theme.Colors.accentBlue)
                            .cornerRadius(Theme.CornerRadius.sm)
                    }
                }

                // Debug: Refresh Token
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text("Refresh Token")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                    Spacer()
                    Button {
                        Task {
                            let success = await pairingService.refreshToken()
                            print("[Settings] Manual token refresh: \(success ? "SUCCESS" : "FAILED")")
                        }
                    } label: {
                        Text("Refresh")
                            .font(Theme.Typography.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, 4)
                            .background(Theme.Colors.accentGreen)
                            .cornerRadius(Theme.CornerRadius.sm)
                    }
                }

                // Debug: Error Log
                NavigationLink {
                    DebugLogView()
                } label: {
                    HStack {
                        Image(systemName: "ladybug")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.Colors.accentOrange)
                        Text("Debug Log")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textTertiary)
                        Spacer()
                        Text("\(DebugLogService.shared.entries.count)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Theme.Colors.accentOrange)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                }
                #endif

                // Debug: Pending workouts status
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.Colors.textTertiary)
                        Text("Pending Workouts:")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textTertiary)
                        Spacer()
                    }
                    Text(workoutsViewModel.pendingWorkoutsStatus.isEmpty ? "Not checked yet" : workoutsViewModel.pendingWorkoutsStatus)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.Colors.accentBlue)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: Theme.Spacing.sm) {
                        Button {
                            Task {
                                await workoutsViewModel.checkPendingWorkouts()
                            }
                        } label: {
                            Text("Check Now")
                                .font(Theme.Typography.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.vertical, Theme.Spacing.xs)
                                .background(Theme.Colors.accentBlue)
                                .cornerRadius(Theme.CornerRadius.sm)
                        }

                        Button {
                            showingWorkoutDebugSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "ant")
                                Text("Debug")
                            }
                            .font(Theme.Typography.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.xs)
                            .background(Theme.Colors.accentOrange)
                            .cornerRadius(Theme.CornerRadius.sm)
                        }
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .stroke(Theme.Colors.borderLight, lineWidth: 1)
            )
            .cornerRadius(Theme.CornerRadius.md)

            // Disconnect button
            Button {
                showingDisconnectAlert = true
            } label: {
                HStack(spacing: Theme.Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                            .fill(Theme.Colors.accentRed.opacity(0.1))
                            .frame(width: 48, height: 48)

                        Image(systemName: "link.badge.minus")
                            .font(.system(size: 22))
                            .foregroundColor(Theme.Colors.accentRed)
                    }

                    Text("Disconnect Account")
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
        .confirmationDialog("Disconnect Account?", isPresented: $showingDisconnectAlert, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                pairingService.unpair()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to pair again to sync workouts from AmakaFlow.")
        }
    }

    private var profilePlaceholder: some View {
        ZStack {
            Circle()
                .fill(Theme.Colors.accentBlue.opacity(0.2))
                .frame(width: 56, height: 56)
            Image(systemName: "person.fill")
                .font(.system(size: 24))
                .foregroundColor(Theme.Colors.accentBlue)
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
        .environmentObject(PairingService.shared)
        .environmentObject(WorkoutsViewModel())
        .preferredColorScheme(.dark)
}
