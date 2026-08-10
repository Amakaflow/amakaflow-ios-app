//
//  AMA2396SyncV2Tests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2396: Sync v2 — map v3 CTA state, local-day bucketing, history scrubber,
//  un-verify, Strava badge mapping, and signature idempotency.
//

import XCTest
@testable import AmakaFlowCompanion

@MainActor
final class AMA2396SyncV2Tests: XCTestCase {
    // Held as instance properties (not test-method locals) — releasing a
    // GRDB-backed `ActualsRepository` while still inside XCTest's task-local
    // error-observation scope hits a Swift 6 concurrency runtime crash
    // (isolated-deinit + TaskLocal teardown). Matches `ActualsFillInTests`.
    private var db: AppDatabase!
    private var repo: ActualsRepository!

    override func setUp() async throws {
        db = try AppDatabase.makeTestDatabase()
        repo = ActualsRepository(database: db, now: { Date(timeIntervalSince1970: 1_700_000_000) })
    }

    // MARK: - Map v3 pinned CTA state machine

    func testMapCTANoneSelectionIsKeepAsIs() {
        let kind = ActualsMapCTAState.kind(selectedMatchTitle: nil, activityTitle: "Afternoon run")
        XCTAssertEqual(kind, .keepAsIs)
        XCTAssertEqual(
            ActualsMapCTAState.label(selectedMatchTitle: nil, activityTitle: "Afternoon run"),
            ActualsCopy.mapKeepAsDoneCTA(title: "Afternoon run")
        )
        XCTAssertFalse(ActualsMapCTAState.isMatchSelected(nil))
    }

    func testMapCTASelectingCandidateBecomesMatch() {
        let kind = ActualsMapCTAState.kind(selectedMatchTitle: "Tempo intervals", activityTitle: "Afternoon run")
        XCTAssertEqual(kind, .match(title: "Tempo intervals"))
        XCTAssertEqual(
            ActualsMapCTAState.label(selectedMatchTitle: "Tempo intervals", activityTitle: "Afternoon run"),
            ActualsCopy.mapMatchToCTA(title: "Tempo intervals")
        )
        XCTAssertTrue(ActualsMapCTAState.isMatchSelected("Tempo intervals"))
    }

    func testMapCTADeselectRevertsToKeepAsIs() {
        // Selecting then deselecting (empty title) must fall back to keep-as-is,
        // matching the view's `selectedMatchID = selected ? nil : match.id` toggle.
        let afterDeselect = ActualsMapCTAState.kind(selectedMatchTitle: nil, activityTitle: "Erg cardio")
        XCTAssertEqual(afterDeselect, .keepAsIs)

        let emptyTitle = ActualsMapCTAState.kind(selectedMatchTitle: "", activityTitle: "Erg cardio")
        XCTAssertEqual(emptyTitle, .keepAsIs)
        XCTAssertFalse(ActualsMapCTAState.isMatchSelected(""))
    }

    // MARK: - Day bucketing: local day, not UTC

    /// Named regression: 18:34 local sorts above 12:19 local on the same day.
    func testEveningActivitySortsAboveMiddayOnSameLocalDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!

        let evening = StravaCompletedActivityDTO(
            stravaId: 1,
            name: "Evening ride",
            type: "Ride",
            distanceKm: 20,
            durationMin: 45,
            startDate: "2026-08-09T22:34:00Z",
            startDateLocal: "2026-08-09T18:34:00",
            description: ""
        )
        let midday = StravaCompletedActivityDTO(
            stravaId: 2,
            name: "Midday run",
            type: "Run",
            distanceKm: 8,
            durationMin: 40,
            startDate: "2026-08-09T16:19:00Z",
            startDateLocal: "2026-08-09T12:19:00",
            description: ""
        )

        let cards = ActualsTodayDemoFeed.cards(
            from: [midday, evening],
            calendar: calendar,
            now: Self.date("2026-08-09T23:00:00Z")
        )

