//
//  UnifiedWorkoutDetailView.swift
//  AmakaFlow
//
//  AMA-2291: One Library → detail layout for every workout source.
//  Edit always available (AI never gatekeeps). Start opens gym + device sheet.
//

import SwiftUI

struct UnifiedWorkoutDetailView: View {
    @State private var displayedWorkout: Workout

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var workoutsViewModel: WorkoutsViewModel

    @State private var showingStartSheet = false
    @State private var showingEditor = false
    @State private var showingWorkoutPlayer = false
    @State private var handoffStatus: String?

    /// Injected for previews / tests. Production reads live managers.
    var garminPairedOverride: Bool?
    var appleWatchReachableOverride: Bool?
    /// Optional reload after Edit save — Library passes load + resolve by id.
    var onEditorDismiss: (() async -> Workout?)?

    init(
        workout: Workout,
        garminPairedOverride: Bool? = nil,
        appleWatchReachableOverride: Bool? = nil,
        onEditorDismiss: (() async -> Workout?)? = nil
    ) {
        _displayedWorkout = State(initialValue: workout)
        self.garminPairedOverride = garminPairedOverride
        self.appleWatchReachableOverride = appleWatchReachableOverride
        self.onEditorDismiss = onEditorDismiss
    }

    private var workout: Workout { displayedWorkout }

    private var garminPaired: Bool {
        if let garminPairedOverride { return garminPairedOverride }
        #if DEBUG
        if UITestEnvironment.isTruthy("UITEST_GARMIN_PAIRED") {
            return true
        }
        #endif
        return GarminConnectManager.shared.isConnected
            || GarminConnectManager.shared.savedDeviceInfo != nil
    }

    private var appleWatchReachable: Bool {
        appleWatchReachableOverride ?? WatchConnectivityManager.shared.isWatchReachable
    }

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    topBar
                        .padding(.horizontal, -Theme.Spacing.lg)

