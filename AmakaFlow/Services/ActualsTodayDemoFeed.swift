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
import OSLog

private let actualsTodayDemoFeedLog = Logger(
    subsystem: "com.myamaka.AmakaFlowCompanion",
    category: "ActualsTodayDemoFeed"
)

/// One diary card driven by Actuals demo content (not WorkoutCompletion ingest yet).
struct ActualsTodayDemoCard: Identifiable, Equatable {
    enum Kind: Equatable {
        case merged
        case unmapped
        case fillInDebt
        /// AMA-2407: durable end state — includes both fill-in verified sessions
        /// and "Verify as-is" (no exercises, no RPE). There is no separate
        /// durable "Counted" kind — product rule is Verified or Fill in, only.
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
    /// AMA-2396 A5: per-session Strava write-state badge.
    let stravaDecoration: StravaDecorationState

    init(
        id: String,
        kind: Kind,
        timeLabel: String,
        title: String,
        stats: [(icon: String, value: String)],
        sourceLabel: String,
        sourceProvider: ActualsSourceProvider?,
        session: ActualsSession?,
        activity: ActualsUnmappedActivity?,
        fillInSession: ActualsFillInSession?,
        stravaDecoration: StravaDecorationState = .none
    ) {
        self.id = id
        self.kind = kind
        self.timeLabel = timeLabel
        self.title = title
        self.stats = stats
        self.sourceLabel = sourceLabel
        self.sourceProvider = sourceProvider
        self.session = session
        self.activity = activity
        self.fillInSession = fillInSession
        self.stravaDecoration = stravaDecoration
    }

    static func == (lhs: ActualsTodayDemoCard, rhs: ActualsTodayDemoCard) -> Bool {
        lhs.id == rhs.id
            && lhs.kind == rhs.kind
            && lhs.stravaDecoration == rhs.stravaDecoration
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
            // AMA-2409: keep activity so Today day-filter retains the real start date.
            // Nilling it parked historical Verified+OURS cards on calendar-today.
            activity: activity,
            fillInSession: saved,
            stravaDecoration: stravaDecoration
        )
    }

    /// AMA-2407: Verify as-is — mark Verified in AmakaFlow only (no Strava write).
    /// Replaces the AMA-2396/2405 "Keep as-is → Counted" path; there is no
    /// durable Counted state, only Verified or Fill in.
    func markingVerifiedAsIs(
        with verifiedSession: ActualsFillInSession,
        decoration: StravaDecorationState
    ) -> ActualsTodayDemoCard {
        ActualsTodayDemoCard(
            id: id,
            kind: .verified,
            timeLabel: timeLabel,
            title: verifiedSession.title,
            stats: stats,
            sourceLabel: verifiedSession.rpe.map { "Verified · RPE \($0)" } ?? "Verified · as-is",
            sourceProvider: sourceProvider ?? activity?.provider,
            session: session,
            activity: activity,
            fillInSession: verifiedSession,
            stravaDecoration: decoration
        )
    }

    func withDecoration(_ state: StravaDecorationState) -> ActualsTodayDemoCard {
        ActualsTodayDemoCard(
            id: id,
            kind: kind,
            timeLabel: timeLabel,
            title: title,
            stats: stats,
            sourceLabel: sourceLabel,
            sourceProvider: sourceProvider,
            session: session,
            activity: activity,
            fillInSession: fillInSession,
            stravaDecoration: state
        )
    }

    /// AMA-2405: cache Strava description after a lazy detail fetch.
    func withActivityDescription(_ description: String) -> ActualsTodayDemoCard {
        var nextActivity = activity
        if nextActivity != nil {
            nextActivity?.activityDescription = description
        }
        var nextSession = fillInSession
        if nextSession != nil {
            nextSession?.stravaCurrentDescription = description
        }
        guard nextActivity != nil || nextSession != nil else { return self }
        return ActualsTodayDemoCard(
            id: id,
            kind: kind,
            timeLabel: timeLabel,
            title: title,
            stats: stats,
            sourceLabel: sourceLabel,
            sourceProvider: sourceProvider,
            session: session,
            activity: nextActivity,
            fillInSession: nextSession,
            stravaDecoration: stravaDecoration
        )
    }

    var statsSummary: String {
        stats.map(\.value).joined(separator: " · ")
    }

    /// Keep kind (fill-in debt) while refreshing in-progress actuals after Back.
    func withFillInSession(_ session: ActualsFillInSession) -> ActualsTodayDemoCard {
        ActualsTodayDemoCard(
            id: id,
            kind: kind == .verified && !session.verified ? .fillInDebt : kind,
            timeLabel: timeLabel,
            title: title,
            stats: stats,
            sourceLabel: sourceLabel,
            sourceProvider: sourceProvider,
            session: self.session,
            activity: activity,
            fillInSession: session,
            stravaDecoration: stravaDecoration
        )
    }
}

@MainActor
// swiftlint:disable:next type_body_length
final class ActualsTodayDemoFeed: ObservableObject {
    @Published private(set) var isActive = false
    /// True while sync-completed is in flight — Today must not flash Connect CTA.
    @Published private(set) var isRefreshing = false
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
    /// AMA-2419: after Apple Health grant, pull HKWorkout samples the same way.
    /// AMA-2422: when multiple sources are linked, load all and certain-dedupe.
    /// Demo flag (`AMA2387_TODAY_DEMO`) still wins in DEBUG for fixture dogfood.
    func handleProviderConnected(
        _ provider: ActualsSourceProvider,
        sync: ActualsSyncProgressStore,
        sources: (any ActualsSourceConnecting)? = nil,
        client: BFFStravaClient? = nil,
        appleHealthFetcher: (any ActualsHealthKitWorkoutFetching)? = nil
    ) async {
        #if DEBUG
        if Self.shouldAutoActivate {
            activateAfterConnect(sync: sync)
            return
        }
        #endif
        if let sources {
            await activateFromConnectedSources(
                sources: sources,
                sync: sync,
                client: client,
                appleHealthFetcher: appleHealthFetcher
            )
            return
        }
        switch provider {
        case .strava:
            await activateFromStravaSync(sync: sync, client: client ?? BFFStravaClient.live())
        case .appleHealth:
            await activateFromAppleHealth(
                sync: sync,
                fetcher: appleHealthFetcher ?? LiveActualsHealthKitWorkoutFetcher()
            )
        case .garmin:
            break
        }
    }

