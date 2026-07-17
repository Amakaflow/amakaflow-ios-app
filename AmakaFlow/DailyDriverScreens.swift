//
//  DailyDriverScreens.swift
//  AmakaFlow
//
//  Shared Daily Driver screen chrome — Library rows, Today timeline, filters
//  (Daily Driver Proto standalone.html — DDBuildScreen, DDTodayScreen).
//

import SwiftUI

// MARK: - Platform / source

enum DDPlatform: String, CaseIterable, Identifiable {
    case all
    case instagram
    case tiktok
    case manual
    case coach
    case ai

    var id: String { rawValue }

    /// SPEC.md — All · Instagram · TikTok · Manual · Coach (no AI chip in handoff).
    static let filterOrder: [DDPlatform] = [.all, .instagram, .tiktok, .manual, .coach]

    var filterLabel: String {
        switch self {
        case .all: return "All"
        case .instagram: return "Instagram"
        case .tiktok: return "TikTok"
        case .manual: return "Manual"
        case .coach: return "Coach"
        case .ai: return "AI"
        }
    }

    var badgeLabel: String {
        switch self {
        case .all: return "ALL"
        case .instagram: return "INSTAGRAM"
        case .tiktok: return "TIKTOK"
        case .manual: return "MANUAL"
        case .coach: return "COACH"
        case .ai: return "AI"
        }
    }

    var accentColor: Color {
        switch self {
        case .all: return DailyDriver.foregroundMuted
        case .instagram: return DailyDriver.purple
        case .tiktok: return Color(hex: "4AD9D9")
        case .manual: return Color.white.opacity(0.45)
        case .coach: return DailyDriver.orange
        case .ai: return DailyDriver.blue
        }
    }

    var iconName: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .instagram: return "camera.fill"
        case .tiktok: return "play.fill"
        case .manual: return "pencil"
        case .coach: return "person.fill"
        case .ai: return "sparkles"
        }
    }

    static func resolve(source: WorkoutSource, sourceUrl: String?) -> DDPlatform {
        if let url = sourceUrl, !url.isEmpty {
            let platform = SocialImportPlatform.detect(from: url)
            switch platform {
            case .instagram: return .instagram
            case .tiktok: return .tiktok
            default: break
            }
        }

        switch source {
        case .instagram: return .instagram
        case .tiktok: return .tiktok
        case .coach: return .coach
        case .ai, .smartPlanner, .amaka, .suggestionAccepted: return .ai
        case .manual, .gymManualSync, .template, .trainingProgram, .connectedCalendar,
             .garmin, .runna, .stryd, .gymClass, .youtube, .image, .other:
            return .manual
        }
    }

    static func resolve(knowledge item: Components.Schemas.LibraryItem) -> DDPlatform {
        if let url = item.sourceUrl {
            let platform = SocialImportPlatform.detect(from: url)
            switch platform {
            case .instagram: return .instagram
            case .tiktok: return .tiktok
            case .coach: return .coach
            case .ai: return .ai
            default: break
            }
        }
        if let domain = item.sourceDomain?.lowercased() {
            if domain.contains("instagram") { return .instagram }
            if domain.contains("tiktok") { return .tiktok }
        }
        return .manual
    }

    func matches(workout: Workout) -> Bool {
        self == .all || Self.resolve(source: workout.source, sourceUrl: workout.sourceUrl) == self
    }

    func matches(knowledge item: Components.Schemas.LibraryItem) -> Bool {
        self == .all || Self.resolve(knowledge: item) == self
    }
}

// MARK: - Screen header

struct DDScreenHeader: View {
    let title: String
    var trailing: AnyView?

