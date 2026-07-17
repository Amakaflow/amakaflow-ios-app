//
//  UnifiedWorkoutDetailView.swift
//  AmakaFlow
//
//  AMA-2291: Library workout detail — Daily Driver layout (DDDetailScreen).
//  Edit always available. Start opens gym + device sheet.
//

import SwiftUI

struct UnifiedWorkoutDetailView: View {
    @State private var displayedWorkout: Workout
    @AppStorage(DefaultsKey.userDisplayName.rawValue) private var userDisplayName = ""

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var workoutsViewModel: WorkoutsViewModel

    @State private var showingStartSheet = false
    @State private var showingEditor = false
    @State private var showingWorkoutPlayer = false
    @State private var handoffStatus: String?
    @State private var isSavingImport = false

    var garminPairedOverride: Bool?
    var appleWatchReachableOverride: Bool?
    var onEditorDismiss: (() async -> Workout?)?
    /// When set, this detail is showing an unsaved social-import draft (SPEC § Create → detail).
    var importContext: WorkoutDetailImportContext?
    var onClose: (() -> Void)?

    init(
        workout: Workout,
        garminPairedOverride: Bool? = nil,
        appleWatchReachableOverride: Bool? = nil,
        onEditorDismiss: (() async -> Workout?)? = nil,
        importContext: WorkoutDetailImportContext? = nil,
        onClose: (() -> Void)? = nil
    ) {
        _displayedWorkout = State(initialValue: workout)
        self.garminPairedOverride = garminPairedOverride
        self.appleWatchReachableOverride = appleWatchReachableOverride
        self.onEditorDismiss = onEditorDismiss
        self.importContext = importContext
        self.onClose = onClose
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
        ZStack(alignment: .bottom) {
            DailyDriver.screenBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    contentBody
                }
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)