    /// Load every linked provider and collapse certain Strava↔Apple Health duplicates.
    func activateFromConnectedSources(
        sources: any ActualsSourceConnecting,
        sync: ActualsSyncProgressStore,
        client: BFFStravaClient? = nil,
        appleHealthFetcher: (any ActualsHealthKitWorkoutFetching)? = nil,
        daysBack: Int = 30
    ) async {
        #if DEBUG
        if Self.shouldAutoActivate {
            activateAfterConnect(sync: sync)
            return
        }
        #endif

        let wantsStrava = sources.isConnected(.strava)
        let wantsApple = sources.isConnected(.appleHealth)
        guard wantsStrava || wantsApple else { return }

        if wantsStrava, !wantsApple {
            await activateFromStravaSync(sync: sync, client: client ?? BFFStravaClient.live())
            return
        }
        if wantsApple, !wantsStrava {
            await activateFromAppleHealth(
                sync: sync,
                fetcher: appleHealthFetcher ?? LiveActualsHealthKitWorkoutFetcher(),
                daysBack: daysBack
            )
            return
        }

        isRefreshing = true
        sync.beginPulling()
        defer { isRefreshing = false }

        let stravaClient = client ?? BFFStravaClient.live()
        let healthFetcher = appleHealthFetcher ?? LiveActualsHealthKitWorkoutFetcher()

        var combined: [ActualsTodayDemoCard] = []
        var stravaActivities: [StravaCompletedActivityDTO] = []
        var loadedAny = false

        do {
            let result = try await stravaClient.syncCompleted(daysBack: daysBack)
            if result.success {
                loadedAny = true
                stravaActivities = result.activities
                combined.append(
                    contentsOf: Self.historyCards(from: result.activities).flatMap(\.cards)
                )
            }
        } catch {
            // Apple Health may still load.
        }

        do {
            let samples = try await healthFetcher.fetchWorkouts(daysBack: daysBack)
            loadedAny = true
            combined.append(contentsOf: Self.historyCards(from: samples).flatMap(\.cards))
        } catch {
            // Keep Strava rows if present.
        }

        guard loadedAny else {
            isActive = false
            showMergeAsk = false
            cards = []
            sync.clear()
            return
        }

        let deduped = ActualsCrossSourceDeduper.dedupeCards(combined, memory: mergeMemory)
        isActive = true
        showMergeAsk = false
        if !deduped.isEmpty {
            sync.beginBackfill(total: deduped.count)
            for _ in deduped {
                sync.recordIngestedSession()
            }
        } else {
            sync.clear()
        }
        cards = Self.applyLocalOverlays(to: deduped, repository: repository)
        reconcilePendingLogDrafts(against: deduped)
        await ensureServerVerifiedForLinkedActivities(stravaActivities, client: stravaClient)
    }

    /// AMA-2426: attach companion log drafts to overlapping device sessions.
    /// Pending drafts never become Today cards on their own.
    func reconcilePendingLogDrafts(against cards: [ActualsTodayDemoCard]) {
        let draftRepo = LogDraftRepository()
        guard let drafts = try? draftRepo.fetchPendingCompanionDrafts(), !drafts.isEmpty else { return }
        let recordings: [ActualsSourceRecording] = cards.compactMap { card in
            if let session = card.session {
                return session.primaryRecording
            }
            if let activity = card.activity {
                return ActualsSourceRecording(
                    id: card.id,
                    provider: activity.provider,
                    deviceKind: .watch,
                    title: activity.title,
                    startDate: activity.startDate,
                    durationSeconds: activity.durationSeconds,
                    distanceMeters: activity.distanceMeters,
                    streamRichness: 3
                )
            }
            return nil
        }
        for draft in drafts {
            let outcome = LogbookReconciliation.reconcile(
                draft: draft,
                deviceSessions: recordings,
                memory: mergeMemory
            )
            switch outcome {
            case .merged(let sessionId):
                guard let device = recordings.first(where: { $0.id == sessionId }) else { continue }
                let session = LogbookReconciliation.mergeDraft(draft, onto: device)
                try? repository.upsertMatchedDraft(session)
                try? draftRepo.markReconciled(draftID: draft.id, sessionID: sessionId)
            case .timeoutCommit:
                // Standalone commit is owned by LogbookViewModel (Undo toast).
                break
            case .noOverlap, .lateTwinRequiresDuplicateFlow:
                break
            }
        }
    }

    /// Replace Today cards with Apple Health workouts for the lookback window.
    func activateFromAppleHealth(
        sync: ActualsSyncProgressStore,
        fetcher: any ActualsHealthKitWorkoutFetching,
        daysBack: Int = 30
    ) async {
        isRefreshing = true
        sync.beginPulling()
        defer { isRefreshing = false }
        do {
            let samples = try await fetcher.fetchWorkouts(daysBack: daysBack)
            isActive = true
            showMergeAsk = false
            let windowCards = Self.historyCards(from: samples).flatMap(\.cards)
            if !samples.isEmpty {
                sync.beginBackfill(total: samples.count)
                for _ in samples {
                    sync.recordIngestedSession()
                }
            } else {
                sync.clear()
            }
            cards = Self.applyLocalOverlays(to: windowCards, repository: repository)
        } catch {
            isActive = false
            showMergeAsk = false
            cards = []
            sync.clear()
        }
    }