    init(title: String, @ViewBuilder trailing: () -> some View = { EmptyView() }) {
        self.title = title
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .ddDisplayText(32, weight: .heavy)
                .foregroundColor(DailyDriver.foreground)
            Spacer(minLength: 0)
            if let trailing {
                trailing
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

struct DDLibraryHeaderAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(DailyDriver.ink)
                .frame(width: 38, height: 38)
                .background(DailyDriver.lime)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add to Library")
        .accessibilityIdentifier("af_library_add")
    }
}

// MARK: - Search + filter pills

struct DDSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search workouts, creators…"

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(DailyDriver.foregroundDim)
            TextField(placeholder, text: $text)
                .font(Theme.Typography.body)
                .foregroundColor(DailyDriver.foreground)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(DailyDriver.card)
        .overlay(
            Capsule(style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(Capsule(style: .continuous))
    }
}

struct DDSourceFilterPills: View {
    @Binding var selection: DDPlatform

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(DDPlatform.filterOrder) { platform in
                    Button {
                        selection = platform
                    } label: {
                        Text(platform.filterLabel)
                            .ddDisplayText(12.5, weight: .semibold)
                            .foregroundColor(selection == platform ? DailyDriver.ink : DailyDriver.foregroundMuted)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 8)
                            .background(selection == platform ? DailyDriver.lime : DailyDriver.card)
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(selection == platform ? Color.clear : DailyDriver.border, lineWidth: 1)
                            )
                            .clipShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(accessibilityID(for: platform))
                    .accessibilityAddTraits(selection == platform ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func accessibilityID(for platform: DDPlatform) -> String {
        switch platform {
        case .all: return "af_library_kind_all"
        case .manual: return "af_library_kind_workout"
        case .instagram: return "af_library_source_instagram"
        case .tiktok: return "af_library_source_tiktok"
        case .coach: return "af_library_source_coach"
        case .ai: return "af_library_source_ai"
        }
    }
}

// MARK: - Library row

struct DDLibraryRow: View {
    let title: String
    let metaLine: String
    let platform: DDPlatform
    let thumbIcon: String
    let gradientColors: [Color]

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                Image(systemName: thumbIcon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .ddDisplayText(15, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                    .lineLimit(1)

                Text(metaLine)
                    .font(.system(size: 10.5))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .padding(.top, 3)

                DDPlatformBadge(platform: platform)
                    .padding(.top, 6)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DailyDriver.foregroundDim)
        }
        .padding(10)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct DDPlatformBadge: View {
    let platform: DDPlatform

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: platform.iconName)
                .font(.system(size: 9, weight: .bold))
            Text(platform.badgeLabel)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
        }
        .foregroundColor(platform.accentColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(platform.accentColor.opacity(0.16))
        .clipShape(Capsule())
    }
}

// MARK: - Today — watch pill + day scrubber + timeline

struct DDWatchReadinessPill: View {
    var isConnected: Bool
    /// Proto shows watch battery % (dd-today-dark.png); use 78 when live data unavailable.
    var batteryPercent: Int? = nil

    private var displayBattery: String {
        if let batteryPercent {
            return "\(batteryPercent)%"
        }
        return isConnected ? "78%" : "—"
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isConnected ? DailyDriver.lime : DailyDriver.foregroundDim)
                .frame(width: 6, height: 6)
            Image(systemName: "applewatch")
                .font(.system(size: 13, weight: .semibold))
            Text(displayBattery)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .foregroundColor(DailyDriver.foreground)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(DailyDriver.card)
        .overlay(
            Capsule(style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(Capsule(style: .continuous))
        .accessibilityIdentifier("af_today_watch_pill")
    }
}

struct DDDayScrubber: View {
    let days: [DDScrubberDay]
    @Binding var selectedIndex: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                Button {
                    if day.isSelectable {
                        selectedIndex = index
                    }
                } label: {
                    VStack(spacing: 2) {
                        Text(day.weekdayLabel)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(DailyDriver.foregroundMuted)
                        Text("\(day.dayNumber)")
                            .ddDisplayText(13, weight: .bold)
                            .foregroundColor(day.isToday ? DailyDriver.foreground : DailyDriver.foregroundMuted)
                        Circle()
                            .fill(dotColor(for: day))
                            .frame(width: 4, height: 4)
                            .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(day.isToday ? DailyDriver.card2 : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(day.isToday ? DailyDriver.border.opacity(0.9) : Color.clear, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .opacity(day.isFuture ? 0.4 : 1)
                }
                .buttonStyle(.plain)
                .disabled(!day.isSelectable && !day.isToday)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
    }

    private func dotColor(for day: DDScrubberDay) -> Color {
        if day.isToday {
            return day.hasActivity ? DailyDriver.lime : DailyDriver.foregroundDim
        }
        return day.hasActivity ? DailyDriver.lime : .clear
    }
}

struct DDScrubberDay: Identifiable {
    let id: Date
    let weekdayLabel: String
    let dayNumber: Int
    let isToday: Bool
    let isFuture: Bool
    let hasActivity: Bool

    var isSelectable: Bool {
        hasActivity && !isToday && !isFuture
    }
}

struct DDTimelineCard: View {
    let icon: String
    let iconBackground: Color
    let time: String
    var title: String?
    var label: String?
    var stats: [(icon: String, value: String)] = []
    var sourceLabel: String?
    var showsChevron: Bool = false
    var trailingAction: AnyView?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(iconBackground)
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                }
                Rectangle()
                    .fill(DailyDriver.border)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                    .padding(.top, 4)
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(time)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundMuted)
                    if let label {
                        Text(label)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(DailyDriver.foregroundDim)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 8)

