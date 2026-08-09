//
//  ActualsTodayDemoFeed.swift
//  AmakaFlow
//
//  AMA-2387 DEBUG: seeds Today with merge / map / fill-in debt so the flow
//  can be judged in the real app shell (tabs + Today chrome) without live ingest.
//  Activate after Connect, or launch with AMA2387_TODAY_DEMO=true.
//

// swiftlint:disable file_length

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
    /// Originating provider — preserved across verified rewrite of `sourceLabel`.
    let sourceProvider: ActualsSourceProvider?
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
            sourceProvider: sourceProvider
                ?? activity?.provider
                ?? session?.primaryRecording?.provider,
            session: session,
            activity: nil,
            fillInSession: saved
        )
    }
}

@MainActor
// swiftlint:disable:next type_body_length
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
        // Persist verified saves with the shared DB — never silently invent an in-memory queue.
        self.repository = repository ?? ActualsRepository()
    }

    /// Avoid MainActor-isolated deinit + TaskLocal teardown crash under XCTest (Swift 6).
    nonisolated deinit {}

    /// Launch flag: skip empty teach and land populated Actuals Today immediately.
    static var shouldAutoActivate: Bool {
        #if DEBUG
        UITestEnvironment.shared.actualsTodayDemo
        #else
        false
        #endif
    }

    /// After a real Connect from Today — honest counter + demo sessions land in-shell.
    /// No-op outside DEBUG (and cold-start / connect require `shouldAutoActivate`).
    func activateAfterConnect(sync: ActualsSyncProgressStore) {
        #if DEBUG
        guard !isActive else { return }
        isActive = true
        sync.beginBackfill(total: 4)
        sync.recordIngestedSession()
        sync.recordIngestedSession()
        loadSampleContent()
        showMergeAsk = true
        #else
        _ = sync
        #endif
    }

    /// AMA-2391: after Strava OAuth succeeds, pull sync-completed into the Today rail.
    /// Demo flag (`AMA2387_TODAY_DEMO`) still wins in DEBUG for fixture dogfood.
    func handleProviderConnected(
        _ provider: ActualsSourceProvider,
        sync: ActualsSyncProgressStore,
        client: BFFStravaClient? = nil
    ) async {
        #if DEBUG
        if Self.shouldAutoActivate {
            activateAfterConnect(sync: sync)
            return
        }
        #endif
        guard provider == .strava else { return }
        await activateFromStravaSync(sync: sync, client: client ?? BFFStravaClient.live())
    }

    /// Replace demo cards with Strava sync-completed activities (30-day backfill).
    func activateFromStravaSync(
        sync: ActualsSyncProgressStore,
        client: BFFStravaClient
    ) async {
        do {
            let result = try await client.syncCompleted(daysBack: 30)
            isActive = true
            showMergeAsk = false
            let activities = result.activities
            let total = max(result.syncedCount, activities.count)
            if total > 0 {
                sync.beginBackfill(total: total)
                for _ in activities {
                    sync.recordIngestedSession()
                }
            } else {
                sync.clear()
            }
            cards = Self.cards(from: activities)
        } catch {
            // Connected server-side; rail stays honest-empty until the next refresh.
            isActive = true
            showMergeAsk = false
            cards = []
            sync.clear()
        }
    }

    /// Map API activities → unmapped Today cards (prefer calendar-today, else recent).
    static func cards(from activities: [StravaCompletedActivityDTO]) -> [ActualsTodayDemoCard] {
        let parsed = activities.compactMap { activity -> (StravaCompletedActivityDTO, Date)? in
            guard let date = parseStravaStartDate(activity.startDate) else { return nil }
            return (activity, date)
        }
        .sorted { $0.1 > $1.1 }

        let calendar = Calendar.current
        let todays = parsed.filter { calendar.isDateInToday($0.1) }
        let chosen = todays.isEmpty ? Array(parsed.prefix(8)) : todays
        return chosen.map { card(from: $0.0, startDate: $0.1) }
    }

    private static func card(
        from activity: StravaCompletedActivityDTO,
        startDate: Date
    ) -> ActualsTodayDemoCard {
        let durationSeconds = TimeInterval(activity.durationMin * 60)
        let distanceMeters = activity.distanceKm > 0 ? activity.distanceKm * 1_000 : nil
        let workoutType = workoutType(from: activity.type)
        let unmapped = ActualsUnmappedActivity(
            title: activity.name,
            provider: .strava,
            startDate: startDate,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            calories: nil,
            avgHR: nil,
            type: workoutType
        )
        var stats: [(icon: String, value: String)] = [
            ("clock", "\(max(1, activity.durationMin))m")
        ]
        if let distanceMeters {
            let kilometers = distanceMeters / 1_000
            let distanceText = kilometers >= 10
                ? String(format: "%.0f km", kilometers)
                : String(format: "%.1f km", kilometers)
            stats.append(("figure.run", distanceText))
        }
        return ActualsTodayDemoCard(
            id: "strava_\(activity.stravaId)",
            kind: .unmapped,
            timeLabel: cardTimeFormatter.string(from: startDate),
            title: activity.name,
            stats: stats,
            sourceLabel: "Synced from \(ActualsCopy.sourceDisplayName(.strava))",
            sourceProvider: .strava,
            session: nil,
            activity: unmapped,
            fillInSession: nil
        )
    }

    private static func workoutType(from raw: String) -> ActualsWorkoutType {
        switch raw.lowercased() {
        case "run", "virtualrun", "trailrun":
            return .run
        case "ride", "virtualride", "ebikeride", "gravelride":
            return .ride
        case "weighttraining", "workout", "crossfit", "yoga":
            return .strength
        default:
            return .other
        }
    }

    private static func parseStravaStartDate(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    /// Cold-start demo: pretend a source is already linked and Today has Actuals debt.
    func activateColdStart(
        sources: ActualsSourceConnectionStore,
        sync: ActualsSyncProgressStore
    ) {
        #if DEBUG
        guard Self.shouldAutoActivate else { return }
        guard !isActive else { return }
        if !sources.hasAnySourceConnected {
            sources.markConnected(.strava)
        }
        activateAfterConnect(sync: sync)
        // Cold start: finish the counter so the banner can clear after a beat.
        sync.recordIngestedSession()
        sync.recordIngestedSession()
        #else
        _ = sources
        _ = sync
        #endif
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

    /// Split restores each recording as its own Today card and sticky-keeps them separate.
    func applySplit(
        restored: [ActualsSourceRecording],
        fromMergedSessionID: String
    ) {
        applyKeepBoth()
        cards.removeAll { $0.id == fromMergedSessionID || $0.kind == .merged }
        for recording in restored.reversed() {
            cards.insert(Self.card(from: recording), at: 0)
        }
    }

    func prepareFillIn(from card: ActualsTodayDemoCard? = nil) {
        let source = card
            ?? cards.first { $0.kind == .fillInDebt }
            ?? cards.first { $0.kind == .merged }
        pendingFillInCardID = source?.id
        let session = source?.fillInSession
            ?? ActualsFillInSession.lowerBodyPosteriorSample(
                id: "today_demo_fill_\(UUID().uuidString.prefix(6))"
            )
        var seeded = session
        if !seeded.exercises.isEmpty, seeded.exercises[0].confirmation == nil {
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
        let prior = cards.first { $0.id == unmappedCardID }
        let activity = prior?.activity ?? Self.unmappedCard().activity
        let timeLabel = prior?.timeLabel ?? "18:10"
        let matched = makeMatchedCard(
            request: MatchedCardRequest(
                cardID: unmappedCardID,
                timeLabel: timeLabel,
                title: draft.title,
                activity: activity,
                blockSummaries: draft.blockSummaries,
                sourceLabel: "Matched · \(ActualsCopy.sourceDisplayName(activity?.provider ?? .garmin))"
            )
        )
        upsertCard(matched, replacing: unmappedCardID, atFrontIfMissing: true)
    }

    /// Map → picked a library workout: keep the session row, attach that plan for RPE.
    func applyLibraryMatch(planTitle: String, unmappedCardID: String = "today_demo_unmapped") {
        let prior = cards.first { $0.id == unmappedCardID }
        let activity = prior?.activity ?? Self.unmappedCard().activity
        let timeLabel = prior?.timeLabel ?? "18:10"
        let matched = makeMatchedCard(
            request: MatchedCardRequest(
                cardID: unmappedCardID,
                timeLabel: timeLabel,
                title: planTitle,
                activity: activity,
                blockSummaries: [planTitle],
                sourceLabel: "Matched · \(ActualsCopy.sourceDisplayName(activity?.provider ?? .garmin))"
            )
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

    private struct MatchedCardRequest {
        let cardID: String
        let timeLabel: String
        let title: String
        let activity: ActualsUnmappedActivity?
        let blockSummaries: [String]
        let sourceLabel: String
    }

    private func makeMatchedCard(request: MatchedCardRequest) -> ActualsTodayDemoCard {
        let cardID = request.cardID
        let timeLabel = request.timeLabel
        let title = request.title
        let activity = request.activity
        let blockSummaries = request.blockSummaries
        let sourceLabel = request.sourceLabel
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
        if let heartRate = activity?.avgHR {
            stats.append(("heart.fill", "\(heartRate)"))
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
                    )
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
            sourceProvider: activity?.provider ?? .garmin,
            session: nil,
            activity: activity,
            fillInSession: fillSession
        )
    }

    // MARK: - Samples

    private static func card(from recording: ActualsSourceRecording) -> ActualsTodayDemoCard {
        let minutes = max(1, Int((recording.durationSeconds / 60).rounded()))
        var stats: [(icon: String, value: String)] = [("clock", "\(minutes)m")]
        if let distance = recording.distanceMeters {
            let kilometers = distance / 1_000
            let distanceText = kilometers >= 10
                ? String(format: "%.0f km", kilometers)
                : String(format: "%.1f km", kilometers)
            stats.append(("figure.run", distanceText))
        }
        let activity = ActualsUnmappedActivity(
            title: recording.title,
            provider: recording.provider,
            startDate: recording.startDate,
            durationSeconds: recording.durationSeconds,
            distanceMeters: recording.distanceMeters,
            calories: nil,
            avgHR: nil,
            type: .strength
        )
        let time = Self.cardTimeFormatter.string(from: recording.startDate)
        return ActualsTodayDemoCard(
            id: recording.id,
            kind: .unmapped,
            timeLabel: time,
            title: recording.title,
            stats: stats,
            sourceLabel: "Synced from \(ActualsCopy.sourceDisplayName(recording.provider))",
            sourceProvider: recording.provider,
            session: nil,
            activity: activity,
            fillInSession: nil
        )
    }

    private static let cardTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private func loadSampleContent() {
        mergeLeft = Self.sampleWatchRecording
        mergeRight = Self.samplePhoneRecording
        // Unmapped first — the session that needs Fill in › → Map v2.
        cards = [
            Self.unmappedCard(),
            Self.mergedCard(),
            Self.fillInCard()
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
            samplePhoneRecording
        ], sessionID: "today_demo_merged")
        return ActualsTodayDemoCard(
            id: session.id,
            kind: .merged,
            timeLabel: "12:04",
            title: session.title,
            stats: [
                ("clock", "44m"),
                ("flame.fill", "612 kcal"),
                ("heart.fill", "148")
            ],
            sourceLabel: session.mergeBadge,
            sourceProvider: session.primaryRecording?.provider ?? .appleHealth,
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
                ("heart.fill", "151")
            ],
            sourceLabel: "Synced from Garmin",
            sourceProvider: activity.provider,
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
                ("dumbbell.fill", "4 moves")
            ],
            sourceLabel: "Apple Watch session",
            sourceProvider: .appleHealth,
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
            )
        ]
    }
}