    /// Replace Today cards with Strava sync-completed activities for the lookback window.
    /// AMA-2396: keep all pulled days in `cards` so the scrubber can show past sessions;
    /// `TodayDiaryView` filters to the selected local day.
    func activateFromStravaSync(
        sync: ActualsSyncProgressStore,
        client: BFFStravaClient
    ) async {
        isRefreshing = true
        // Show lookback copy immediately — don't wait for the response to paint a banner.
        sync.beginPulling()
        defer { isRefreshing = false }
        do {
            let result = try await client.syncCompleted(daysBack: 30)
            // Logical BFF failure: do not activate Today, map activities, or invent progress.
            guard result.success else {
                throw StravaLogicalSyncFailure(message: result.message)
            }
            isActive = true
            showMergeAsk = false
            let activities = result.activities
            // Newest-first across the window (same order History uses).
            let windowCards = Self.historyCards(from: activities).flatMap(\.cards)
            let total = max(result.syncedCount, activities.count)
            if total > 0 {
                sync.beginBackfill(total: total)
                for _ in activities {
                    sync.recordIngestedSession()
                }
            } else {
                sync.clear()
            }
            // Re-apply local match/verify so a Strava re-pull does not wipe Save state.
            cards = Self.applyLocalOverlays(to: windowCards, repository: repository)
            // Signature / wrote-Strava without a server verified row yet — mark
            // those Strava ids verified on our end so the next pull is durable.
            await ensureServerVerifiedForLinkedActivities(activities, client: client)
        } catch is StravaLogicalSyncFailure {
            showMergeAsk = false
            cards = []
            sync.clear()
        } catch {
            // Tokens missing / network — leave the empty Today + Connect CTA visible
            // only when we are no longer considered linked (caller may clear store).
            isActive = false
            showMergeAsk = false
            cards = []
            sync.clear()
        }
    }

