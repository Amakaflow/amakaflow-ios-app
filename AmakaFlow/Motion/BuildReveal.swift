//
//  BuildReveal.swift
//  AmakaFlow
//
//  AMA-2383 — "it writes itself" build reveal engine. Script-driven beats;
//  text wipe via mask + width (not fade). Spec: design-handoff/MOTION.md §2
//  Reference: design-handoff/reference/screens-motion.jsx (SMBuildScreen)
//

// swiftlint:disable file_length

import Combine
import SwiftUI
import UIKit

// MARK: - Beats

enum BuildBeatKind: Equatable {
    case band
    case row
    case bullet
    case credit
    case pills
}

struct BuildBeat: Identifiable, Equatable {
    let id: UUID
    let kind: BuildBeatKind
    var label: String?
    var tag: String?
    var color: Color?
    var name: String?
    var detail: String?
    var chip: String?
    var chipAmber: Bool
    var open: Bool
    var initial: String?
    var creditBackground: Color?
    var pills: [String]

    init(
        id: UUID = UUID(),
        kind: BuildBeatKind,
        label: String? = nil,
        tag: String? = nil,
        color: Color? = nil,
        name: String? = nil,
        detail: String? = nil,
        chip: String? = nil,
        chipAmber: Bool = false,
        open: Bool = false,
        initial: String? = nil,
        creditBackground: Color? = nil,
        pills: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.tag = tag
        self.color = color
        self.name = name
        self.detail = detail
        self.chip = chip
        self.chipAmber = chipAmber
        self.open = open
        self.initial = initial
        self.creditBackground = creditBackground
        self.pills = pills
    }

    /// Color is not reliably Equatable across SwiftUI versions — compare
    /// identity + content fields only.
    static func == (lhs: BuildBeat, rhs: BuildBeat) -> Bool {
        lhs.id == rhs.id
            && lhs.kind == rhs.kind
            && lhs.label == rhs.label
            && lhs.tag == rhs.tag
            && lhs.name == rhs.name
            && lhs.detail == rhs.detail
            && lhs.chip == rhs.chip
            && lhs.chipAmber == rhs.chipAmber
            && lhs.open == rhs.open
            && lhs.initial == rhs.initial
            && lhs.pills == rhs.pills
    }

    /// Counts toward COMPOSING… n OF m (rows + bullets only).
    var countsTowardProgress: Bool {
        kind == .row || kind == .bullet
    }

    static func band(_ label: String, tag: String, color: Color) -> BuildBeat {
        BuildBeat(kind: .band, label: label, tag: tag, color: color)
    }

    static func row(_ name: String, detail: String, chip: String? = nil, chipAmber: Bool = false, open: Bool = false) -> BuildBeat {
        BuildBeat(kind: .row, name: name, detail: detail, chip: chip, chipAmber: chipAmber, open: open)
    }

    static func bullet(_ detail: String) -> BuildBeat {
        BuildBeat(kind: .bullet, detail: detail)
    }

    static func credit(initial: String, name: String, sub: String, background: Color) -> BuildBeat {
        BuildBeat(kind: .credit, name: name, detail: sub, initial: initial, creditBackground: background)
    }

    static func pills(_ pills: [String]) -> BuildBeat {
        BuildBeat(kind: .pills, pills: pills)
    }
}

struct BuildRevealConfig: Equatable {
    var title: String
    var verb: String
    var doneNote: String
    var cta: String
    var building: String
    var beats: [BuildBeat] // mutated when streaming appends beats

    var progressTotal: Int {
        beats.filter(\.countsTowardProgress).count
    }
}

// MARK: - Controller

@MainActor
final class BuildRevealController: ObservableObject {
    @Published private(set) var visibleCount: Int = 0
    @Published private(set) var isDone: Bool = false
    @Published private(set) var runID: Int = 0

    private(set) var config: BuildRevealConfig
    private var scriptTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?
    private var reduceMotion: Bool = false

    init(config: BuildRevealConfig) {
        self.config = config
    }

    var shownBeats: [BuildBeat] {
        Array(config.beats.prefix(visibleCount))
    }

    var progressShown: Int {
        shownBeats.filter(\.countsTowardProgress).count
    }

    var statusLine: String {
        if isDone {
            return "READY · \(config.doneNote)"
        }
        return "\(config.verb)… \(progressShown) OF \(config.progressTotal)"
    }

