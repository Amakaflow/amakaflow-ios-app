//
//  ActualsTodayDemoFeed.swift
//  AmakaFlow
//
//  AMA-2387 DEBUG: seeds Today with merge / map / fill-in debt so the flow
//  can be judged in the real app shell (tabs + Today chrome) without live ingest.
//  Activate after Connect, or launch with AMA2387_TODAY_DEMO=true.
//

import Combine
import Foundation

/// One diary card driven by Actuals demo content (not WorkoutCompletion ingest yet).
struct ActualsTodayDemoCard: Identifiable, Equatable {
    enum Kind: Equatable {
        case merged
        case unmapped
        case fillInDebt
        case verified
    }

    let id: String
    let kind: Kind
    let timeLabel: String
    let title: String
    let stats: [(icon: String, value: String)]
    let sourceLabel: String
    let session: ActualsSession?
    let activity: ActualsUnmappedActivity?
    let fillInSession: ActualsFillInSession?

    static func == (lhs: ActualsTodayDemoCard, rhs: ActualsTodayDemoCard) -> Bool {
        lhs.id == rhs.id && lhs.kind == rhs.kind
    }

    func markingVerified(with saved: ActualsFillInSession) -> ActualsTodayDemoCard {
        ActualsTodayDemoCard(
            id: id,
            kind: .verified,
            timeLabel: timeLabel,
            title: title,
            stats: stats,
            sourceLabel: "Verified · RPE \(saved.rpe ?? 0)",
            session: session,
            activity: nil,
            fillInSession: saved
        )
    }
}

@MainActor
final class ActualsTodayDemoFeed: ObservableObject {
    @Published private(set) var isActive = false
    @Published var showMergeAsk = false
    @Published private(set) var cards: [ActualsTodayDemoCard] = []
    @Published private(set) var mergeLeft: ActualsSourceRecording?
    @Published private(set) var mergeRight: ActualsSourceRecording?
    @Published var fillInViewModel: ActualsFillInViewModel?
    /// Card that opened the current fill-in — flipped to Verified on save.
    private(set) var pendingFillInCardID: String?

    private(set) var mergeMemory = ActualsMergeMemory()
    let repository: ActualsRepository

    init(repository: ActualsRepository? = nil) {
        if let repository {
            self.repository = repository
        } else if let db = try? AppDatabase.makeTestDatabase() {
            self.repository = ActualsRepository(database: db)
        } else {
            self.repository = ActualsRepository()
        }
    }

    /// Launch flag: skip empty teach and land populated Actuals Today immediately.
    static var shouldAutoActivate: Bool {
        #if DEBUG
        UITestEnvironment.isTruthy("AMA2387_TODAY_DEMO")
        #else
        false
        #endif
    }

    /// After a real Connect from Today — honest counter + demo sessions land in-shell.
    func activateAfterConnect(sync: ActualsSyncProgressStore) {
        guard !isActive else { return }
        isActive = true
        sync.beginBackfill(total: 4)
        sync.recordIngestedSession()
        sync.recordIngestedSession()
        loadSampleContent()
        showMergeAsk = true
    }

    /// Cold-start demo: pretend a source is already linked and Today has Actuals debt.
    func activateColdStart(
        sources: ActualsSourceConnectionStore,
        sync: ActualsSyncProgressStore
    ) {
        guard !isActive else { return }
        if !sources.hasAnySourceConnected {
            sources.markConnected(.strava)
        }
        activateAfterConnect(sync: sync)
        // Cold start: finish the counter so the banner can clear after a beat.
        sync.recordIngestedSession()
        sync.recordIngestedSession()
    }

    func applyMerge() {
        showMergeAsk = false
        // Ensure merged card is first / present.
        if !cards.contains(where: { $0.kind == .merged }) {
            cards.insert(Self.mergedCard(), at: 0)
        }
    }

    func applyKeepBoth() {
        if let left = mergeLeft, let right = mergeRight {
            ActualsMergeClassifier.applyKeepBoth(left, right, memory: &mergeMemory)
        }
        showMergeAsk = false
    }

    func prepareFillIn(from card: ActualsTodayDemoCard? = nil) {
        let source = card
            ?? cards.first(where: { $0.kind == .fillInDebt })
            ?? cards.first(where: { $0.kind == .merged })
        pendingFillInCardID = source?.id
        let session = source?.fillInSession
            ?? ActualsFillInSession.lowerBodyPosteriorSample(
                id: "today_demo_fill_\(UUID().uuidString.prefix(6))"
            )
        var seeded = session
        if seeded.exercises.first?.confirmation == nil {
            seeded.exercises[0].confirmation = .adjusted
            seeded.exercises[0].actualWeightKg = 90
        }
        fillInViewModel = ActualsFillInViewModel(session: seeded, repository: repository)
    }