                if let title {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(title)
                                .ddDisplayText(15, weight: .bold)
                                .foregroundColor(DailyDriver.foreground)
                            Spacer(minLength: 0)
                            if showsChevron {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(DailyDriver.foregroundDim)
                            }
                        }

                        if !stats.isEmpty {
                            HStack(spacing: 12) {
                                ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                                    HStack(spacing: 4) {
                                        Image(systemName: stat.icon)
                                            .font(.system(size: 11))
                                        Text(stat.value)
                                    }
                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                    .foregroundColor(DailyDriver.foregroundMuted)
                                }
                            }
                            .padding(.top, 6)
                        }

                        HStack(spacing: 8) {
                            if let sourceLabel {
                                Text(sourceLabel.uppercased())
                                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(DailyDriver.foregroundMuted)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(DailyDriver.card2)
                                    .clipShape(Capsule())
                            }
                            Spacer(minLength: 0)
                            if let trailingAction {
                                trailingAction
                            }
                        }
                        .padding(.top, 10)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(DailyDriver.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(DailyDriver.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.bottom, 18)
                } else {
                    Spacer(minLength: 22)
                }
            }
        }
    }
}

// MARK: - Library / workout presentation helpers

enum DDLibraryPresentation {
    static func row(for workout: Workout) -> (meta: String, platform: DDPlatform, icon: String, gradient: [Color]) {
        (
            metaLine(for: workout),
            DDPlatform.resolve(source: workout.source, sourceUrl: workout.sourceUrl),
            thumbIcon(for: workout),
            gradientColors(for: workout)
        )
    }

    static func row(for knowledge: Components.Schemas.LibraryItem) -> (meta: String, platform: DDPlatform, icon: String, gradient: [Color]) {
        let platform = DDPlatform.resolve(knowledge: knowledge)
        let creator = knowledge.sourceDomain ?? "saved"
        let kind = knowledge.kind.rawValue.capitalized
        return ("\(kind) · by \(creator)", platform, kindIcon(knowledge.kind), gradientForPlatform(platform))
    }

    static func matchesSearch(_ query: String, title: String, creator: String) -> Bool {
        guard !query.isEmpty else { return true }
        let q = query.lowercased()
        return title.lowercased().contains(q) || creator.lowercased().contains(q)
    }

    private static func metaLine(for workout: Workout) -> String {
        let minutes = max(1, workout.duration / 60)
        let creator = creatorLabel(for: workout)
        if workout.blockCount > 0 {
            return "\(workout.blockCount) blocks · \(minutes) min · by \(creator)"
        }
        if workout.exerciseCount > 0 {
            return "\(workout.exerciseCount) exercises · \(minutes) min · by \(creator)"
        }
        return "\(minutes) min · by \(creator)"
    }

    static func creatorLabel(for workout: Workout) -> String {
        if let handle = workout.sourceUrl?.trimmingCharacters(in: .whitespacesAndNewlines), handle.hasPrefix("@") {
            return String(handle.dropFirst())
        }
        switch workout.source {
        case .ai, .smartPlanner, .amaka, .suggestionAccepted:
            return "AmakaFlow AI"
        case .coach:
            if let url = workout.sourceUrl, !url.isEmpty { return url }
            return "Coach"
        case .manual, .gymManualSync:
            return "you"
        default:
            if let url = workout.sourceUrl, let host = URL(string: url)?.host {
                return host.replacingOccurrences(of: "www.", with: "")
            }
            return "you"
        }
    }

    private static func thumbIcon(for workout: Workout) -> String {
        switch workout.sport {
        case .running: return "figure.run"
        case .cycling: return "bicycle"
        case .strength: return "dumbbell.fill"
        case .mobility: return "figure.flexibility"
        case .swimming: return "figure.pool.swim"
        case .cardio: return "flame.fill"
        case .other: return "bolt.fill"
        }
    }

    private static func gradientColors(for workout: Workout) -> [Color] {
        gradientForPlatform(DDPlatform.resolve(source: workout.source, sourceUrl: workout.sourceUrl))
    }

    private static func gradientForPlatform(_ platform: DDPlatform) -> [Color] {
        switch platform {
        case .instagram: return [Color(hex: "3A1145"), Color(hex: "12041A")]
        case .tiktok: return [Color(hex: "0D3830"), Color(hex: "04140F")]
        case .coach: return [Color(hex: "33240A"), Color(hex: "120C03")]
        case .ai: return [Color(hex: "101C30"), Color(hex: "060A12")]
        case .manual, .all: return [Color(hex: "2A3505"), Color(hex: "0F1202")]
        }
    }