    /// Replace beats (e.g. when wiring a live workout) and reset.
    func updateConfig(_ config: BuildRevealConfig) {
        cancelPlayback()
        self.config = config
        visibleCount = 0
        isDone = false
    }

    /// Scripted playback with theatrical cap. Skips entirely under Reduce Motion /
    /// VoiceOver (full content immediately).
    func playScripted(reduceMotion: Bool, voiceOverRunning: Bool? = nil) {
        let voiceOverActive = voiceOverRunning ?? UIAccessibility.isVoiceOverRunning
        self.reduceMotion = reduceMotion || voiceOverActive
        cancelPlayback()
        runID += 1
        let thisRun = runID

        if self.reduceMotion {
            visibleCount = config.beats.count
            isDone = true
            return
        }

        visibleCount = 0
        isDone = false
        let stagger = MotionTokens.cappedStagger(beatCount: config.beats.count)
        let total = config.beats.count

        scriptTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(MotionTokens.buildKick * 1_000_000_000))
            guard !Task.isCancelled, runID == thisRun else { return }
            for beatIndex in 1...max(total, 1) where total > 0 {
                guard !Task.isCancelled, runID == thisRun else { return }
                withAnimation(MotionTokens.easeOutQuart(duration: MotionTokens.base)) {
                    visibleCount = beatIndex
                }
                if beatIndex < total {
                    try? await Task.sleep(nanoseconds: UInt64(stagger * 1_000_000_000))
                }
            }
            try? await Task.sleep(nanoseconds: UInt64(MotionTokens.buildDoneSettle * 1_000_000_000))
            guard !Task.isCancelled, runID == thisRun else { return }
            isDone = true
        }
    }

    /// Honest-progress: reveal exactly one more beat (SSE chunk / parse block).
    func revealNext() {
        guard visibleCount < config.beats.count else {
            isDone = true
            return
        }
        withAnimation(MotionTokens.easeOutQuart(duration: MotionTokens.base)) {
            visibleCount += 1
        }
        if visibleCount >= config.beats.count {
            settleTask?.cancel()
            runID += 1
            let thisRun = runID
            settleTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(MotionTokens.buildDoneSettle * 1_000_000_000))
                guard !Task.isCancelled, runID == thisRun else { return }
                isDone = true
            }
        }
    }

    /// Append a beat that just arrived from the stream, then reveal it.
    func appendAndReveal(_ beat: BuildBeat) {
        config.beats.append(beat)
        revealNext()
    }

    func markDone() {
        visibleCount = config.beats.count
        isDone = true
    }

    func replay(reduceMotion: Bool) {
        playScripted(reduceMotion: reduceMotion)
    }

    private func cancelPlayback() {
        scriptTask?.cancel()
        scriptTask = nil
        settleTask?.cancel()
        settleTask = nil
    }
}

// MARK: - Assembled render tree

enum BuildRevealElement: Identifiable, Equatable {
    case credit(BuildBeat)
    case pills(BuildBeat)
    case bullet(BuildBeat)
    case band(band: BuildBeat, rows: [BuildBeat])

    var id: UUID {
        switch self {
        case .credit(let beat), .pills(let beat), .bullet(let beat): return beat.id
        case .band(let band, _): return band.id
        }
    }

    static func assemble(from beats: [BuildBeat]) -> [BuildRevealElement] {
        var out: [BuildRevealElement] = []
        for beat in beats {
            switch beat.kind {
            case .band:
                out.append(.band(band: beat, rows: []))
            case .row:
                if case .band(let band, var rows) = out.last {
                    rows.append(beat)
                    out[out.count - 1] = .band(band: band, rows: rows)
                } else {
                    // Orphan row — wrap in a transparent band
                    out.append(.band(band: BuildBeat(kind: .band, label: "", tag: "", color: .clear), rows: [beat]))
                }
            case .bullet:
                out.append(.bullet(beat))
            case .credit:
                out.append(.credit(beat))
            case .pills:
                out.append(.pills(beat))
            }
        }
        return out
    }
}

// MARK: - Wipe text (mask width — the "being written" read)

struct BuildWipeText: View {
    let text: String
    var font: Font = .system(size: 8, weight: .semibold, design: .monospaced)
    var color: Color = DailyDriver.foregroundDim
    var reduceMotion: Bool = false
    @State private var progress: CGFloat = 0