            bottomActionBar
        }
        .preferredColorScheme(.dark)
        .ddSuppressFloatingChrome()
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
            .presentationDragIndicator(.hidden)
            .presentationBackground(DailyDriver.screenBackground)
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
                WorkoutEditorView(workout: displayedWorkout)
            }
        )
        .fullScreenCover(isPresented: $showingWorkoutPlayer) {
            WorkoutPlayerView()
        }
        .accessibilityIdentifier("af_workout_detail_screen")
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack {
            LinearGradient(
                colors: heroGradientColors,
                startPoint: UnitPoint(x: 0.2, y: 0),
                endPoint: UnitPoint(x: 0.8, y: 1)
            )

            Image(systemName: heroIcon)
                .font(.system(size: 38, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))

            VStack {
                HStack {
                    Button {
                        closeDetail()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("af_workout_detail_back")
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                Spacer()

                HStack(spacing: 7) {
                    ForEach(heroPills, id: \.self) { pill in
                        Text(pill)
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Capsule())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .frame(height: 190)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("af_workout_detail_hero")
    }

    // MARK: - Body

    private var contentBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(workout.name)
                .ddDisplayText(24, weight: .heavy)
                .foregroundColor(DailyDriver.foreground)
                .lineSpacing(2)
                .accessibilityIdentifier("af_workout_detail_title")

            if let description = displayDescription, !description.isEmpty {
                Text(description)
                    .font(.system(size: 12.5))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .lineSpacing(4)
                    .padding(.top, 8)
            }

            creditRow
                .padding(.top, 12)

            blockList
                .padding(.top, 4)

            if let handoffStatus {
                Text(handoffStatus)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(.top, Theme.Spacing.md)
                    .accessibilityIdentifier("af_workout_detail_handoff_status")
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
    }

    private var creditRow: some View {
        HStack(spacing: 10) {
            Text(creditInitial)
                .ddDisplayText(13, weight: .heavy)
                .foregroundColor(creditInk)
                .frame(width: 32, height: 32)
                .background(creditBackground)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(creditName)
                    .ddDisplayText(12.5, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                Text(creditSubtitle)
                    .font(.system(size: 10))
                    .foregroundColor(DailyDriver.foregroundMuted)
            }

            Spacer(minLength: 0)

            if let action = creditActionLabel {
                Button {
                    if let url = creditOpenURL {
                        openURL(url)
                    }
                } label: {
                    Text(action)
                        .ddDisplayText(11, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(DailyDriver.card2)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(creditOpenIdentifier(for: action))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("af_workout_detail_credit_row")
    }

    private var blockList: some View {
        Group {
            let sections = DDWorkoutDisplayGrouping.sections(for: workout)
            if sections.isEmpty {
                Text("No blocks yet — tap Edit to build the structure.")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .padding(.top, 18)
                    .accessibilityIdentifier("af_workout_detail_blocks_empty")
            } else {
                ForEach(sections) { section in
                    DDWorkoutBlockSectionView(section: section)
                        .padding(.top, 18)
                }
                .accessibilityIdentifier("af_workout_detail_blocks")
            }
        }
    }

    // MARK: - Bottom CTAs

    private var bottomActionBar: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 8
            let editWidth = (proxy.size.width - gap) * (1 / 2.2)
            let startWidth = (proxy.size.width - gap) * (1.2 / 2.2)

            HStack(spacing: gap) {
                Button {
                    showingEditor = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Edit")
                            .ddDisplayText(15, weight: .bold)
                    }
                    .foregroundColor(DailyDriver.foreground)
                    .frame(width: editWidth)
                    .padding(.vertical, 16)
                    .background(DailyDriver.tabBarBackground)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(DailyDriver.borderStrong, lineWidth: 1)
                    )
                    .clipShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("af_workout_detail_edit")

                Button {
                    Task { await handleStartTapped() }
                } label: {
                    HStack(spacing: 6) {
                        if isSavingImport {
                            ProgressView()
                                .tint(DailyDriver.ink)
                        } else {
                            Text("▶")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        Text("Start")
                            .ddDisplayText(15, weight: .bold)
                    }
                    .foregroundColor(DailyDriver.ink)
                    .frame(width: startWidth)
                    .padding(.vertical, 16)
                    .background(DailyDriver.lime)
                    .clipShape(Capsule(style: .continuous))
                    .ddLimeGlow()
                }
                .disabled(isSavingImport)
                .buttonStyle(.plain)
                .accessibilityIdentifier("af_workout_detail_start")
            }
        }
        .frame(height: 52)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}

// MARK: - Start handoffs + helpers

extension UnifiedWorkoutDetailView {
    fileprivate var displayDescription: String? {
        workout.description
    }

    fileprivate func closeDetail() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    fileprivate func handleStartTapped() async {
        if let importContext, !importContext.isSaved {
            isSavingImport = true
            await importContext.viewModel.saveToLibrary()
            isSavingImport = false
            if case .saved(let workoutId) = importContext.viewModel.phase {
                importContext.onLibraryReload()
                displayedWorkout = withSavedId(workoutId)
            } else {
                return
            }
        }
        showingStartSheet = true
    }

    /// Resolve provenance from source + URL (imports may arrive as `.amaka` / `.other`).
    fileprivate var resolvedSourceKey: String {
        if workout.source != .other && workout.source != .amaka {
            return workout.source.rawValue
        }
        if let url = workout.sourceUrl, !url.isEmpty {
            return SocialImportPlatform.detect(from: url).rawValue
        }
        return workout.source.rawValue
    }

    fileprivate var heroPills: [String] {
        var pills: [String] = [sourceHeroPill]

        if workout.exerciseCount > 0 {
            let rounds = heroRoundCount
            if rounds > 1 {
                pills.append("\(rounds) ROUNDS · \(ddHeroDurationLabel)")
            } else {
                pills.append("\(workout.exerciseCount) EXERCISES · \(ddHeroDurationLabel)")
            }
        } else if workout.blockCount > 0 {
            pills.append("\(workout.blockCount) BLOCKS · \(ddHeroDurationLabel)")
        } else {
            pills.append(ddHeroDurationLabel)
        }

        pills.append(sportHeroPill)
        return pills
    }

    fileprivate var ddHeroDurationLabel: String {
        let minutes = max(1, workout.duration / 60)
        return "~\(minutes) MIN"
    }

    /// Whole-workout round count for hero chips (dd-detail-dark: "5 ROUNDS · ~20 MIN").
    fileprivate var heroRoundCount: Int {
        if let parsed = Self.parseRoundCount(from: workout.description) {
            return parsed
        }
        let workBlocks = workout.blocks.filter { !Self.isWarmupOrCooldown($0) }
        let rounds = workBlocks.map(\.rounds).max() ?? 1
        return max(1, rounds)
    }

    fileprivate static func parseRoundCount(from description: String?) -> Int? {
        guard let description else { return nil }
        let lowered = description.lowercased()
        let wordMap = [
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
            "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10
        ]
        for (word, value) in wordMap where lowered.contains("\(word) rounds") {
            return value
        }
        guard let regex = try? NSRegularExpression(pattern: "(\\d+)\\s+rounds", options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(lowered.startIndex..<lowered.endIndex, in: lowered)
        guard let match = regex.firstMatch(in: lowered, options: [], range: range),
              match.numberOfRanges > 1,
              let swiftRange = Range(match.range(at: 1), in: lowered),
              let value = Int(lowered[swiftRange]) else {
            return nil
        }
        return value
    }

    fileprivate static func isWarmupOrCooldown(_ block: Block) -> Bool {
        let label = block.label?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return label == "warm-up" || label == "warmup" || label == "cool-down" || label == "cooldown"
    }

    fileprivate var sourceHeroPill: String {
        if workout.source == .coach {
            return "FROM TRAINER"
        }
        if workout.source == .manual || workout.source == .gymManualSync {
            return "CREATED BY YOU"
        }
        if let badge = WorkoutSourceProvenance.badge(for: resolvedSourceKey) {
            if WorkoutSourceProvenance.isExternal(resolvedSourceKey) {
                return "FROM \(badge.label)".uppercased()
            }
            if workout.source == .ai || workout.source == .smartPlanner || workout.source == .amaka {
                return "FROM AI COACH"
            }
            return "FROM \(badge.label)".uppercased()
        }
        return "CREATED BY YOU"
    }

    fileprivate var sportHeroPill: String {
        if workout.name.localizedCaseInsensitiveContains("hyrox") {
            return "HYROX"
        }
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

    fileprivate var heroGradientColors: [Color] {
        switch DDPlatform.resolve(source: workout.source, sourceUrl: workout.sourceUrl) {
        case .instagram:
            return [Color(hex: "3A1145"), Color(hex: "1A0A22"), Color(hex: "0A0A0B")]
        case .tiktok:
            return [Color(hex: "0D3830"), Color(hex: "062019"), Color(hex: "0A0A0B")]
        case .coach:
            return [Color(hex: "33240A"), Color(hex: "1D1405"), Color(hex: "0A0A0B")]
        case .ai:
            return [Color(hex: "101C30"), Color(hex: "060A12"), Color(hex: "0A0A0B")]
        case .manual, .all:
            switch workout.sport {
            case .running, .cycling, .swimming:
                return [Color(hex: "0D2438"), Color(hex: "071522"), Color(hex: "0A0A0B")]
            case .cardio:
                return [Color(hex: "2A3505"), Color(hex: "141B03"), Color(hex: "0A0A0B")]
            default:
                return [Color(hex: "2A3505"), Color(hex: "141B03"), Color(hex: "0A0A0B")]
            }
        }
    }

    fileprivate var heroIcon: String {
        if WorkoutSourceProvenance.isExternal(resolvedSourceKey) {
            return "play.fill"
        }
        switch workout.sport {
        case .running: return "figure.run"
        case .cycling: return "bicycle"
        case .strength, .mobility: return "dumbbell.fill"
        case .swimming: return "figure.pool.swim"
        case .cardio: return "flame.fill"
        case .other: return "dumbbell.fill"
        }
    }

    fileprivate var storedCreatorName: String? {
        let trimmed = workout.creatorName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    fileprivate var resolvedCreatorName: String? {
        if let storedCreatorName { return storedCreatorName }
        if workout.source == .coach {
            let coach = creatorHandle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !coach.isEmpty, coach.lowercased() != "you" { return coach }
        }
        return nil
    }

    fileprivate var creditDateSuffix: String? {
        workout.createdAt?.formatted(.dateTime.month(.abbreviated).day())
    }

    fileprivate var creatorHandle: String {
        if let url = workout.sourceUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
            if url.hasPrefix("@") {
                return String(url.dropFirst())
            }
            if let host = URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") {
                let path = URL(string: url)?.pathComponents.filter { $0 != "/" } ?? []
                if let first = path.first, !first.isEmpty, !first.contains(".") {
                    return first
                }
                return host
            }
            if !url.contains("://") {
                return url
            }
        }
        return DDLibraryPresentation.creatorLabel(for: workout)
    }

    fileprivate var coachDisplayName: String {
        let handle = resolvedCreatorName ?? creatorHandle
        if handle == "you" || handle.isEmpty {
            return "Coach"
        }
        if handle.localizedCaseInsensitiveContains("coach") {
            let parts = handle.split(separator: " ").map(String.init)
            if parts.count >= 2 {
                return parts.joined(separator: " ")
            }
            return "Coach \(handle.capitalized)"
        }
        if handle.contains(" ") {
            return "Coach \(handle)"
        }
        return "Coach \(handle)"
    }

    fileprivate var creditInitial: String {
        if workout.source == .coach {
            return String(coachDisplayName.prefix(1)).uppercased()
        }
        if WorkoutSourceProvenance.isExternal(resolvedSourceKey) {
            return String(creatorHandle.prefix(1)).lowercased()
        }
        let trimmed = userDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return String(trimmed.prefix(1)).uppercased()
        }
        return "Y"
    }

    fileprivate var creditBackground: Color {
        switch resolvedSourceKey.lowercased() {
        case "instagram": return DailyDriver.purple
        case "tiktok": return Color(hex: "4AD9D9")
        case "youtube": return DailyDriver.red
        case "manual", "gym_manual_sync": return DailyDriver.lime
        case "coach": return DailyDriver.orange
        default: return DailyDriver.lime
        }
    }

    fileprivate var creditInk: Color {
        switch resolvedSourceKey.lowercased() {
        case "tiktok": return Color(hex: "00211F")
        case "manual", "gym_manual_sync": return DailyDriver.ink
        default:
            return creditBackground == DailyDriver.lime ? DailyDriver.ink : .white
        }
    }

    fileprivate var creditName: String {
        if workout.source == .manual || workout.source == .gymManualSync {
            return "You"
        }
        if workout.source == .coach {
            return coachDisplayName
        }
        if WorkoutSourceProvenance.isExternal(resolvedSourceKey) {
            if let creator = resolvedCreatorName {
                let trimmed = creator.hasPrefix("@") ? String(creator.dropFirst()) : creator
                return trimmed
            }
            return creatorHandle
        }
        if workout.source == .ai || workout.source == .smartPlanner || workout.source == .amaka {
            return "AmakaFlow AI"
        }
        return "You"
    }

    fileprivate var creditSubtitle: String {
        if workout.source == .manual || workout.source == .gymManualSync {
            if let date = creditDateSuffix {
                return "Created manually · \(date)"
            }
            return "Created manually"
        }
        if workout.source == .coach {
            if let date = creditDateSuffix {
                return "Shared with you · \(date)"
            }
            return "Shared with you"
        }
        if WorkoutSourceProvenance.isExternal(resolvedSourceKey) {
            return "Workout by"
        }
        if workout.source == .ai || workout.source == .smartPlanner {
            return "Built by AI Coach"
        }
        return "Created manually"
    }

    fileprivate var creditActionLabel: String? {
        if workout.source == .coach {
            return "Message"
        }
        if creditOpenURL != nil,
           let label = WorkoutSourceProvenance.externalLabel(for: resolvedSourceKey) {
            return "Open in \(label)"
        }
        return nil
    }

    fileprivate var creditOpenURL: URL? {
        if let url = WorkoutSourceProvenance.externalURL(for: workout) {
            return url
        }
        guard let sourceUrl = workout.sourceUrl,
              let url = URL(string: sourceUrl),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return nil
        }
        return url
    }

    fileprivate func handleStartConfirm(gym: WorkoutStartGym, device: WorkoutStartDevice) {
        let handoff = WorkoutStartHandoffResolver.handoff(for: device)
        switch handoff {
        case .garmin:
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
            beginAppleTryHandoff()
        case .phone:
            WorkoutEngine.shared.start(workout: workout)
            showingWorkoutPlayer = true
            handoffStatus = "Recording on Phone — stop anytime, then log sets"
        }
    }

    fileprivate func beginAppleTryHandoff() {
        handoffStatus = appleWatchReachable
            ? "Sending to Apple Watch…"
            : "Saving to Apple Fitness…"
        Task {
            let result = await AppleStartHandoffService().handoff(
                workout: workout,
                watchReachable: appleWatchReachable
            )
            handoffStatus = result.message
        }
    }

    fileprivate func creditOpenIdentifier(for label: String) -> String {
        switch label.lowercased() {
        case let s where s.contains("instagram"): return "af_credit_open_instagram"
        case let s where s.contains("tiktok"): return "af_credit_open_tiktok"
        case let s where s.contains("youtube"): return "af_credit_open_youtube"
        default: return "af_credit_open_external"
        }
    }

    fileprivate func withSavedId(_ id: String) -> Workout {
        Workout(
            id: id,
            name: displayedWorkout.name,
            sport: displayedWorkout.sport,
            duration: displayedWorkout.duration,
            blocks: displayedWorkout.blocks,
            description: displayedWorkout.description,
            source: displayedWorkout.source,
            sourceUrl: displayedWorkout.sourceUrl,
            creatorName: displayedWorkout.creatorName,
            createdAt: displayedWorkout.createdAt
        )
    }
}

#if DEBUG
#Preview("Social") {
    NavigationStack {
        UnifiedWorkoutDetailView(
            workout: Workout(
                name: "DB Full-body AMRAP",
                sport: .cardio,
                duration: 1200,
                blocks: [
                    Block(
                        label: "Round 1–3",
                        structure: .amrap,
                        rounds: 3,
                        exercises: [
                            Exercise(
                                name: "Wall balls",
                                canonicalName: nil,
                                sets: nil,
                                reps: "20",
                                durationSeconds: nil,
                                load: ExerciseLoad(value: 0, unit: "med ball 6 kg"),
                                restSeconds: nil,
                                distance: nil,
                                notes: nil,
                                focus: "Quads · Shoulders",
                                supersetGroup: nil
                            ),
                            Exercise(
                                name: "Barbell thrusters",
                                canonicalName: nil,
                                sets: nil,
                                reps: "12",
                                durationSeconds: nil,
                                load: ExerciseLoad(value: 40, unit: "kg"),
                                restSeconds: nil,
                                distance: nil,
                                notes: nil,
                                focus: "Full body",
                                supersetGroup: nil
                            ),
                            Exercise(
                                name: "Burpee broad jumps",
                                canonicalName: nil,
                                sets: nil,
                                reps: "10",
                                durationSeconds: nil,
                                load: ExerciseLoad(value: 0, unit: "bodyweight"),
                                restSeconds: nil,
                                distance: nil,
                                notes: nil,
                                focus: "Full body",
                                supersetGroup: nil
                            )
                        ]
                    ),
                    Block(
                        label: "Finisher",
                        structure: .circuit,
                        rounds: 1,
                        exercises: [
                            Exercise(
                                name: "Sled push",
                                canonicalName: nil,
                                sets: 2,
                                reps: nil,
                                durationSeconds: nil,
                                load: ExerciseLoad(value: 80, unit: "kg"),
                                restSeconds: nil,
                                distance: 20,
                                notes: nil,
                                focus: "Legs · Core",
                                supersetGroup: nil
                            )
                        ]
                    )
                ],
                description: "Five rounds of full-body conditioning — wall balls, thrusters and jumps, with a sled finisher. Parsed from the reel; nothing saved yet.",
                source: .instagram,
                sourceUrl: "https://instagram.com/reel/abc",
                creatorName: "gospelofgainz"
            ),
            garminPairedOverride: true,
            appleWatchReachableOverride: false
        )
        .environmentObject(WorkoutsViewModel())
    }
}

#Preview("Coach") {
    NavigationStack {
        UnifiedWorkoutDetailView(
            workout: Workout(
                name: "Lower body — posterior",
                sport: .strength,
                duration: 3120,
                blocks: [
                    Block(
                        label: "Main lifts",
                        structure: .straight,
                        rounds: 1,
                        exercises: [
                            Exercise(
                                name: "Back squat",
                                canonicalName: nil,
                                sets: 3,
                                reps: "5",
                                durationSeconds: nil,
                                load: nil,
                                restSeconds: nil,
                                distance: nil,
                                notes: "build to heavy",
                                focus: "Quads · Glutes",
                                supersetGroup: nil
                            ),
                            Exercise(
                                name: "Romanian deadlift",
                                canonicalName: nil,
                                sets: 3,
                                reps: "8",
                                durationSeconds: nil,
                                load: ExerciseLoad(value: 70, unit: "kg"),
                                restSeconds: nil,
                                distance: nil,
                                notes: nil,
                                focus: "Hamstrings · Glutes",
                                supersetGroup: nil
                            )
                        ]
                    ),
                    Block(
                        label: "Accessories",
                        structure: .straight,
                        rounds: 1,
                        exercises: [
                            Exercise(
                                name: "Split squat",
                                canonicalName: nil,
                                sets: 2,
                                reps: "10",
                                durationSeconds: nil,
                                load: nil,
                                restSeconds: nil,
                                distance: nil,
                                notes: nil,
                                focus: "Quads · Glutes",
                                supersetGroup: nil
                            )
                        ]
                    )
                ],
                description: "Posterior-chain strength: squat, hinge, single-leg. From your trainer.",
                source: .coach,
                sourceUrl: "Coach Mike",
                creatorName: "Coach Mike",
                createdAt: Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 1))
            ),
            garminPairedOverride: false,
            appleWatchReachableOverride: false
        )
        .environmentObject(WorkoutsViewModel())
    }
}

#Preview("Manual") {
    NavigationStack {
        UnifiedWorkoutDetailView(
            workout: Workout(
                name: "Hyrox Sim — Stations 1–4",
                sport: .cardio,
                duration: 2700,
                blocks: [
                    Block(
                        label: "Stations 1–4",
                        structure: .circuit,
                        rounds: 2,
                        exercises: [
                            Exercise(
                                name: "SkiErg",
                                canonicalName: nil,
                                sets: nil,
                                reps: nil,
                                durationSeconds: nil,
                                load: nil,
                                restSeconds: nil,
                                distance: 250,
                                notes: "Full body",
                                supersetGroup: nil
                            )
                        ]
                    )
                ],
                description: "Race-pace simulation of the first four stations with run intervals between each.",
                source: .manual
            ),
            garminPairedOverride: false,
            appleWatchReachableOverride: true
        )
        .environmentObject(WorkoutsViewModel())
    }
}
#endif