    private static func kindIcon(_ kind: Components.Schemas.LibraryKind) -> String {
        switch kind {
        case .workout: return "flame.fill"
        case .video: return "play.fill"
        case .article: return "doc.text.fill"
        case .plan: return "calendar"
        }
    }
}

extension WorkoutCompletion {
    var ddTimeRange: String {
        let start = startedAt.formatted(date: .omitted, time: .shortened)
        let end = resolvedEndedAt.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }

    var ddTimelineStats: [(icon: String, value: String)] {
        var stats: [(icon: String, value: String)] = []
        let minutes = max(1, durationSeconds / 60)
        stats.append((icon: "clock", value: "\(minutes)M"))
        if let cal = activeCalories {
            stats.append((icon: "flame.fill", value: "\(cal) CAL"))
        }
        if let hr = avgHeartRate {
            stats.append((icon: "heart.fill", value: "\(hr) BPM"))
        }
        return stats
    }

    var ddTimelineIcon: (name: String, background: Color) {
        let lowered = workoutName.lowercased()
        if lowered.contains("run") {
            return ("figure.run", DailyDriver.blue)
        }
        if lowered.contains("workout") || lowered.contains("strength") || lowered.contains("lift") {
            return ("dumbbell.fill", DailyDriver.card2)
        }
        if source == .garmin || source == .appleWatch {
            return ("flame.fill", DailyDriver.lime)
        }
        return ("figure.strengthtraining.traditional", DailyDriver.card2)
    }

    var ddSourceCaption: String {
        if isSyncedToStrava {
            return "Imported from Strava"
        }
        switch source {
        case .garmin: return "Synced from Garmin"
        case .appleWatch: return "Apple Watch session"
        case .phone: return "Phone session"
        case .manual: return "Manual entry"
        }
    }

    /// Sparse Strava pull — show “What was this?” instead of Log RPE (dd-today-dark.png).
    var ddNeedsActivityMapping: Bool {
        workoutId == nil
            && distanceMeters == nil
            && avgHeartRate == nil
            && durationSeconds < 20 * 60
    }

    var ddTimelineTitle: String {
        if let meters = distanceMeters, meters >= 1000 {
            let km = String(format: "%.1f", Double(meters) / 1000)
            if workoutName.localizedCaseInsensitiveContains("run") {
                return "\(workoutName) / \(km) km"
            }
            return "\(workoutName) / \(km) km"
        }
        return workoutName
    }
}

// MARK: - Workout detail block grouping (DDDetailScreen)

struct DDWorkoutDisplaySection: Identifiable {
    let id: String
    let title: String
    let note: String
    let exercises: [Exercise]
}

enum DDWorkoutDisplayGrouping {
    /// Collapse consecutive single-exercise blocks into one section (proto "Main lifts" card).
    static func sections(for workout: Workout) -> [DDWorkoutDisplaySection] {
        guard !workout.blocks.isEmpty else { return [] }

        var sections: [DDWorkoutDisplaySection] = []
        var singletonRun: [Block] = []
        let totalExercises = max(1, workout.exerciseCount)

        func explicitTitle(for block: Block, fallbackIndex: Int) -> String {
            if let trimmed = block.label?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
                return trimmed
            }
            switch block.structure {
            case .amrap: return "AMRAP"
            case .emom: return "EMOM"
            case .tabata: return "Tabata"
            case .superset: return "Superset"
            default: return fallbackIndex == 0 ? "Main block" : "Block \(fallbackIndex + 1)"
            }
        }

        func isMergeableSingleton(_ block: Block) -> Bool {
            guard block.exercises.count == 1 else { return false }
            if let label = block.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
                // Legacy/manual saves often auto-label each exercise "Block N" — still merge.
                return label.range(of: #"^Block \d+$"#, options: .regularExpression) != nil
            }
            return true
        }

        func durationShare(for exerciseCount: Int) -> Int {
            let ratio = Double(exerciseCount) / Double(totalExercises)
            return max(60, Int(Double(workout.duration) * ratio))
        }

        func appendSection(title: String, blocks: [Block]) {
            let exercises = blocks.flatMap(\.exercises)
            guard !exercises.isEmpty else { return }
            let rounds = blocks.first?.rounds ?? 1
            let seconds = durationShare(for: exercises.count)
            let note = sectionNote(exerciseCount: exercises.count, rounds: rounds, durationSeconds: seconds)
            sections.append(
                DDWorkoutDisplaySection(
                    id: "\(title)-\(sections.count)-\(blocks.first?.id ?? UUID().uuidString)",
                    title: title,
                    note: note,
                    exercises: exercises
                )
            )
        }