                    hero
                    titleBlock
                    pillsRow
                    creditRow
                    primaryActions
                    blockList
                    if let handoffStatus {
                        Text(handoffStatus)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .accessibilityIdentifier("af_workout_detail_handoff_status")
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, 120)
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingStartSheet) {
            WorkoutStartSheet(
                workout: workout,
                garminPaired: garminPaired,
                appleWatchReachable: appleWatchReachable,
                onConfirm: { gym, device in
                    showingStartSheet = false
                    handleStartConfirm(gym: gym, device: device)
                },
                onClose: { showingStartSheet = false }
            )
            .presentationDetents([.large, .medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(
            isPresented: $showingEditor,
            onDismiss: {
                Task {
                    if let refreshed = await onEditorDismiss?() {
                        displayedWorkout = refreshed
                    }
                }
            },
            content: {
                // AI never gatekeeps — Edit always opens the structure editor.
                WorkoutEditorView(workout: displayedWorkout)
            }
        )
        .fullScreenCover(isPresented: $showingWorkoutPlayer) {
            WorkoutPlayerView()
        }
        .accessibilityIdentifier("af_workout_detail_screen")
    }

    private var topBar: some View {
        AFTopBar(
            title: "Workout",
            subtitle: provenanceSubtitle,
            backIdentifier: "af_workout_detail_back",
            backAction: { dismiss() },
            right: { EmptyView() }
        )
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Theme.Colors.readyHigh.opacity(0.95), Theme.Colors.readyHigh.opacity(0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: sportIcon)
                .font(.system(size: 44, weight: .semibold))
                .foregroundColor(Theme.Colors.primaryForeground.opacity(0.92))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let badge = WorkoutSourceProvenance.badge(for: workout.source.rawValue) {
                AFChip(text: badge.label, outline: false)
                    .padding(Theme.Spacing.md)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .accessibilityIdentifier("af_workout_detail_hero")
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(workout.name)
                .font(Theme.Typography.title1)
                .foregroundColor(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("af_workout_detail_title")

            if let description = workout.description, !description.isEmpty {
                Text(description)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
    }

    private var pillsRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            AFChip(text: workout.sport.rawValue.capitalized, outline: true)
            AFChip(text: workout.formattedDuration, outline: true)
            if workout.exerciseCount > 0 {
                AFChip(text: "\(workout.exerciseCount) exercises", outline: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityIdentifier("af_workout_detail_pills")
    }

    @ViewBuilder
    private var creditRow: some View {
        if LibraryDetailRouting.showsSocialCreditRow(source: workout.source) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Theme.Colors.accentBlue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(creditCreatorLabel)
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)

                    if let label = WorkoutSourceProvenance.externalLabel(for: workout.source.rawValue),
                       let url = WorkoutSourceProvenance.externalURL(for: workout) {
                        Button {
                            openURL(url)
                        } label: {
                            HStack(spacing: 4) {
                                Text("Open in \(label)")
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.accentBlue)
                        }
                        .accessibilityIdentifier(creditOpenIdentifier(for: label))
                    } else {
                        Text("Source link unavailable")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                            .accessibilityIdentifier("af_credit_open_absent")
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .stroke(Theme.Colors.borderLight, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
            .accessibilityIdentifier("af_workout_detail_credit_row")
        }
    }

    private var blockList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Structure")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)

            if workout.blocks.isEmpty {
                AFCard {
                    Text("No blocks yet — tap Edit to build the structure.")
                        .afMuted()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("af_workout_detail_blocks_empty")
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(Array(workout.blocks.enumerated()), id: \.element.id) { index, block in
                        BlockSectionView(block: block, blockIndex: index)
                    }
                }
                .accessibilityIdentifier("af_workout_detail_blocks")
            }
        }
    }

    private var primaryActions: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button {
                showingEditor = true
            } label: {
                Text("Edit")
                    .font(Theme.Typography.bodyBold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(AFGhostButtonStyle(size: .md))
            .accessibilityIdentifier("af_workout_detail_edit")

            Button {
                showingStartSheet = true
            } label: {
                Text("Start")
                    .font(Theme.Typography.bodyBold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(AFPrimaryButtonStyle(size: .md))
            .accessibilityIdentifier("af_workout_detail_start")
        }
    }

    // MARK: - Start handoffs

    private func handleStartConfirm(gym: WorkoutStartGym, device: WorkoutStartDevice) {
        let handoff = WorkoutStartHandoffResolver.handoff(for: device)
        switch handoff {
        case .garmin:
            // AMA-2286: CIQ FIT queue (AMA-1387). Not live remote sendWorkoutState; not garth.
            handoffStatus = "Queueing for Garmin…"
            Task {
                let result = await GarminStartHandoffService().push(
                    workoutId: workout.id,
                    gymTitle: gym.title
                )
                handoffStatus = result.message
                if result.kind != .failed {
                    GarminConnectManager.shared.sendOpenAppRequest()
                }
            }
        case .apple:
            // AMA-2287: full Apple Workout try. Prefer send-to-watch when reachable.
            if appleWatchReachable {
                Task {
                    await workoutsViewModel.sendToWatch(workout)
                    handoffStatus = "Sent to Apple Watch — AMA-2287 try path"
                }
            } else if #available(iOS 18.0, *) {
                Task {
                    do {
                        try await WorkoutKitConverter.shared.saveToWorkoutKit(workout)
                        handoffStatus = "Saved to Apple Fitness (try) — AMA-2287"
                    } catch {
                        handoffStatus = "Apple try stub — Watch unreachable (\(error.localizedDescription))"
                    }
                }
            } else {
                handoffStatus = "Apple try stub — Watch unreachable (AMA-2287)"
            }
        case .phone:
            // AMA-2290: full strength phone player. Reuse existing engine/player entry.
            WorkoutEngine.shared.start(workout: workout)
            showingWorkoutPlayer = true
            handoffStatus = "Phone player opened — AMA-2290 stub uses existing player"
        }
    }

    // MARK: - Helpers

    private var provenanceSubtitle: String {
        WorkoutSourceProvenance.badge(for: workout.source.rawValue)?.label ?? "Library"
    }

    private var creditCreatorLabel: String {
        if let label = WorkoutSourceProvenance.externalLabel(for: workout.source.rawValue) {
            return "From \(label)"
        }
        return "Imported workout"
    }

    private func creditOpenIdentifier(for label: String) -> String {
        switch label.lowercased() {
        case "instagram": return "af_credit_open_instagram"
        case "tiktok": return "af_credit_open_tiktok"
        case "youtube": return "af_credit_open_youtube"
        default: return "af_credit_open_external"
        }
    }

    private var sportIcon: String {
        switch workout.sport {
        case .running: return "figure.run"
        case .cycling: return "bicycle"
        case .strength: return "dumbbell.fill"
        case .mobility: return "figure.yoga"
        case .swimming: return "figure.pool.swim"
        case .cardio: return "figure.mixed.cardio"
        case .other: return "figure.elliptical"
        }
    }
}

#if DEBUG
#Preview("Social") {
    NavigationStack {
        UnifiedWorkoutDetailView(
            workout: Workout(
                name: "IG Push Day",
                sport: .strength,
                duration: 2400,
                intervals: [
                    .reps(sets: 3, reps: 8, name: "Bench", load: nil, restSec: 90, followAlongUrl: nil)
                ],
                source: .instagram,
                sourceUrl: "https://instagram.com/reel/abc"
            ),
            garminPairedOverride: true,
            appleWatchReachableOverride: false
        )
        .environmentObject(WorkoutsViewModel())
    }
}

#Preview("Manual") {
    NavigationStack {
        UnifiedWorkoutDetailView(
            workout: Workout(
                name: "Manual Full Body",
                sport: .strength,
                duration: 1800,
                intervals: [],
                source: .manual
            ),
            garminPairedOverride: false,
            appleWatchReachableOverride: true
        )
        .environmentObject(WorkoutsViewModel())
    }
}
#endif