    /// After a successful verified save — timeline CTA becomes Verified, not Fill in.
    func markVerified(saved: ActualsFillInSession) {
        var touched = Set<String>()
        if let pending = pendingFillInCardID {
            touched.insert(pending)
        }
        touched.insert(saved.id)
        touched.insert("today_demo_fill")
        touched.insert("today_demo_unmapped")

        for index in cards.indices {
            let card = cards[index]
            let matchesPending = touched.contains(card.id)
            let matchesSession = card.fillInSession?.id == saved.id
            // Merged Hyrox → fill-in from detail: flip that card too.
            let matchesMergedFillPath = card.kind == .merged
                && pendingFillInCardID == card.id
            // Only the card we opened — never every fill-in-debt row.
            if matchesPending || matchesSession || matchesMergedFillPath {
                cards[index] = card.markingVerified(with: saved)
            }
        }
        pendingFillInCardID = nil
    }

    func removeCard(id: String) {
        cards.removeAll { $0.id == id }
    }

    /// After match-save: keep the same timeline row (stable id) — never delete the session.
    /// Title becomes what they built; CTA becomes Log RPE.
    func applyCaptureMatched(draft: ActualsCaptureDraft, unmappedCardID: String = "today_demo_unmapped") {
        let prior = cards.first(where: { $0.id == unmappedCardID })
        let activity = prior?.activity ?? Self.unmappedCard().activity
        let timeLabel = prior?.timeLabel ?? "18:10"
        let matched = makeMatchedCard(
            cardID: unmappedCardID,
            timeLabel: timeLabel,
            title: draft.title,
            activity: activity,
            blockSummaries: draft.blockSummaries,
            sourceLabel: "Matched · \(ActualsCopy.sourceDisplayName(activity?.provider ?? .garmin))"
        )
        upsertCard(matched, replacing: unmappedCardID, atFrontIfMissing: true)
    }

    /// Map → picked a library workout: keep the session row, attach that plan for RPE.
    func applyLibraryMatch(planTitle: String, unmappedCardID: String = "today_demo_unmapped") {
        let prior = cards.first(where: { $0.id == unmappedCardID })
        let activity = prior?.activity ?? Self.unmappedCard().activity
        let timeLabel = prior?.timeLabel ?? "18:10"
        let matched = makeMatchedCard(
            cardID: unmappedCardID,
            timeLabel: timeLabel,
            title: planTitle,
            activity: activity,
            blockSummaries: [planTitle],
            sourceLabel: "Matched · \(ActualsCopy.sourceDisplayName(activity?.provider ?? .garmin))"
        )
        upsertCard(matched, replacing: unmappedCardID, atFrontIfMissing: true)
    }

    private func upsertCard(
        _ card: ActualsTodayDemoCard,
        replacing id: String,
        atFrontIfMissing: Bool
    ) {
        if let index = cards.firstIndex(where: { $0.id == id }) {
            cards[index] = card
        } else if atFrontIfMissing {
            cards.insert(card, at: 0)
        } else {
            cards.append(card)
        }
    }

    private func makeMatchedCard(
        cardID: String,
        timeLabel: String,
        title: String,
        activity: ActualsUnmappedActivity?,
        blockSummaries: [String],
        sourceLabel: String
    ) -> ActualsTodayDemoCard {
        let minutes: Int = {
            if let activity {
                return max(1, Int((activity.durationSeconds / 60).rounded()))
            }
            return 44
        }()
        var stats: [(icon: String, value: String)] = [("clock", "\(minutes)m")]
        if let cal = activity?.calories {
            stats.append(("flame.fill", "\(Int(cal.rounded())) kcal"))
        }
        if let hr = activity?.avgHR {
            stats.append(("heart.fill", "\(hr)"))
        }
        let moveCount = max(blockSummaries.count, 1)
        stats.append(("dumbbell.fill", "\(moveCount) moves"))

        let exercises: [ExerciseActual] = blockSummaries.prefix(6).enumerated().map { offset, name in
            let slug = name
                .lowercased()
                .replacingOccurrences(of: " ", with: "_")
                .filter { $0.isLetter || $0.isNumber || $0 == "_" }
            return ExerciseActual(
                id: "capture_\(offset)_\(slug)",
                name: name,
                planned: ExerciseActualPlanned(sets: 1, reps: 1, note: "AS BUILT")
            )
        }
        let fillSession = ActualsFillInSession(
            id: cardID,
            title: title,
            subtitle: "\(title.uppercased()) · MATCHED",
            exercises: exercises.isEmpty
                ? [
                    ExerciseActual(
                        id: "capture_main",
                        name: title,
                        planned: ExerciseActualPlanned(sets: 1, reps: 1, note: "AS BUILT")
                    ),
                ]
                : Array(exercises),
            rpe: nil,
            verified: false
        )

        return ActualsTodayDemoCard(
            id: cardID,
            kind: .fillInDebt,
            timeLabel: timeLabel,
            title: title,
            stats: stats,
            sourceLabel: sourceLabel,
            session: nil,
            activity: activity,
            fillInSession: fillSession
        )
    }