        func flushSingletonRun() {
            guard !singletonRun.isEmpty else { return }
            let title = sections.isEmpty ? "Main block" : "Block \(sections.count + 1)"
            appendSection(title: title, blocks: singletonRun)
            singletonRun = []
        }

        for block in workout.blocks {
            if isMergeableSingleton(block) {
                singletonRun.append(block)
            } else {
                flushSingletonRun()
                appendSection(title: explicitTitle(for: block, fallbackIndex: sections.count), blocks: [block])
            }
        }
        flushSingletonRun()

        return sections
    }

    private static func sectionNote(exerciseCount: Int, rounds: Int, durationSeconds: Int) -> String {
        let minutes = max(1, durationSeconds / 60)
        if exerciseCount > 1 && rounds <= 1 {
            return "~\(minutes) min"
        }
        if rounds > 1 {
            return "\(rounds) rounds · ~\(minutes) min"
        }
        if exerciseCount > 1 {
            return "\(exerciseCount) exercises · ~\(minutes) min"
        }
        return "~\(minutes) min"
    }
}

struct DDWorkoutBlockSectionView: View {
    let section: DDWorkoutDisplaySection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(section.title)
                    .ddDisplayText(14.5, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                Spacer(minLength: 0)
                Text(section.note.uppercased())
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundMuted)
            }

            VStack(spacing: 0) {
                ForEach(Array(section.exercises.enumerated()), id: \.element.id) { index, exercise in
                    HStack(spacing: 11) {
                        DDIconChip(systemName: "dumbbell.fill", background: DailyDriver.card2, size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name)
                                .ddDisplayText(13.5, weight: .semibold)
                                .foregroundColor(DailyDriver.foreground)
                            Text(exercise.ddDetailLine)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(DailyDriver.foregroundMuted)
                        }
                        Spacer(minLength: 0)
                        if let hint = exercise.ddMuscleHint {
                            Text(hint)
                                .font(.system(size: 9.5))
                                .foregroundColor(DailyDriver.foregroundDim)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    .padding(.vertical, 11)

                    if index < section.exercises.count - 1 {
                        Divider()
                            .overlay(DailyDriver.card2)
                    }
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 2)
            .background(DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DailyDriver.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

extension Exercise {
    var ddDetailLine: String {
        var parts: [String] = []
        if let sets, let reps {
            parts.append("\(sets) × \(reps)")
        } else if let reps {
            parts.append("\(reps) reps")
        } else if let durationSeconds {
            parts.append(durationSeconds >= 60 ? "\(durationSeconds / 60) min" : "\(durationSeconds) sec")
        } else if let distance {
            parts.append(distance >= 1000 ? String(format: "%.1f km", distance / 1000) : "\(Int(distance)) m")
        }

        if let load {
            if load.value > 0 {
                if load.unit == "bodyweight" {
                    parts.append("bodyweight")
                } else {
                    let valueText = load.value.truncatingRemainder(dividingBy: 1) == 0
                        ? String(Int(load.value))
                        : String(load.value)
                    let unit = load.unit.trimmingCharacters(in: .whitespacesAndNewlines)
                    parts.append(unit.isEmpty ? valueText : "\(valueText) \(unit)")
                }
            } else if !load.unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append(load.unit)
            }
        }

        if let notes {
            let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !Exercise.looksLikeMuscleFocus(trimmed) {
                parts.append(trimmed)
            }
        }

        return parts.joined(separator: " · ").uppercased()
    }

    var ddMuscleHint: String? {
        if let focus {
            let trimmed = focus.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let notes {
            let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, Exercise.looksLikeMuscleFocus(trimmed) {
                return trimmed
            }
        }
        return nil
    }
}

extension Array where Element == WorkoutCompletion {
    func scrubberDays(calendar: Calendar = .current, now: Date = Date()) -> [DDScrubberDay] {
        let today = calendar.startOfDay(for: now)
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) else {
            return []
        }

        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            let dayNumber = calendar.component(.day, from: date)
            let weekday = date.formatted(.dateTime.weekday(.narrow)).uppercased()
            let hasActivity = contains { calendar.isDate($0.startedAt, inSameDayAs: date) }
            return DDScrubberDay(
                id: date,
                weekdayLabel: weekday,
                dayNumber: dayNumber,
                isToday: calendar.isDate(date, inSameDayAs: today),
                isFuture: date > today,
                hasActivity: hasActivity
            )
        }
    }
}