        XCTAssertEqual(cards.count, 2)
        XCTAssertEqual(cards.first?.title, "Evening ride", "18:34 must sort above 12:19 on the same local day")
        XCTAssertEqual(cards.last?.title, "Midday run")
    }

    /// UTC-crossing: a late-evening US Pacific activity is still "today" UTC-wise
    /// the *next* day — `start_date_local` must win so it lands on the athlete's day.
    func testUTCCrossingActivityLandsOnAthletesLocalDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        // 23:15 local Aug 9 == 06:15 UTC Aug 10 — a naive UTC bucket would file
        // this under Aug 10, not the athlete's Aug 9.
        let lateNight = StravaCompletedActivityDTO(
            stravaId: 3,
            name: "Late night lift",
            type: "WeightTraining",
            distanceKm: 0,
            durationMin: 50,
            startDate: "2026-08-10T06:15:00Z",
            startDateLocal: "2026-08-09T23:15:00",
            description: ""
        )

        let resolved = ActualsTodayDemoFeed.resolveStartDate(lateNight, calendar: calendar)
        XCTAssertNotNil(resolved)
        let localDay = calendar.component(.day, from: resolved!)
        XCTAssertEqual(localDay, 9, "start_date_local must win over the UTC calendar day")

        let aug9 = Self.date("2026-08-09T20:00:00Z") // still Aug 9 in Los Angeles (13:00 local)
        let cardsForAug9 = ActualsTodayDemoFeed.cards(
            from: [lateNight],
            on: calendar.startOfDay(for: Self.date("2026-08-09T20:00:00-07:00")),
            calendar: calendar,
            now: aug9
        )
        XCTAssertEqual(cardsForAug9.count, 1)
        XCTAssertEqual(cardsForAug9.first?.title, "Late night lift")
    }

    func testHistoryDayHeaderFormat() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let saturday = Self.date("2026-08-08T12:00:00Z") // Aug 8 2026 is a Saturday
        let header = ActualsDayBucketing.historyDayHeader(for: saturday, calendar: calendar)
        XCTAssertEqual(header, "SAT · AUG 8")
    }

    // MARK: - History scrubber (past 30 navigable, future dimmed/planned-only)

    func testScrubberNavigableRangeCoversPast30DaysThroughToday() {
        let now = Self.date("2026-08-09T12:00:00Z")
        let range = ActualsHistoryScrubber.navigableRange(now: now)
        XCTAssertNotNil(range)
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: range!.start, to: range!.end).day
        XCTAssertEqual(days, ActualsHistoryScrubber.lookbackDays - 1)
        XCTAssertEqual(calendar.startOfDay(for: range!.end), calendar.startOfDay(for: now))
    }

    func testScrubberFutureSlotIsDimmedPlannedOnlyNotSelectable() {
        let now = Self.date("2026-08-09T12:00:00Z")
        let days = ActualsHistoryScrubber.days(activityDates: [], now: now, includeFuturePlannedSlot: true)
        guard let future = days.last else {
            return XCTFail("expected at least one day in the scrubber window")
        }
        XCTAssertTrue(future.isFuture)
        XCTAssertFalse(future.isSelectable, "future days are planned-only — never scrubbable as history")
    }

    func testScrubberPastDaysAreAllSelectable() {
        let now = Self.date("2026-08-09T12:00:00Z")
        let days = ActualsHistoryScrubber.days(activityDates: [], now: now, includeFuturePlannedSlot: true)
        for day in days where !day.isFuture {
            XCTAssertTrue(day.isSelectable)
        }
        XCTAssertTrue(days.contains { $0.isToday })
    }

    // MARK: - Un-verify: verified → draft, RPE cleared

    func testUnverifySessionClearsVerifiedAndRPEKeepsExerciseRows() throws {
        var session = ActualsFillInSession.lowerBodyPosteriorSample(id: "unverify_\(UUID().uuidString)")
        session.exercises = session.exercises.map { exercise in
            var copy = exercise
            copy.confirmation = .asPlanned
            return copy
        }
        session.rpe = 7
        session.verified = true
        try repo.saveVerifiedSession(session)

        try repo.unverifySession(id: session.id)

        let reloaded = try repo.fetchSession(id: session.id)
        XCTAssertNotNil(reloaded)
        XCTAssertEqual(reloaded?.verified, false)
        XCTAssertNil(reloaded?.rpe)
        // Exercise rows survive — un-verify is a draft, not a delete.
        XCTAssertEqual(reloaded?.exercises.count, session.exercises.count)
    }

    func testFeedApplyUnverifyMarksCardAsFillInDraft() {
        let feed = ActualsTodayDemoFeed(repository: repo)
        // Seed a fill-in-debt card so `prepareFillIn`/`markVerified` have a row to flip.
        feed.activateAfterConnect(sync: ActualsSyncProgressStore())

        var session = ActualsFillInSession.lowerBodyPosteriorSample(id: "feed_unverify")
        session.rpe = 6
        session.verified = true
        feed.prepareFillIn()
        feed.markVerified(saved: session)

        feed.applyUnverify(sessionID: session.id)

        let card = feed.cards.first { $0.fillInSession?.id == session.id || $0.id == session.id }
        XCTAssertEqual(card?.kind, .fillInDebt)
        XCTAssertNil(card?.fillInSession?.rpe)
        XCTAssertEqual(card?.fillInSession?.verified, false)
    }

    // MARK: - Badge mapping

    func testBadgeLabelMapping() {
        XCTAssertEqual(StravaDecorationState.ours.badgeLabel, "STRAVA ✓ OURS")
        XCTAssertEqual(StravaDecorationState.skipped(rule: .virtual).badgeLabel, "STRAVA · SKIPPED")
        XCTAssertEqual(StravaDecorationState.untouched.badgeLabel, "STRAVA · UNTOUCHED")
        XCTAssertNil(StravaDecorationState.none.badgeLabel)
    }

    func testDecorationPersistedRawValueRoundTrips() {
        for state: StravaDecorationState in [.ours, .untouched, .none, .skipped(rule: .described), .skipped(rule: .race)] {
            let raw = state.persistedRawValue
            let restored = StravaDecorationState(persistedRawValue: raw)
            XCTAssertEqual(restored, state)
        }
    }

    // MARK: - Signature idempotency

    func testDecorateTwiceIsByteIdentical() {
        let once = StravaWriteBackDecorator.decorate(description: "Great session today")
        let twice = StravaWriteBackDecorator.decorate(description: once)
        XCTAssertEqual(once, twice)
        XCTAssertEqual(once.components(separatedBy: StravaWriteBackSignature.line).count, 2)
    }

    func testDecorateEmptyDescriptionIsJustSignature() {
        let decorated = StravaWriteBackDecorator.decorate(description: "")
        XCTAssertEqual(decorated, StravaWriteBackSignature.line)
        let decoratedAgain = StravaWriteBackDecorator.decorate(description: decorated)
        XCTAssertEqual(decorated, decoratedAgain)
    }

    func testWriteBackSignatureLineMatchesTrackedCopy() {
        XCTAssertEqual(StravaWriteBackSignature.line, "— tracked with AmakaFlow")
    }

    func testLibraryWorkoutResolverParsesNamedTimedStepsFromBlocksJSON() throws {
        let base = Workout(
            id: "bike-ski-row",
            name: "Bike ski row repeats",
            sport: .mixed,
            duration: 77 * 60,
            blocks: [
                Block(
                    label: nil,
                    structure: .circuit,
                    rounds: 6,
                    exercises: [
                        Exercise(
                            name: "Timed Work",
                            canonicalName: nil,
                            sets: 1,
                            reps: nil,
                            durationSeconds: 180,
                            load: nil,
                            restSeconds: nil,
                            distance: nil,
                            notes: nil,
                            focus: nil,
                            supersetGroup: nil
                        )
                    ]
                )
            ],
            source: .manual
        )
        XCTAssertTrue(ActualsLibraryWorkoutResolver.looksPlaceholder(base))

        let data: [String: Any] = [
            "title": "Bike ski row repeats",
            "sport": "mixed",
            "blocks": [
                [
                    "label": "Circuit",
                    "type": "circuit",
                    "rounds": 6,
                    "exercises": [
                        ["name": "Assault Bike", "duration_sec": 180, "sets": 1],
                        ["name": "Ski Erg", "duration_sec": 180, "sets": 1],
                        ["name": "Rowing Machine", "duration_sec": 180, "sets": 1],
                        ["name": "Spin / Indoor Bike", "duration_sec": 180, "sets": 1]
                    ]
                ]
            ]
        ]
        let resolved = try XCTUnwrap(
            ActualsLibraryWorkoutResolver.workout(fromBlocksJSON: data, base: base)
        )
        XCTAssertFalse(ActualsLibraryWorkoutResolver.looksPlaceholder(resolved))
        let names = resolved.blocks.flatMap(\.exercises).map(\.name)
        XCTAssertEqual(names, [
            "Assault Bike", "Ski Erg", "Rowing Machine", "Spin / Indoor Bike"
        ])
        let body = StravaWorkoutStructureText.structureBody(from: resolved)
        XCTAssertTrue(body.contains("Assault Bike"))
        XCTAssertTrue(body.contains("🚴") || body.contains("⛷️") || body.contains("🚣"))
        XCTAssertFalse(body.contains("Timed Work"))
    }

    func testStructureBodyIncludesCircuitRoundsAndEquipmentEmoji() {
        let workout = Workout(
            id: "bike-ski-row",
            name: "Bike ski row repeats",
            sport: .mixed,
            duration: 77 * 60,
            blocks: [
                Block(
                    label: "Circuit",
                    structure: .circuit,
                    rounds: 6,
                    exercises: [
                        Exercise(
                            name: "Assault Bike",
                            canonicalName: nil,
                            sets: 1,
                            reps: nil,
                            durationSeconds: 180,
                            load: nil,
                            restSeconds: nil,
                            distance: nil,
                            notes: nil,
                            focus: nil,
                            supersetGroup: nil
                        ),
                        Exercise(
                            name: "Ski Erg",
                            canonicalName: nil,
                            sets: 1,
                            reps: nil,
                            durationSeconds: 180,
                            load: nil,
                            restSeconds: nil,
                            distance: nil,
                            notes: nil,
                            focus: nil,
                            supersetGroup: nil
                        ),
                        Exercise(
                            name: "Rowing Machine",
                            canonicalName: nil,
                            sets: 1,
                            reps: nil,
                            durationSeconds: 180,
                            load: nil,
                            restSeconds: nil,
                            distance: nil,
                            notes: nil,
                            focus: nil,
                            supersetGroup: nil
                        ),
                        Exercise(
                            name: "Spin / Indoor Bike",
                            canonicalName: nil,
                            sets: 1,
                            reps: nil,
                            durationSeconds: 180,
                            load: nil,
                            restSeconds: nil,
                            distance: nil,
                            notes: nil,
                            focus: nil,
                            supersetGroup: nil
                        )
                    ]
                )
            ],
            source: .manual
        )
        let body = StravaWorkoutStructureText.structureBody(from: workout)
        XCTAssertTrue(body.contains("6 ROUNDS"))
        XCTAssertTrue(body.contains("🚴"))
        XCTAssertTrue(body.contains("⛷️"))
        XCTAssertTrue(body.contains("🚣"))
        XCTAssertTrue(body.contains("Assault Bike"))
        XCTAssertTrue(body.contains("Ski Erg"))
        XCTAssertTrue(body.contains("Rowing Machine"))
        XCTAssertTrue(body.contains("Spin / Indoor Bike"))
        XCTAssertTrue(body.contains("3:00") || body.contains("180"))
        let exercises = StravaWorkoutStructureText.fillInExercises(from: workout)
        XCTAssertEqual(exercises.count, 4)
        XCTAssertEqual(exercises[0].planned.note, "3:00")
    }

    func testEvaluatePreservesForeignDescriptionWhenSkipDescribedOff() throws {
        let decision = StravaWriteBackDecorator.evaluate(
            StravaWriteBackEvaluateInput(
                activityType: "Run",
                recordingApp: nil,
                description: "Coach notes from another app",
                isRace: false,
                rules: StravaWriteBackRules(
                    skipVirtual: true,
                    skipDescribed: false,
                    skipRaces: true
                ),
                structureBody: "Back squat: 3×5",
                rpe: 7
            )
        )
        XCTAssertTrue(decision.shouldWrite)
        XCTAssertEqual(decision.state, .ours)
        let decorated = try XCTUnwrap(decision.decoratedDescription)
        XCTAssertTrue(decorated.hasPrefix("Coach notes from another app"))
        XCTAssertTrue(decorated.contains("Back squat: 3×5"))
        XCTAssertTrue(decorated.contains(StravaWriteBackSignature.line))
    }

    func testEvaluateSkipsDescribedWhenRuleOn() {
        let decision = StravaWriteBackDecorator.evaluate(
            StravaWriteBackEvaluateInput(
                activityType: "Run",
                recordingApp: nil,
                description: "Someone else's words",
                isRace: false,
                rules: .default,
                structureBody: "Tempo: 4×8",
                rpe: nil
            )
        )
        XCTAssertFalse(decision.shouldWrite)
        if case .skipped(rule: .described) = decision.state {
            // expected
        } else {
            XCTFail("expected skipped(described), got \(decision.state)")
        }
        XCTAssertNil(decision.decoratedDescription)
    }

    func testMarkingCountedPromotesDecorationOnlyForStrava() {
        let garmin = ActualsTodayDemoCard(
            id: "garmin_1",
            kind: .unmapped,
            timeLabel: "12:00",
            title: "Easy spin",
            stats: [],
            sourceLabel: "Garmin",
            sourceProvider: .garmin,
            session: nil,
            activity: nil,
            fillInSession: nil,
            stravaDecoration: .none
        ).markingCounted()
        XCTAssertEqual(garmin.stravaDecoration, .none)

        let strava = ActualsTodayDemoCard(
            id: "strava_1",
            kind: .unmapped,
            timeLabel: "12:00",
            title: "Easy run",
            stats: [],
            sourceLabel: "Strava",
            sourceProvider: .strava,
            session: nil,
            activity: nil,
            fillInSession: nil,
            stravaDecoration: .none
        ).markingCounted()
        XCTAssertEqual(strava.stravaDecoration, .untouched)
    }

    func testFillInSessionRequiresWriteBackMetadata() {
        var session = ActualsFillInSession.lowerBodyPosteriorSample()
        session.stravaActivityId = "99"
        XCTAssertFalse(session.canEvaluateStravaWriteBack)
        session.stravaActivityType = "Run"
        XCTAssertTrue(session.canEvaluateStravaWriteBack)
    }

    func testScrubberReturnsFullLookbackStrip() {
        let now = Self.date("2026-08-09T12:00:00Z")
        let days = ActualsHistoryScrubber.days(
            activityDates: [],
            now: now,
            includeFuturePlannedSlot: true
        )
        // 30 past days through today (30) + 1 future slot.
        XCTAssertEqual(days.count, ActualsHistoryScrubber.lookbackDays + 1)
        XCTAssertTrue(days.contains { $0.isToday })
        XCTAssertEqual(days.filter(\.isFuture).count, 1)
    }

    // MARK: - Helpers

    private static func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: iso) {
            return date
        }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fallback.date(from: iso) {
            return date
        }
        XCTFail("unparseable fixture date: \(iso)")
        return Date.distantPast
    }

    func testLibraryCandidateIncludesBikeSkiRowRepeatsTitle() {
        let workout = Workout(
            id: "lib_bike_ski",
            name: "Bike ski row repeats",
            sport: .cardio,
            duration: 60,
            blocks: [
                Block(
                    label: "Circuit",
                    structure: .circuit,
                    rounds: 6,
                    exercises: [
                        Exercise(name: "Assault Bike", canonicalName: nil, sets: 1, reps: nil, durationSeconds: 180, load: nil, restSeconds: nil, distance: nil, notes: nil, focus: nil, supersetGroup: nil),
                        Exercise(name: "Ski Erg", canonicalName: nil, sets: 1, reps: nil, durationSeconds: 180, load: nil, restSeconds: nil, distance: nil, notes: nil, focus: nil, supersetGroup: nil),
                        Exercise(name: "Rowing Machine", canonicalName: nil, sets: 1, reps: nil, durationSeconds: 180, load: nil, restSeconds: nil, distance: nil, notes: nil, focus: nil, supersetGroup: nil),
                        Exercise(name: "Spin / Indoor Bike", canonicalName: nil, sets: 1, reps: nil, durationSeconds: 180, load: nil, restSeconds: nil, distance: nil, notes: nil, focus: nil, supersetGroup: nil)
                    ]
                )
            ],
            source: .manual
        )
        let candidates = ActualsPlanCandidate.fromLibrary([workout])
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].title, "Bike ski row repeats")
        // 6 rounds × 4 × 180s = 4320s — not the broken ~1 MIN wire duration.
        XCTAssertEqual(candidates[0].durationSeconds, 4320)
        XCTAssertEqual(candidates[0].type, .other)
    }

}