    // MARK: - Samples

    private func loadSampleContent() {
        mergeLeft = Self.sampleWatchRecording
        mergeRight = Self.samplePhoneRecording
        // Unmapped first — the session that needs Fill in › → Map v2.
        cards = [
            Self.unmappedCard(),
            Self.mergedCard(),
            Self.fillInCard(),
        ]
    }

    private static func mergedCard() -> ActualsTodayDemoCard {
        let session = ActualsMergeClassifier.merge([
            sampleWatchRecording,
            ActualsSourceRecording(
                id: "today_demo_garmin",
                provider: .garmin,
                deviceKind: .watch,
                title: "Hyrox Sim",
                startDate: Date().addingTimeInterval(-3600),
                durationSeconds: 44 * 60,
                streamRichness: 4
            ),
            samplePhoneRecording,
        ], sessionID: "today_demo_merged")
        return ActualsTodayDemoCard(
            id: session.id,
            kind: .merged,
            timeLabel: "12:04",
            title: session.title,
            stats: [
                ("clock", "44m"),
                ("flame.fill", "612 kcal"),
                ("heart.fill", "148"),
            ],
            sourceLabel: session.mergeBadge,
            session: session,
            activity: nil,
            fillInSession: nil
        )
    }

    /// Fallback when a card is missing its activity payload (never push a blank Map).
    static func sampleUnmappedActivity() -> ActualsUnmappedActivity {
        ActualsUnmappedActivity(
            title: "Gym session",
            provider: .garmin,
            startDate: Date().addingTimeInterval(-7200),
            durationSeconds: 44 * 60,
            distanceMeters: nil,
            calories: 486,
            avgHR: 151,
            type: .strength
        )
    }

    private static func unmappedCard() -> ActualsTodayDemoCard {
        let activity = sampleUnmappedActivity()
        return ActualsTodayDemoCard(
            id: "today_demo_unmapped",
            kind: .unmapped,
            timeLabel: "18:10",
            title: "Gym session",
            stats: [
                ("clock", "44m"),
                ("flame.fill", "486 kcal"),
                ("heart.fill", "151"),
            ],
            sourceLabel: "Synced from Garmin",
            session: nil,
            activity: activity,
            fillInSession: nil
        )
    }

    private static func fillInCard() -> ActualsTodayDemoCard {
        var session = ActualsFillInSession.lowerBodyPosteriorSample(id: "today_demo_fill")
        session.exercises[0].confirmation = .adjusted
        session.exercises[0].actualWeightKg = 90
        return ActualsTodayDemoCard(
            id: session.id,
            kind: .fillInDebt,
            timeLabel: "07:52",
            title: session.title,
            stats: [
                ("clock", "48m"),
                ("dumbbell.fill", "4 moves"),
            ],
            sourceLabel: "Apple Watch session",
            session: nil,
            activity: nil,
            fillInSession: session
        )
    }

    private static var sampleWatchRecording: ActualsSourceRecording {
        ActualsSourceRecording(
            id: "today_demo_aw",
            provider: .appleHealth,
            deviceKind: .watch,
            title: "Hyrox Sim",
            startDate: Date().addingTimeInterval(-3600),
            durationSeconds: 44 * 60,
            distanceMeters: 5_200,
            streamRichness: 5
        )
    }

    private static var samplePhoneRecording: ActualsSourceRecording {
        ActualsSourceRecording(
            id: "today_demo_strava",
            provider: .strava,
            deviceKind: .phone,
            title: "Hyrox Sim",
            startDate: Date().addingTimeInterval(-3600 + 45),
            durationSeconds: 44 * 60,
            distanceMeters: 5_180,
            streamRichness: 2
        )
    }

    static var samplePlanCandidates: [ActualsPlanCandidate] {
        let start = Date().addingTimeInterval(-7200)
        return [
            ActualsPlanCandidate(
                id: "today_c1",
                title: "Lower body — posterior",
                sourceLabel: "MY WORKOUTS",
                scheduledStart: start,
                durationSeconds: 48 * 60,
                distanceMeters: nil,
                type: .strength,
                targetAvgHR: nil
            ),
        ]
    }
}