    var body: some View {
        Text(text)
            .font(font)
            .foregroundColor(color)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .mask(alignment: .leading) {
                GeometryReader { geo in
                    Rectangle()
                        .frame(width: max(0, geo.size.width * progress))
                }
            }
            .onAppear {
                if reduceMotion {
                    progress = 1
                } else {
                    progress = 0
                    withAnimation(
                        MotionTokens.easeOutQuart(duration: MotionTokens.wipeDuration)
                            .delay(MotionTokens.wipeDelay)
                    ) {
                        progress = 1
                    }
                }
            }
    }
}

// MARK: - Screen

struct BuildRevealView: View {
    @ObservedObject var controller: BuildRevealController
    var onCTA: () -> Void
    var showReplay: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let elements = BuildRevealElement.assemble(from: controller.shownBeats)
        VStack(alignment: .leading, spacing: 0) {
            header
            statusLine
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(elements.enumerated()), id: \.element.id) { _, element in
                            elementView(element)
                                .id(element.id)
                        }
                        Color.clear.frame(height: 1).id("build_reveal_bottom")
                    }
                    .padding(.bottom, 110)
                }
                .onChange(of: controller.visibleCount) { _, _ in
                    withAnimation(MotionTokens.easeOutQuart(duration: MotionTokens.fast)) {
                        proxy.scrollTo("build_reveal_bottom", anchor: .bottom)
                    }
                }
            }

            ctaButton
        }
        .onAppear {
            controller.playScripted(reduceMotion: reduceMotion)
        }
        .accessibilityIdentifier("dd_build_reveal")
    }

    private var header: some View {
        HStack {
            Text(controller.config.title)
                .ddDisplayText(17, weight: .bold)
                .foregroundColor(DailyDriver.foreground)
            Spacer(minLength: 0)
            if showReplay {
                Button("↺ Replay") {
                    controller.replay(reduceMotion: reduceMotion)
                }
                .ddDisplayText(11.5, weight: .bold)
                .foregroundColor(DailyDriver.foregroundMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(DailyDriver.card2)
                .clipShape(Capsule())
                .buttonStyle(.plain)
            }
        }
    }

    private var statusLine: some View {
        HStack(spacing: 0) {
            Text(controller.statusLine)
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .foregroundColor(controller.isDone ? DailyDriver.lime : DailyDriver.foregroundDim)
            if !controller.isDone {
                BuildCaret()
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 12)
        .accessibilityIdentifier("dd_build_status")
    }

    @ViewBuilder
    private func elementView(_ element: BuildRevealElement) -> some View {
        switch element {
        case .credit(let beat):
            creditCard(beat)
        case .pills(let beat):
            pillsRow(beat)
        case .bullet(let beat):
            bulletRow(beat)
        case .band(let band, let rows):
            bandBlock(band: band, rows: rows)
        }
    }

    private func creditCard(_ beat: BuildBeat) -> some View {
        HStack(spacing: 10) {
            Text(beat.initial ?? "?")
                .ddDisplayText(13, weight: .heavy)
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(beat.creditBackground ?? DailyDriver.purple)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(beat.name ?? "")
                    .ddDisplayText(12.5, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                if let detail = beat.detail {
                    BuildWipeText(text: detail, reduceMotion: reduceMotion)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(DailyDriver.card)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DailyDriver.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.bottom, 10)
        .transition(.opacity.combined(with: .offset(y: 10)))
    }

    private func pillsRow(_ beat: BuildBeat) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(beat.pills.enumerated()), id: \.offset) { index, pill in
                Text(pill)
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(DailyDriver.card2)
                    .clipShape(Capsule())
                    .modifier(PopOnAppear(delay: Double(index) * 0.07, reduceMotion: reduceMotion))
            }
        }
        .padding(.bottom, 10)
    }

    private func bulletRow(_ beat: BuildBeat) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(DailyDriver.lime)
                .frame(width: 5, height: 5)
                .padding(.top, 6)
            BuildWipeText(
                text: beat.detail ?? "",
                font: .system(size: 11.5),
                color: DailyDriver.foreground,
                reduceMotion: reduceMotion
            )
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 6)
    }

    private func bandBlock(band: BuildBeat, rows: [BuildBeat]) -> some View {
        VStack(spacing: 0) {
            if !(band.label ?? "").isEmpty {
                HStack(spacing: 8) {
                    Text(band.label ?? "")
                        .ddDisplayText(12, weight: .bold)
                        .foregroundColor(DailyDriver.foreground)
                    Spacer(minLength: 0)
                    if let tag = band.tag {
                        Text(tag)
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundColor(DailyDriver.foregroundDim)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background((band.color ?? DailyDriver.lime).opacity(0.16))
                .overlay(
                    Rectangle().stroke((band.color ?? DailyDriver.lime).opacity(0.4), lineWidth: 1)
                )
            }

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                rowView(row, number: index + 1, isLast: index == rows.count - 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.vertical, 5)
        .transition(.opacity.combined(with: .offset(y: 10)))
    }

    private func rowView(_ row: BuildBeat, number: Int, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .ddDisplayText(12, weight: .bold)
                .foregroundColor(DailyDriver.ink)
                .frame(width: 22, height: 22)
                .background(DailyDriver.lime)
                .clipShape(Circle())
                .modifier(PopOnAppear(delay: 0, reduceMotion: reduceMotion))

            VStack(alignment: .leading, spacing: 2) {
                Text(row.name ?? "")
                    .ddDisplayText(13, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                if let detail = row.detail {
                    BuildWipeText(text: detail, reduceMotion: reduceMotion)
                }
            }
            Spacer(minLength: 0)
            if let chip = row.chip {
                Text(chip)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(row.chipAmber ? DailyDriver.ink : DailyDriver.foregroundMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(row.chipAmber ? DailyDriver.amber : DailyDriver.card2)
                    .clipShape(Capsule())
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DailyDriver.card)
        .overlay(alignment: .bottom) {
            if !isLast {
                DailyDriver.border.frame(height: 1)
            }
        }
    }

    private var ctaButton: some View {
        Button(
            action: {
                guard controller.isDone else { return }
                onCTA()
            },
            label: {
                Text(controller.isDone ? controller.config.cta : controller.config.building)
                    .ddDisplayText(14, weight: .bold)
                    .foregroundColor(controller.isDone ? DailyDriver.ink : DailyDriver.foregroundMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(controller.isDone ? DailyDriver.lime : DailyDriver.card2)
                    .clipShape(Capsule())
                    .opacity(controller.isDone ? 1 : 0.55)
            }
        )
        .buttonStyle(.plain)
        .disabled(!controller.isDone)
        .animation(MotionTokens.easeOutQuart(duration: MotionTokens.ctaColorSettle), value: controller.isDone)
        .modifier(CTALandPulse(active: controller.isDone, reduceMotion: reduceMotion))
        .accessibilityIdentifier("dd_build_cta")
        .padding(.top, 8)
    }
}

private struct PopOnAppear: ViewModifier {
    let delay: Double
    let reduceMotion: Bool
    @State private var didPop = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(reduceMotion || didPop ? 1 : 0.55)
            .onAppear {
                guard !reduceMotion else {
                    didPop = true
                    return
                }
                withAnimation(MotionTokens.spring.delay(delay)) {
                    didPop = true
                }
            }
    }
}

private struct BuildCaret: View {
    @State private var caretVisible = true
    var body: some View {
        Text("▍")
            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
            .foregroundColor(DailyDriver.lime)
            .opacity(caretVisible ? 1 : 0)
            .onAppear {
                withAnimation(.linear(duration: 0.7).repeatForever(autoreverses: true)) {
                    caretVisible.toggle()
                }
            }
    }
}

private struct CTALandPulse: ViewModifier {
    let active: Bool
    let reduceMotion: Bool
    @State private var pulsed = false

    func body(content: Content) -> some View {
        content
            .offset(y: active && !pulsed && !reduceMotion ? 14 : 0)
            .shadow(
                color: active ? DailyDriver.lime.opacity(pulsed || reduceMotion ? 0.55 : 0.85) : .clear,
                radius: active && !pulsed && !reduceMotion ? 18 : 11
            )
            .onChange(of: active) { _, isActive in
                guard isActive, !reduceMotion else { return }
                pulsed = false
                withAnimation(MotionTokens.spring) {
                    pulsed = true
                }
            }
    }
}

// MARK: - Script builders from live data

enum BuildRevealScripts {
    static let watchVerb = "COMPOSING"
    static let watchDoneNote = "PREP + RAMPS + COOLDOWN"
    static let watchCTA = "Schedule on the watch"
    static let watchBuilding = "Composing…"

    static let importVerb = "PARSING"
    static let importDoneNote = "FROM THE REEL — NOTHING SAVED YET"
    static let importCTA = "Check the structure"
    static let importBuilding = "Parsing the reel…"

    static let aiVerb = "DRAFTING"
    static let aiDoneNote = "DRAFT · NOT SAVED — REFINE OR COMMIT"
    static let aiCTA = "Save to Library"
    static let aiBuilding = "Drafting…"

    /// Map Apple Watch preview sections into a build script (local data → cap ≤2s).
    static func watchPreview(
        title: String = "To your Apple Watch",
        sections: [PreviewSection]
    ) -> BuildRevealConfig {
        var beats: [BuildBeat] = []
        for section in sections {
            let color: Color = {
                switch section.accent {
                case .mobility: return DailyDriver.mobilityBand
                case .cooldown: return DailyDriver.blue
                case .work: return DailyDriver.lime
                }
            }()
            beats.append(.band(section.band, tag: section.tag ?? "", color: color))
            for step in section.steps {
                beats.append(.row(
                    step.title,
                    detail: step.detail ?? "",
                    chip: step.restChip,
                    chipAmber: step.isOpenRest,
                    open: step.isOpenGoal
                ))
            }
        }
        return BuildRevealConfig(
            title: title,
            verb: watchVerb,
            doneNote: watchDoneNote,
            cta: watchCTA,
            building: watchBuilding,
            beats: beats
        )
    }

    /// Reel/social import — credit first, then pills, then one band per block.
    /// Amber SWAP chips when equipment is empty and the row looks barbell/sled-bound.
    static func importFromDraft(_ draft: SocialImportDraft) -> BuildRevealConfig {
        var beats: [BuildBeat] = []

        if let prov = draft.postProvenance {
            let name = prov.creatorDisplay
            let stripped = name.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            let initial = String(stripped.prefix(1)).lowercased()
            beats.append(.credit(
                initial: initial.isEmpty ? "?" : initial,
                name: name,
                sub: "REEL CAPTION + VIDEO PARSED",
                background: DailyDriver.purple
            ))
        }

        var pills = ["FROM \(draft.platform.displayName.uppercased())"]
        let exerciseCount = draft.blocks.reduce(0) { $0 + $1.exercises.count }
        if exerciseCount > 0 {
            pills.append("\(exerciseCount) EXERCISES")
        }
        if draft.blocks.contains(where: { $0.rounds > 1 }) {
            let rounds = draft.blocks.map(\.rounds).max() ?? 1
            pills.append("\(rounds) ROUNDS")
        }
        beats.append(.pills(pills))

        for block in draft.blocks {
            let label = (block.label?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                ?? block.type?.uppercased()
                ?? "BLOCK"
            let tag: String = {
                if block.rounds > 1 { return "\(block.rounds) ROUNDS" }
                return "\(block.exercises.count) MOVES"
            }()
            let color: Color = {
                switch block.enrichmentKind {
                case "session_warmup": return DailyDriver.mobilityBand
                case "cooldown": return DailyDriver.blue
                default: return DailyDriver.orange
                }
            }()
            beats.append(.band(label, tag: tag, color: color))
            for exercise in block.exercises {
                let chip = swapChip(for: exercise, equipmentEmpty: draft.equipmentEmpty)
                beats.append(.row(
                    exercise.name,
                    detail: exerciseDetail(exercise),
                    chip: chip,
                    chipAmber: chip != nil,
                    open: exercise.openGoal == true
                ))
            }
        }

        return BuildRevealConfig(
            title: draft.title,
            verb: importVerb,
            doneNote: importDoneNote,
            cta: importCTA,
            building: importBuilding,
            beats: beats
        )
    }

    // Create-with-AI draft — WHY THIS bullets before blocks. Scripted fallback
    // when the response arrives whole (no SSE yet); call sites may also
    // `revealNext` per chunk when streaming lands.
    // swiftlint:disable:next function_parameter_count
    static func aiFromDraft(
        title: String,
        whyThis: [String],
        warmUp: WorkoutInterval?,
        mainBlocks: [WorkoutInterval],
        cooldown: WorkoutInterval?,
        metaPills: [String]
    ) -> BuildRevealConfig {
        var beats: [BuildBeat] = []
        if !metaPills.isEmpty {
            beats.append(.pills(metaPills))
        }
        for bullet in whyThis.prefix(3) {
            beats.append(.bullet(bullet))
        }
        if let warmUp {
            beats.append(.band("Warm-up", tag: "~5 MIN", color: DailyDriver.mobilityBand))
            beats.append(contentsOf: intervalRows(warmUp))
        }
        if !mainBlocks.isEmpty {
            beats.append(.band(
                title.isEmpty ? "Session" : title,
                tag: "\(mainBlocks.count) EXERCISES",
                color: DailyDriver.lime
            ))
            for interval in mainBlocks {
                beats.append(contentsOf: intervalRows(interval))
            }
        }
        if let cooldown {
            beats.append(.band("Cooldown", tag: "AFTER", color: DailyDriver.blue))
            beats.append(contentsOf: intervalRows(cooldown))
        }
        return BuildRevealConfig(
            title: title,
            verb: aiVerb,
            doneNote: aiDoneNote,
            cta: aiCTA,
            building: aiBuilding,
            beats: beats
        )
    }

    // MARK: - Helpers

    private static func exerciseDetail(_ exercise: SocialImportExercise) -> String {
        var parts: [String] = []
        if let sets = exercise.sets, let reps = exercise.reps {
            parts.append("\(sets) × \(reps)")
        } else if let sets = exercise.sets, let range = exercise.repsRange, !range.isEmpty {
            parts.append("\(sets) × \(range)")
        } else if let reps = exercise.reps {
            parts.append("\(reps) REPS")
        } else if let seconds = exercise.seconds {
            parts.append(String(format: "%d:%02d MIN", seconds / 60, seconds % 60))
        } else if exercise.openGoal == true {
            parts.append("OPEN")
        }
        if let load = exercise.load?.trimmingCharacters(in: .whitespacesAndNewlines), !load.isEmpty {
            parts.append(load.uppercased())
        }
        return parts.isEmpty ? "FROM THE REEL" : parts.joined(separator: " · ")
    }

    private static func swapChip(for exercise: SocialImportExercise, equipmentEmpty: Bool) -> String? {
        guard equipmentEmpty else { return nil }
        let name = exercise.name.lowercased()
        if name.contains("barbell") || name.contains("bb ") {
            return "SWAP? NO BARBELL"
        }
        if name.contains("sled") {
            return "SWAP? NO SLED"
        }
        if name.contains("cable") {
            return "SWAP? NO CABLES"
        }
        return nil
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func intervalRows(_ interval: WorkoutInterval) -> [BuildBeat] {
        switch interval {
        case .warmup(let seconds, let target):
            return [.row(target ?? "Warm-up", detail: "\(seconds)S · LIGHT")]
        case .cooldown(let seconds, let target):
            return [.row(target ?? "Cooldown", detail: "\(seconds)S · EASY")]
        case .time(let seconds, let target):
            return [.row(target ?? "Timed", detail: "\(seconds)S")]
        case .reps(let sets, let reps, let name, let load, let restSec, _):
            var detail = sets.map { "\($0) × \(reps)" } ?? "\(reps) REPS"
            if let load, !load.isEmpty { detail += " · \(load.uppercased())" }
            let chip = restSec.map { "REST \($0)S" }
            return [.row(name, detail: detail, chip: chip)]
        case .distance(let meters, let target):
            return [.row(target ?? "Distance", detail: "\(meters) M")]
        case .repeat(let count, let intervals):
            var rows: [BuildBeat] = []
            for nested in intervals {
                rows.append(contentsOf: intervalRows(nested))
            }
            guard count > 1, let first = rows.first else { return rows }
            return [
                .row(
                    first.name ?? "Set",
                    detail: [first.detail, "×\(count)"].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                    chip: first.chip
                )
            ] + Array(rows.dropFirst())
        case .rest(let seconds):
            if let seconds {
                return [.row("Rest", detail: "\(seconds)S")]
            }
            return [.row("Rest", detail: "OPEN", open: true)]
        }
    }
}