    /// Map API activities → unmapped Today cards for calendar-today only.
    /// AMA-2396: bucket by `start_date_local` (not UTC) so evening sessions don't
    /// land on the wrong day; sort newest-first (18:34 above 12:19).
    static func cards(
        from activities: [StravaCompletedActivityDTO],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [ActualsTodayDemoCard] {
        cards(
            from: activities,
            on: calendar.startOfDay(for: now),
            calendar: calendar,
            now: now
        )
    }

    /// All activities for a local day, newest-first.
    static func cards(
        from activities: [StravaCompletedActivityDTO],
        on day: Date,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [ActualsTodayDemoCard] {
        let parsed = activities.compactMap { activity -> (StravaCompletedActivityDTO, Date)? in
            guard let date = resolveStartDate(activity, calendar: calendar, now: now) else {
                return nil
            }
            guard calendar.isDate(date, inSameDayAs: day) else { return nil }
            return (activity, date)
        }
        .sorted { $0.1 > $1.1 }

        return parsed.map {
            card(from: $0.0, startDate: $0.1, timeZone: calendar.timeZone)
        }
    }

    /// Full 30-day (or longer) history rows, day-bucketed newest-first.
    static func historyCards(
        from activities: [StravaCompletedActivityDTO],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [(day: Date, cards: [ActualsTodayDemoCard])] {
        let parsed: [(StravaCompletedActivityDTO, Date)] = activities.compactMap { activity in
            guard let date = resolveStartDate(activity, calendar: calendar, now: now) else {
                return nil
            }
            return (activity, date)
        }
        let buckets = ActualsDayBucketing.bucketByLocalDay(
            parsed,
            startDate: { $0.1 },
            calendar: calendar
        )
        return buckets.map { day, items in
            (
                day,
                items.map {
                    card(from: $0.0, startDate: $0.1, timeZone: calendar.timeZone)
                }
            )
        }
    }

    static func resolveStartDate(
        _ activity: StravaCompletedActivityDTO,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> Date? {
        ActualsDayBucketing.resolveStartDate(
            startDateLocal: activity.startDateLocal,
            startDateUTC: activity.startDate,
            calendar: calendar,
            now: now
        )
    }

    private static func card(
        from activity: StravaCompletedActivityDTO,
        startDate: Date,
        timeZone: TimeZone = .current
    ) -> ActualsTodayDemoCard {
        let durationSeconds = TimeInterval(activity.durationMin * 60)
        let distanceMeters = activity.distanceKm > 0 ? activity.distanceKm * 1_000 : nil
        let workoutType = StravaActivityClassification.actualsWorkoutType(
            sportType: activity.type,
            title: activity.name
        )
        let unmapped = ActualsUnmappedActivity(
            title: activity.name,
            provider: .strava,
            startDate: startDate,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            calories: nil,
            avgHR: nil,
            type: workoutType,
            stravaTypeRaw: activity.type,
            activityDescription: activity.description
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
        let timeLabel = Self.timeLabel(for: startDate, timeZone: timeZone)
        let cardID = "strava_\(activity.stravaId)"
        // AMA-2407: hydrate Verified from sync flags OR our ownership signature in
        // the Strava description ("— tracked with AmakaFlow"). Signature means
        // already linked — show STRAVA ✓ OURS, never ask to verify again.
        let hasOurSignature = StravaWriteBackDecorator.containsOurSignature(activity.description)
        if activity.amakaflowVerified || activity.amakaflowWroteStrava || hasOurSignature {
            var session = makeVerifiedAsIsSession(cardID: cardID, title: activity.name, activity: unmapped)
            if session.rpe == nil {
                session.rpe = StravaWriteBackDecorator.rpeFromSignedDescription(activity.description)
            }
            let decoration = decorationFromSyncFlags(
                wroteStrava: activity.amakaflowWroteStrava,
                description: activity.description
            )
            let sourceLabel = session.rpe.map { "Verified · RPE \($0)" } ?? "Verified · as-is"
            return ActualsTodayDemoCard(
                id: cardID,
                kind: .verified,
                timeLabel: timeLabel,
                title: activity.name,
                stats: stats,
                sourceLabel: sourceLabel,
                sourceProvider: .strava,
                session: nil,
                activity: unmapped,
                fillInSession: session,
                stravaDecoration: decoration
            )
        }
        return ActualsTodayDemoCard(
            id: cardID,
            kind: .unmapped,
            timeLabel: timeLabel,
            title: activity.name,
            stats: stats,
            sourceLabel: "Synced from \(ActualsCopy.sourceDisplayName(.strava))",
            sourceProvider: .strava,
            session: nil,
            activity: unmapped,
            fillInSession: nil
        )
    }

    // MARK: - Apple Health → cards (AMA-2419)

    static func historyCards(
        from samples: [ActualsHealthKitWorkoutSample],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [(day: Date, cards: [ActualsTodayDemoCard])] {
        _ = now
        let buckets = ActualsDayBucketing.bucketByLocalDay(
            samples,
            startDate: { $0.startDate },
            calendar: calendar
        )
        return buckets.map { day, items in
            (
                day: day,
                cards: items.map { card(from: $0, timeZone: calendar.timeZone) }
            )
        }
    }

    static func cards(
        from samples: [ActualsHealthKitWorkoutSample],
        on day: Date,
        calendar: Calendar = .current
    ) -> [ActualsTodayDemoCard] {
        samples
            .filter { calendar.isDate($0.startDate, inSameDayAs: day) }
            .sorted { $0.startDate > $1.startDate }
            .map { card(from: $0, timeZone: calendar.timeZone) }
    }

    static func card(
        from sample: ActualsHealthKitWorkoutSample,
        timeZone: TimeZone = .current
    ) -> ActualsTodayDemoCard {
        let minutes = max(1, Int(sample.durationSeconds / 60))
        let unmapped = ActualsUnmappedActivity(
            title: sample.title,
            provider: .appleHealth,
            startDate: sample.startDate,
            durationSeconds: sample.durationSeconds,
            distanceMeters: sample.distanceMeters,
            calories: sample.activeEnergyKcal,
            avgHR: sample.averageHeartRateBPM,
            type: sample.activityType
        )
        var stats: [(icon: String, value: String)] = [
            ("clock", "\(minutes)m")
        ]
        if let distanceMeters = sample.distanceMeters, distanceMeters > 0 {
            let kilometers = distanceMeters / 1_000
            let distanceText = kilometers >= 10
                ? String(format: "%.0f km", kilometers)
                : String(format: "%.1f km", kilometers)
            stats.append(("figure.run", distanceText))
        }
        if let kcal = sample.activeEnergyKcal {
            stats.append(("flame.fill", "\(Int(kcal.rounded())) kcal"))
        }
        if let averageHeartRate = sample.averageHeartRateBPM {
            stats.append(("heart.fill", "\(Int(averageHeartRate.rounded())) bpm"))
        }
        return ActualsTodayDemoCard(
            id: "applehealth_\(sample.id)",
            kind: .unmapped,
            timeLabel: timeLabel(for: sample.startDate, timeZone: timeZone),
            title: sample.title,
            stats: stats,
            sourceLabel: "Synced from \(ActualsCopy.sourceDisplayName(.appleHealth))",
            sourceProvider: .appleHealth,
            session: nil,
            activity: unmapped,
            fillInSession: nil
        )
    }

    /// Profile / stats: map Apple Health samples into completion rows.
    static func completions(from samples: [ActualsHealthKitWorkoutSample]) -> [WorkoutCompletion] {
        samples.map { sample in
            WorkoutCompletion(
                id: "applehealth_\(sample.id)",
                workoutName: sample.title,
                startedAt: sample.startDate,
                endedAt: sample.startDate.addingTimeInterval(sample.durationSeconds),
                durationSeconds: max(0, Int(sample.durationSeconds.rounded())),
                avgHeartRate: sample.averageHeartRateBPM.map { Int($0.rounded()) },
                maxHeartRate: nil,
                activeCalories: sample.activeEnergyKcal.map { Int($0.rounded()) },
                distanceMeters: sample.distanceMeters.map { Int($0.rounded()) },
                source: .appleWatch,
                syncedToStrava: false,
                workoutId: nil,
                originalWorkout: nil,
                isSimulated: false
            )
        }
        .sorted { $0.startedAt > $1.startedAt }
    }

    private static func parseStravaStartDate(_ raw: String) -> Date? {
        ActualsDayBucketing.parseISO8601(raw)
    }

    /// AMA-2396: cards for live Strava sync keep the `strava_<id>` prefix through
    /// merge/mapping — extract it so write-back knows which activity to update.
    static func stravaActivityId(fromCardID cardID: String) -> String? {
        let prefix = "strava_"
        guard cardID.hasPrefix(prefix) else { return nil }
        return String(cardID.dropFirst(prefix.count))
    }

    /// AMA-2407: Verify as-is — mark Verified in AmakaFlow, never touch Strava.
    /// 1) build a verified-as-is session, 2) persist locally, 3) call server
    /// verify (no write-back), 4) flip the card to `.verified`/`.untouched`,
    /// 5) broadcast so Today/History re-apply overlays.
    func applyKeepAsIs(unmappedCardID: String, client: BFFStravaClient? = nil) async {
        guard let card = cards.first(where: { $0.id == unmappedCardID }) else { return }
        var verifiedSession = Self.makeVerifiedAsIsSession(
            cardID: card.id,
            title: card.title,
            activity: card.activity
        )
        let description = card.activity?.activityDescription
            ?? verifiedSession.stravaCurrentDescription
            ?? ""
        // Recover RPE from a signed Strava footer before persist — card label and
        // GRDB must agree (CodeRabbit AMA-2407).
        if verifiedSession.rpe == nil {
            verifiedSession.rpe = StravaWriteBackDecorator.rpeFromSignedDescription(description)
        }
        do {
            try repository.upsertVerifiedAsIs(verifiedSession)
        } catch {
            actualsTodayDemoFeedLog.error(
                "Failed to persist verify-as-is for \(card.id, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
        let decoration = Self.decorationForLocalVerifyAsIs(
            sourceProvider: card.sourceProvider ?? card.activity?.provider,
            description: description
        )
        try? repository.storeDecoration(decoration, forSessionID: verifiedSession.id)
        if let index = cards.firstIndex(where: { $0.id == unmappedCardID }) {
            cards[index] = cards[index].markingVerifiedAsIs(
                with: verifiedSession,
                decoration: decoration
            )
        }
        NotificationCenter.default.post(name: .actualsLocalSessionsDidChange, object: nil)

        guard let activityId = verifiedSession.stravaActivityId else { return }
        let verifyClient = client ?? BFFStravaClient.live()
        do {
            _ = try await verifyClient.verifySession(
                activityId: activityId,
                amakaflowSessionId: verifiedSession.id
            )
        } catch {
            // Best-effort — local state already reads Verified; next sync pull
            // reconciles the server flag if this call didn't land.
            actualsTodayDemoFeedLog.error(
                "Strava verify call failed for activity \(activityId, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Synthesize a verified-as-is fill-in session — no exercises/RPE required,
    /// Strava's own metrics stand as the record (AMA-2407).
    static func makeVerifiedAsIsSession(
        cardID: String,
        title: String,
        activity: ActualsUnmappedActivity?
    ) -> ActualsFillInSession {
        ActualsFillInSession(
            id: cardID,
            title: title,
            subtitle: "\(title.uppercased()) · VERIFIED AS-IS",
            exercises: [],
            rpe: nil,
            verified: true,
            stravaActivityId: stravaActivityId(fromCardID: cardID),
            stravaActivityType: activity?.stravaTypeRaw,
            stravaCurrentDescription: activity?.activityDescription,
            stravaRecordingApp: activity?.recordingApp,
            stravaIsRace: activity?.isRace ?? false,
            structureBody: nil
        )
    }

    /// `.ours` when AmakaFlow already wrote Strava (server flag or our own
    /// signature in the description); `.untouched` for a plain verify-as-is.
    static func decorationFromSyncFlags(wroteStrava: Bool, description: String) -> StravaDecorationState {
        if wroteStrava || StravaWriteBackDecorator.containsOurSignature(description) {
            return .ours
        }
        return .untouched
    }

    /// Strava decoration is a statement about Strava — never promote it on
    /// Garmin/Apple Health cards. When the Strava body already carries our
    /// ownership signature, treat as `.ours` (already linked) — not UNTOUCHED.
    static func decorationForLocalVerifyAsIs(
        sourceProvider: ActualsSourceProvider?,
        description: String = ""
    ) -> StravaDecorationState {
        guard sourceProvider == .strava else { return .none }
        return decorationFromSyncFlags(wroteStrava: false, description: description)
    }

    /// AMA-2405: persist a lazy-fetched Strava description onto the card (+ activity-id cache).
    /// AMA-2407: if the text includes our signature, promote to Verified + `.ours`
    /// so athletes never re-verify a session AmakaFlow already wrote.
    func applyActivityDescription(
        cardID: String,
        description: String,
        client: BFFStravaClient? = nil
    ) {
        guard let index = cards.firstIndex(where: { $0.id == cardID }) else { return }
        let updated = Self.applyingDescriptionAndSignedOwnership(
            to: cards[index],
            description: description,
            repository: repository
        )
        let promoted = (updated.kind == .verified && cards[index].kind != .verified)
            || (updated.stravaDecoration == .ours && cards[index].stravaDecoration != .ours)
        cards[index] = updated
        if promoted {
            NotificationCenter.default.post(name: .actualsLocalSessionsDidChange, object: nil)
        }
        let activityId = updated.fillInSession?.stravaActivityId
            ?? Self.stravaActivityId(fromCardID: cardID)
        guard let activityId, !activityId.isEmpty else { return }
        do {
            try repository.upsertStravaActivityDescription(
                activityId: activityId,
                description: description
            )
        } catch {
            // In-memory card already updated; do not roll back UI on persistence failure.
            actualsTodayDemoFeedLog.error(
                "Failed to persist Strava description for activity \(activityId, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
        // Lazy detail is often the first place we see the signature (list sync
        // omits descriptions) — mark that Strava id verified on our server.
        if promoted, StravaWriteBackDecorator.containsOurSignature(description) {
            let sessionId = updated.fillInSession?.id ?? cardID
            Task {
                await self.markServerVerified(
                    activityId: activityId,
                    sessionId: sessionId,
                    client: client
                )
            }
        }
    }

    /// Best-effort POST `/verify` for activities AmakaFlow already linked
    /// (signature or wrote-Strava) but that lack `amakaflow_verified` yet.
    func ensureServerVerifiedForLinkedActivities(
        _ activities: [StravaCompletedActivityDTO],
        client: BFFStravaClient
    ) async {
        for activity in activities {
            let signed = StravaWriteBackDecorator.containsOurSignature(activity.description)
            guard signed || activity.amakaflowWroteStrava else { continue }
            guard !activity.amakaflowVerified else { continue }
            let activityId = String(activity.stravaId)
            let sessionId = "strava_\(activity.stravaId)"
            do {
                _ = try await client.verifySession(
                    activityId: activityId,
                    amakaflowSessionId: sessionId
                )
            } catch {
                actualsTodayDemoFeedLog.error(
                    "Auto-verify failed for linked activity \(activityId, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private func markServerVerified(
        activityId: String,
        sessionId: String,
        client: BFFStravaClient? = nil
    ) async {
        let stravaClient = client ?? BFFStravaClient.live()
        do {
            _ = try await stravaClient.verifySession(
                activityId: activityId,
                amakaflowSessionId: sessionId
            )
        } catch {
            actualsTodayDemoFeedLog.error(
                "Auto-verify failed for activity \(activityId, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Cache description and, when it carries our AmakaFlow signature, flip the
    /// card to Verified + `STRAVA ✓ OURS`. Prefer an existing fill-in / matched
    /// session with exercise rows (image‑1 verified chrome) — never replace that
    /// with verify-as-is + a Strava description dump.
    static func applyingDescriptionAndSignedOwnership(
        to card: ActualsTodayDemoCard,
        description: String,
        repository: ActualsRepository?
    ) -> ActualsTodayDemoCard {
        var next = card.withActivityDescription(description)
        let provider = next.sourceProvider ?? next.activity?.provider
        guard provider == .strava,
              StravaWriteBackDecorator.containsOurSignature(description) else {
            return next
        }
        let activityId = next.fillInSession?.stravaActivityId
            ?? stravaActivityId(fromCardID: next.id)
        let persisted: ActualsFillInSession? = {
            guard let repository, let activityId else { return nil }
            return (try? repository.fetchSessionsKeyedByStravaActivityId())?[activityId]
        }()
        var session = richerFillInSession(
            next.fillInSession,
            persisted,
            fallbackAsIsCardID: next.id,
            title: next.title,
            activity: next.activity
        )
        // Local GRDB may be empty on a fresh sim — recover rows from the
        // signed Strava body we already wrote (same data image‑2 shows).
        if session.exercises.isEmpty {
            let recovered = StravaWorkoutStructureText.fillInExercises(
                fromSignedDescription: description
            )
            if !recovered.isEmpty {
                let rpe = session.rpe
                    ?? StravaWriteBackDecorator.rpeFromSignedDescription(description)
                session = ActualsFillInSession(
                    id: session.id,
                    title: session.title,
                    subtitle: "\(session.title.uppercased()) · MATCHED",
                    exercises: recovered,
                    rpe: rpe,
                    verified: true,
                    stravaActivityId: session.stravaActivityId
                        ?? stravaActivityId(fromCardID: next.id),
                    stravaActivityType: session.stravaActivityType
                        ?? next.activity?.stravaTypeRaw,
                    stravaCurrentDescription: description,
                    stravaRecordingApp: session.stravaRecordingApp
                        ?? next.activity?.recordingApp,
                    stravaIsRace: session.stravaIsRace,
                    structureBody: StravaWorkoutStructureText
                        .structureBodyStrippingOwnershipFooter(description)
                )
            }
        }
        session.verified = true
        session.stravaCurrentDescription = description
        if session.rpe == nil {
            session.rpe = StravaWriteBackDecorator.rpeFromSignedDescription(description)
        }
        if let repository {
            // upsertVerifiedAsIs keeps existing exercise rows when `exercises` is
            // empty, and rewrites them when present — never invents as-is over a
            // richer matched session we already preferred above.
            try? repository.upsertVerifiedAsIs(session)
            try? repository.storeDecoration(.ours, forSessionID: session.id)
        }
        if session.exercises.isEmpty {
            return next.markingVerifiedAsIs(with: session, decoration: .ours)
        }
        // Image‑1 chrome: exercise deltas, not a Strava description dump.
        return next.markingVerified(with: session).withDecoration(.ours)
    }

    /// Prefer the session that still has fill-in exercise rows (post-verify UI).
    static func richerFillInSession(
        _ primary: ActualsFillInSession?,
        _ secondary: ActualsFillInSession?,
        fallbackAsIsCardID: String,
        title: String,
        activity: ActualsUnmappedActivity?
    ) -> ActualsFillInSession {
        let candidates = [primary, secondary].compactMap { $0 }
        if let best = candidates.max(by: { $0.exercises.count < $1.exercises.count }),
           !best.exercises.isEmpty {
            return best
        }
        return primary
            ?? secondary
            ?? makeVerifiedAsIsSession(
                cardID: fallbackAsIsCardID,
                title: title,
                activity: activity
            )
    }

    /// AMA-2396 A3: un-verify — actuals kept as draft, RPE cleared, badge cleared.
    func applyUnverify(sessionID: String) {
        for index in cards.indices {
            guard let saved = cards[index].fillInSession, saved.id == sessionID
                    || cards[index].id == sessionID else { continue }
            var draft = saved
            draft.verified = false
            draft.rpe = nil
            let card = cards[index]
            cards[index] = ActualsTodayDemoCard(
                id: card.id,
                kind: .fillInDebt,
                timeLabel: card.timeLabel,
                title: card.title,
                stats: card.stats,
                sourceLabel: "Fill in · draft",
                sourceProvider: card.sourceProvider,
                session: card.session,
                activity: card.activity,
                fillInSession: draft,
                stravaDecoration: .none
            )
        }
    }

    func applyDecoration(cardID: String, state: StravaDecorationState) {
        guard let index = cards.firstIndex(where: { $0.id == cardID }) else { return }
        cards[index] = cards[index].withDecoration(state)
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
        let fallback = source?.fillInSession
            ?? ActualsFillInSession.lowerBodyPosteriorSample(
                id: "today_demo_fill_\(UUID().uuidString.prefix(6))"
            )
        // Prefer GRDB draft/verified rows so Back → reopen keeps confirmations / RPE.
        let seeded: ActualsFillInSession = {
            if let persisted = try? repository.fetchSession(id: fallback.id) {
                return Self.mergePersistedFillIn(persisted, fallback: fallback)
            }
            return Self.healMisencodedTimeCap(in: fallback)
        }()
        fillInViewModel = ActualsFillInViewModel(session: seeded, repository: repository)
    }

    /// Persist in-progress fill-in when the athlete leaves mid-edit (not verified save).
    @discardableResult
    func persistFillInDraftProgress() -> Bool {
        guard let viewModel = fillInViewModel else { return false }
        do {
            guard try viewModel.persistDraftProgress() else { return false }
            let draft = viewModel.session
            for index in cards.indices {
                let card = cards[index]
                let matchesPending = card.id == pendingFillInCardID
                let matchesSession = card.fillInSession?.id == draft.id || card.id == draft.id
                if matchesPending || matchesSession {
                    cards[index] = card.withFillInSession(draft)
                }
            }
            NotificationCenter.default.post(name: .actualsLocalSessionsDidChange, object: nil)
            return true
        } catch {
            return false
        }
    }

    /// Persisted draft wins for confirmations/RPE; fallback keeps structure/title if richer.
    static func mergePersistedFillIn(
        _ persisted: ActualsFillInSession,
        fallback: ActualsFillInSession
    ) -> ActualsFillInSession {
        var merged = persisted
        if merged.structureBody == nil || merged.structureBody?.isEmpty == true {
            merged.structureBody = fallback.structureBody
        }
        if merged.stravaActivityId == nil {
            merged.stravaActivityId = fallback.stravaActivityId
        }
        if merged.stravaActivityType == nil {
            merged.stravaActivityType = fallback.stravaActivityType
        }
        if merged.exercises.isEmpty {
            merged.exercises = fallback.exercises
        } else if merged.exercises.allSatisfy({ $0.structureHeader == nil }),
                  let body = merged.structureBody ?? fallback.structureBody {
            merged.exercises = StravaWorkoutStructureText.stampingStructureHeaders(
                onto: merged.exercises,
                from: body
            )
        }
        return healMisencodedTimeCap(in: merged)
    }

    /// Fix already-saved fill-in rows that show a minute cap as circuit rounds.
    static func healMisencodedTimeCap(in session: ActualsFillInSession) -> ActualsFillInSession {
        var healed = session
        healed.exercises = StravaWorkoutStructureText.healMisencodedTimeCapRounds(
            exercises: session.exercises
        )
        healed.structureBody = StravaWorkoutStructureText.healMisencodedTimeCapRounds(
            structureBody: session.structureBody
        )
        return healed
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
        let captureWorkout = draft.toWorkoutForMatch()
        let matched = makeMatchedCard(
            request: MatchedCardRequest(
                cardID: unmappedCardID,
                timeLabel: timeLabel,
                title: draft.title,
                activity: activity,
                blockSummaries: draft.blockSummaries.isEmpty
                    ? [draft.title]
                    : draft.blockSummaries,
                sourceLabel: "Matched · \(ActualsCopy.sourceDisplayName(activity?.provider ?? .garmin))",
                workout: captureWorkout
            )
        )
        if let session = matched.fillInSession {
            try? repository.upsertMatchedDraft(session)
            NotificationCenter.default.post(name: .actualsLocalSessionsDidChange, object: nil)
        }
        upsertCard(matched, replacing: unmappedCardID, atFrontIfMissing: true)
    }

    /// Map → picked a library workout: keep the session row, attach that plan for RPE.
    func applyLibraryMatch(
        planTitle: String,
        unmappedCardID: String = "today_demo_unmapped",
        workout: Workout? = nil
    ) {
        let prior = cards.first { $0.id == unmappedCardID }
        let activity = prior?.activity ?? Self.unmappedCard().activity
        let timeLabel = prior?.timeLabel ?? "18:10"
        let summaries: [String] = {
            if let workout {
                let names = workout.blocks.flatMap(\.exercises).map(\.name)
                if !names.isEmpty { return names }
            }
            return [planTitle]
        }()
        let matched = makeMatchedCard(
            request: MatchedCardRequest(
                cardID: unmappedCardID,
                timeLabel: timeLabel,
                title: planTitle,
                activity: activity,
                blockSummaries: summaries,
                sourceLabel: "Matched · \(ActualsCopy.sourceDisplayName(activity?.provider ?? .garmin))",
                workout: workout
            )
        )
        if let session = matched.fillInSession {
            try? repository.upsertMatchedDraft(session)
            NotificationCenter.default.post(name: .actualsLocalSessionsDidChange, object: nil)
        }
        upsertCard(matched, replacing: unmappedCardID, atFrontIfMissing: true)
    }

    /// Re-read GRDB match/verify overlays onto the current Strava cards (Today scrubber).
    func reapplyLocalOverlays() {
        cards = Self.applyLocalOverlays(to: cards, repository: repository)
    }

    /// Merge persisted match/verify sessions onto freshly pulled Strava cards.
    static func applyLocalOverlays(
        to cards: [ActualsTodayDemoCard],
        repository: ActualsRepository
    ) -> [ActualsTodayDemoCard] {
        let cachedDescriptions = (try? repository.fetchCachedStravaDescriptions()) ?? [:]
        let byStrava = ((try? repository.fetchSessionsKeyedByStravaActivityId()) ?? [:])
            .filter { !ActualsRepository.isDescriptionCacheSession(id: $0.value.id) }
        return cards.map { card in
            overlayLocalSession(
                on: applyCachedDescription(to: card, cached: cachedDescriptions),
                byStrava: byStrava,
                repository: repository
            )
        }
    }

    private static func applyCachedDescription(
        to card: ActualsTodayDemoCard,
        cached: [String: String]
    ) -> ActualsTodayDemoCard {
        guard let activityId = stravaActivityId(fromCardID: card.id),
              let description = cached[activityId],
              !description.isEmpty else {
            return card
        }
        let existing = card.activity?.activityDescription
            ?? card.fillInSession?.stravaCurrentDescription
            ?? ""
        guard existing.isEmpty else { return card }
        return card.withActivityDescription(description)
    }

    private static func overlayLocalSession(
        on card: ActualsTodayDemoCard,
        byStrava: [String: ActualsFillInSession],
        repository: ActualsRepository
    ) -> ActualsTodayDemoCard {
        let liveDescription = card.activity?.activityDescription
            ?? card.fillInSession?.stravaCurrentDescription
            ?? ""
        let signed = StravaWriteBackDecorator.containsOurSignature(liveDescription)
            && (card.sourceProvider ?? card.activity?.provider) == .strava
        guard let activityId = stravaActivityId(fromCardID: card.id),
              var session = byStrava[activityId] else {
            guard signed else { return card }
            return applyingDescriptionAndSignedOwnership(
                to: card,
                description: liveDescription,
                repository: repository
            )
        }
        hydrateSessionMetadata(&session, activityId: activityId, from: card.activity)
        var decoration = (try? repository.fetchDecoration(forSessionID: session.id))
            ?? card.stravaDecoration
        let descriptionForDecoration = session.stravaCurrentDescription
            ?? card.activity?.activityDescription
            ?? liveDescription
        if decoration != .ours,
           StravaWriteBackDecorator.containsOurSignature(descriptionForDecoration) {
            decoration = .ours
            try? repository.storeDecoration(.ours, forSessionID: session.id)
        }
        // AMA-2407: server flags win — a stale local draft must never downgrade
        // a card the sync already reports Verified back to fill-in debt.
        if session.verified || card.kind == .verified || signed {
            return verifiedOverlayCard(
                VerifiedOverlayRequest(
                    card: card,
                    session: session,
                    signed: signed,
                    decoration: decoration,
                    descriptionForDecoration: descriptionForDecoration
                ),
                repository: repository
            )
        }
        let matched = makeMatchedCard(
            request: MatchedCardRequest(
                cardID: card.id,
                timeLabel: card.timeLabel,
                title: session.title,
                activity: card.activity,
                blockSummaries: session.exercises.map(\.name),
                sourceLabel: "Matched · \(ActualsCopy.sourceDisplayName(card.activity?.provider ?? .strava))",
                structureBody: session.structureBody,
                seedExercises: session.exercises
            )
        )
        return ActualsTodayDemoCard(
            id: matched.id,
            kind: .fillInDebt,
            timeLabel: matched.timeLabel,
            title: session.title,
            stats: matched.stats,
            sourceLabel: matched.sourceLabel,
            sourceProvider: matched.sourceProvider,
            session: matched.session,
            activity: matched.activity,
            fillInSession: session,
            stravaDecoration: decoration
        )
    }

    private static func hydrateSessionMetadata(
        _ session: inout ActualsFillInSession,
        activityId: String,
        from activity: ActualsUnmappedActivity?
    ) {
        guard let activity else { return }
        if session.stravaActivityId == nil { session.stravaActivityId = activityId }
        if session.stravaActivityType == nil {
            session.stravaActivityType = activity.stravaTypeRaw
        }
        if session.stravaCurrentDescription == nil {
            session.stravaCurrentDescription = activity.activityDescription
        }
        if session.stravaRecordingApp == nil {
            session.stravaRecordingApp = activity.recordingApp
        }
        session.stravaIsRace = activity.isRace
    }

    private struct VerifiedOverlayRequest {
        let card: ActualsTodayDemoCard
        let session: ActualsFillInSession
        let signed: Bool
        let decoration: StravaDecorationState
        let descriptionForDecoration: String
    }

    private static func verifiedOverlayCard(
        _ request: VerifiedOverlayRequest,
        repository: ActualsRepository
    ) -> ActualsTodayDemoCard {
        let card = request.card
        var effectiveSession = richerFillInSession(
            request.session,
            card.fillInSession,
            fallbackAsIsCardID: card.id,
            title: card.title,
            activity: card.activity
        )
        effectiveSession.verified = true
        if effectiveSession.rpe == nil {
            effectiveSession.rpe = StravaWriteBackDecorator.rpeFromSignedDescription(
                request.descriptionForDecoration
            )
        }
        var nextDecoration = request.decoration
        if request.signed || nextDecoration == .ours {
            nextDecoration = .ours
            try? repository.storeDecoration(.ours, forSessionID: effectiveSession.id)
        }
        let sourceLabel = effectiveSession.rpe.map { "Verified · RPE \($0)" }
            ?? (effectiveSession.exercises.isEmpty ? "Verified · as-is" : "Verified")
        return ActualsTodayDemoCard(
            id: card.id,
            kind: .verified,
            timeLabel: card.timeLabel,
            title: effectiveSession.title,
            stats: card.stats,
            sourceLabel: sourceLabel,
            sourceProvider: card.sourceProvider ?? card.activity?.provider ?? .strava,
            session: card.session,
            activity: card.activity,
            fillInSession: effectiveSession,
            stravaDecoration: nextDecoration
        )
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

    struct MatchedCardRequest {
        let cardID: String
        let timeLabel: String
        let title: String
        let activity: ActualsUnmappedActivity?
        let blockSummaries: [String]
        let sourceLabel: String
        /// Full Library workout when Map picks a real plan — seeds steps + Strava text.
        let workout: Workout?
        /// Precomputed structure (e.g. rehydrate from GRDB).
        let structureBody: String?
        let seedExercises: [ExerciseActual]?

        init(
            cardID: String,
            timeLabel: String,
            title: String,
            activity: ActualsUnmappedActivity?,
            blockSummaries: [String],
            sourceLabel: String,
            workout: Workout? = nil,
            structureBody: String? = nil,
            seedExercises: [ExerciseActual]? = nil
        ) {
            self.cardID = cardID
            self.timeLabel = timeLabel
            self.title = title
            self.activity = activity
            self.blockSummaries = blockSummaries
            self.sourceLabel = sourceLabel
            self.workout = workout
            self.structureBody = structureBody
            self.seedExercises = seedExercises
        }
    }

    private func makeMatchedCard(request: MatchedCardRequest) -> ActualsTodayDemoCard {
        Self.makeMatchedCard(request: request)
    }

    /// Shared by Today + History so Map → match always attaches a fill-in session
    /// (RPE / Save / write-back), not just a renamed title.
    static func makeMatchedCard(request: MatchedCardRequest) -> ActualsTodayDemoCard {
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

        let structureBody: String? = {
            if let workout = request.workout {
                let text = StravaWorkoutStructureText.structureBody(from: workout)
                return text.isEmpty ? nil : text
            }
            if let stored = request.structureBody?.trimmingCharacters(in: .whitespacesAndNewlines),
               !stored.isEmpty {
                return stored
            }
            return nil
        }()

        let exercises: [ExerciseActual] = {
            if let seeded = request.seedExercises, !seeded.isEmpty {
                return Array(seeded.prefix(24))
            }
            if let workout = request.workout {
                let fromWorkout = StravaWorkoutStructureText.fillInExercises(from: workout)
                if !fromWorkout.isEmpty { return fromWorkout }
            }
            return blockSummaries.prefix(12).enumerated().map { offset, name in
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
        }()
        let moveCount = max(exercises.count, blockSummaries.count, 1)
        stats.append(("dumbbell.fill", "\(moveCount) moves"))

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
            verified: false,
            stravaActivityId: Self.stravaActivityId(fromCardID: cardID),
            stravaActivityType: activity?.stravaTypeRaw,
            stravaCurrentDescription: activity?.activityDescription,
            stravaRecordingApp: activity?.recordingApp,
            stravaIsRace: activity?.isRace ?? false,
            structureBody: structureBody
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
        let time = Self.timeLabel(for: recording.startDate, timeZone: .current)
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

    /// AMA-2421: format with the same zone used to resolve `start_date_local`.
    private static func timeLabel(for date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

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

/// BFF returned HTTP 200 with `success: false` — not a transport failure.
private struct StravaLogicalSyncFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
