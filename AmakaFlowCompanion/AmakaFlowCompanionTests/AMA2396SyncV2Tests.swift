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
        calendar.locale = Locale(identifier: "en_US_POSIX")
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

    /// Most common path: class / Garmin strength → Build it (no Library match).
    func testCaptureFromScratchSeedsFillInAndStravaStructureWithoutLibraryMatch() throws {
        let draft = ActualsCaptureDraft.sampleHyrox()
        let workout = try XCTUnwrap(draft.toWorkoutForMatch())
        XCTAssertEqual(workout.blocks.flatMap(\.exercises).map(\.name), [
            "Ski erg", "Sled push", "Wall balls", "Burpee broad jump"
        ])

        var activity = ActualsUnmappedActivity(
            title: "Evening Weight Training",
            provider: .strava,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 45 * 60,
            distanceMeters: nil,
            calories: 126,
            avgHR: 89,
            type: .strength
        )
        activity.stravaTypeRaw = "WeightTraining"

        let card = ActualsTodayDemoFeed.makeMatchedCard(
            request: .init(
                cardID: "strava_evening_wt",
                timeLabel: "18:34",
                title: draft.title,
                activity: activity,
                blockSummaries: draft.blockSummaries,
                sourceLabel: "Matched · Strava",
                workout: workout
            )
        )
        XCTAssertEqual(card.kind, .fillInDebt)
        let session = try XCTUnwrap(card.fillInSession)
        XCTAssertEqual(session.exercises.map(\.name), [
            "Ski erg", "Sled push", "Wall balls", "Burpee broad jump"
        ])
        XCTAssertFalse(session.exercises.contains { $0.name == "Unknown" })
        XCTAssertTrue(session.stravaStructureBody.contains("Ski erg"))
        XCTAssertTrue(session.stravaStructureBody.contains("Wall balls"))
        XCTAssertEqual(session.stravaActivityId, "evening_wt")
        XCTAssertTrue(session.canEvaluateStravaWriteBack)

        let decision = StravaWriteBackDecorator.evaluate(
            StravaWriteBackEvaluateInput(
                activityType: session.stravaActivityType ?? "",
                recordingApp: session.stravaRecordingApp,
                description: session.stravaCurrentDescription ?? "",
                isRace: session.stravaIsRace,
                rules: .default,
                structureBody: session.stravaStructureBody,
                rpe: 7
            )
        )
        XCTAssertTrue(decision.shouldWrite)
        let decorated = try XCTUnwrap(decision.decoratedDescription)
        XCTAssertTrue(decorated.contains("Ski erg"))
        XCTAssertTrue(decorated.contains(StravaWriteBackSignature.line))
        XCTAssertFalse(decorated.contains("Unknown"))
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
        let base = placeholderBikeSkiRowWorkout()
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
        assertBikeSkiRowResolved(resolved)
    }

    func testLibraryWorkoutResolverUsesIntervalsWhenBlocksArePlaceholderTimedWork() throws {
        let base = placeholderBikeSkiRowWorkout()
        // Dogfood shape: empty/placeholder blocks + intervals with name and target:null.
        let data: [String: Any] = [
            "title": "Bike ski row repeats",
            "sport": "mixed",
            "blocks": [
                [
                    "type": "circuit",
                    "rounds": 6,
                    "exercises": [
                        ["name": "Timed Work", "duration_sec": 180, "sets": 1],
                        ["name": "Timed Work", "duration_sec": 180, "sets": 1],
                        ["name": "Timed Work", "duration_sec": 180, "sets": 1],
                        ["name": "Timed Work", "duration_sec": 180, "sets": 1]
                    ]
                ]
            ],
            "intervals": [
                ["kind": "round_start", "rounds": 6],
                ["kind": "time", "seconds": 180, "name": "Assault Bike", "target": NSNull()],
                ["kind": "time", "seconds": 180, "name": "Ski Erg", "target": NSNull()],
                ["kind": "time", "seconds": 180, "name": "Rowing Machine", "target": NSNull()],
                ["kind": "time", "seconds": 180, "name": "Spin / Indoor Bike", "target": NSNull()]
            ]
        ]
        let resolved = try XCTUnwrap(
            ActualsLibraryWorkoutResolver.workout(fromBlocksJSON: data, base: base)
        )
        assertBikeSkiRowResolved(resolved)
        XCTAssertEqual(resolved.blocks.first?.rounds, 6)
        XCTAssertEqual(resolved.blocks.first?.structure, .circuit)
        let fillIn = StravaWorkoutStructureText.fillInExercises(from: resolved)
        XCTAssertEqual(fillIn.map(\.name), [
            "Assault Bike", "Ski Erg", "Rowing Machine", "Spin / Indoor Bike"
        ])
        let body = StravaWorkoutStructureText.structureBody(from: resolved)
        XCTAssertTrue(body.contains("6 ROUNDS"))
    }

    func testTimedIntervalDecodesMachineNameFromNameWhenTargetNull() throws {
        let json = """
        {"kind":"time","seconds":180,"name":"Assault Bike","target":null}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WorkoutInterval.self, from: json)
        guard case .time(let seconds, let target) = decoded else {
            return XCTFail("expected time interval")
        }
        XCTAssertEqual(seconds, 180)
        XCTAssertEqual(target, "Assault Bike")
    }

    private func placeholderBikeSkiRowWorkout() -> Workout {
        Workout(
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
    }

    private func assertBikeSkiRowResolved(_ resolved: Workout) {
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
        XCTAssertEqual(exercises[0].planned.sets, 6)
        XCTAssertEqual(exercises[0].planned.displayLine, "6 × 3:00")
        let verified = ActualsVerifiedDeltas.rows(from: exercises.map {
            var row = $0
            row.confirmation = .asPlanned
            return row
        })
        XCTAssertEqual(verified[0].actualLine, "6 × 3:00")
    }

    // MARK: - Exhaustive Library structure → fill-in / Strava / Garmin

    func testNestedRepeatIntervalsResolveNamesAndRounds() throws {
        let data: [String: Any] = [
            "title": "Bike ski row repeats",
            "intervals": [
                [
                    "kind": "repeat",
                    "reps": 6,
                    "intervals": [
                        ["kind": "time", "seconds": 180, "name": "Assault Bike", "target": NSNull()],
                        ["kind": "time", "seconds": 180, "target": "Ski Erg"],
                        ["kind": "time", "seconds": 180, "name": "Rowing Machine"],
                        ["kind": "time", "seconds": 180, "name": "Spin / Indoor Bike", "target": ""]
                    ]
                ]
            ]
        ]
        let resolved = try XCTUnwrap(
            ActualsLibraryWorkoutResolver.workout(
                fromBlocksJSON: data,
                base: placeholderBikeSkiRowWorkout()
            )
        )
        assertBikeSkiRowResolved(resolved)
        XCTAssertEqual(resolved.blocks.first?.rounds, 6)
        XCTAssertEqual(resolved.blocks.first?.structure, .circuit)
    }

    func testStrengthStraightSetsKeepPerExerciseSets() throws {
        let workout = Workout(
            id: "strength",
            name: "Lower body",
            sport: .strength,
            duration: 45 * 60,
            blocks: [
                Block(
                    label: "Main",
                    structure: .straight,
                    rounds: 1,
                    exercises: [
                        Exercise(
                            name: "Back squat",
                            canonicalName: nil,
                            sets: 3,
                            reps: "5",
                            durationSeconds: nil,
                            load: ExerciseLoad(value: 85, unit: "kg"),
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
        let rows = StravaWorkoutStructureText.fillInExercises(from: workout)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].planned.sets, 3)
        XCTAssertEqual(rows[0].planned.reps, 5)
        XCTAssertEqual(rows[0].planned.weightKg, 85)
        let body = StravaWorkoutStructureText.structureBody(from: workout)
        XCTAssertTrue(body.contains("Back squat"))
        XCTAssertFalse(body.contains("Timed Work"))
    }

    func testTriSetBlocksStampFillInAndVerifiedStructureBands() {
        func station(_ name: String, kilograms: Double?) -> Exercise {
            Exercise(
                name: name,
                canonicalName: nil,
                sets: 3,
                reps: "10",
                durationSeconds: nil,
                load: kilograms.map { ExerciseLoad(value: $0, unit: "kg") },
                restSeconds: nil,
                distance: nil,
                notes: nil,
                focus: nil,
                supersetGroup: nil
            )
        }
        let workout = Workout(
            id: "tri",
            name: "Upper Body Tri Sets",
            sport: .strength,
            duration: 56 * 60,
            blocks: [
                Block(
                    label: "Tri-set",
                    structure: .superset,
                    rounds: 3,
                    exercises: [
                        station("Pull Ups", kilograms: nil),
                        station("Single Arm Row", kilograms: 20),
                        station("Forearm Twist", kilograms: 5)
                    ]
                ),
                Block(
                    label: "Tri-set",
                    structure: .superset,
                    rounds: 3,
                    exercises: [
                        station("Dumbbell Press", kilograms: 20),
                        station("Band Pull Apart", kilograms: nil),
                        station("TRX Tricep Extension", kilograms: nil)
                    ]
                )
            ],
            source: .manual
        )
        let body = StravaWorkoutStructureText.structureBody(from: workout)
        XCTAssertTrue(body.contains("TRI-SET · 3 ROUNDS"))
        let rows = StravaWorkoutStructureText.fillInExercises(from: workout)
        XCTAssertEqual(rows.count, 6)
        XCTAssertEqual(rows[0].structureHeader, "TRI-SET · 3 ROUNDS")
        XCTAssertEqual(rows[0].structureBlockIndex, 0)
        XCTAssertEqual(rows[3].structureHeader, "TRI-SET · 3 ROUNDS")
        XCTAssertEqual(rows[3].structureBlockIndex, 1)

        let session = ActualsFillInSession(
            id: "tri_fill",
            title: workout.name,
            subtitle: "UPPER BODY TRI SETS · MATCHED",
            exercises: rows.map {
                var row = $0
                row.confirmation = .asPlanned
                return row
            },
            verified: true,
            structureBody: body
        )
        XCTAssertEqual(session.structureSections.count, 2)
        XCTAssertEqual(session.structureSections[0].header, "TRI-SET · 3 ROUNDS")
        XCTAssertEqual(session.structureSections[0].exercises.count, 3)
        XCTAssertEqual(session.structureSections[1].exercises.map(\.name).first, "Dumbbell Press")

        // Rows saved without headers still recover bands from structureBody.
        let bare = rows.map {
            ExerciseActual(id: $0.id, name: $0.name, planned: $0.planned)
        }
        let recovered = ActualsFillInSession(
            id: "tri_recover",
            title: workout.name,
            subtitle: "MATCHED",
            exercises: bare,
            verified: false,
            structureBody: body
        )
        XCTAssertEqual(recovered.exercises[0].structureHeader, "TRI-SET · 3 ROUNDS")
        XCTAssertEqual(recovered.structureSections.count, 2)
    }

    func testEMOMRoundsSeedFillInSets() {
        let workout = Workout(
            id: "emom",
            name: "Engine EMOM",
            sport: .conditioning,
            duration: 20 * 60,
            blocks: [
                Block(
                    label: nil,
                    structure: .emom,
                    rounds: 10,
                    exercises: [
                        Exercise(
                            name: "Burpee",
                            canonicalName: nil,
                            sets: 1,
                            reps: "5",
                            durationSeconds: nil,
                            load: nil,
                            restSeconds: nil,
                            distance: nil,
                            notes: nil,
                            focus: nil,
                            supersetGroup: nil
                        ),
                        Exercise(
                            name: "Cal row",
                            canonicalName: nil,
                            sets: 1,
                            reps: nil,
                            durationSeconds: nil,
                            load: nil,
                            restSeconds: nil,
                            distance: 15,
                            notes: nil,
                            focus: nil,
                            supersetGroup: nil
                        )
                    ]
                )
            ],
            source: .manual
        )
        let rows = StravaWorkoutStructureText.fillInExercises(from: workout)
        XCTAssertEqual(rows.map(\.planned.sets), [10, 10])
        XCTAssertEqual(rows[1].planned.displayLine, "10 × 15 m")
        let body = StravaWorkoutStructureText.structureBody(from: workout)
        XCTAssertTrue(body.contains("10 ROUNDS"))
        XCTAssertTrue(body.contains("Burpee"))
        XCTAssertTrue(body.contains("Cal row"))
    }

    /// For-time 60 min cap must not become "60 ROUNDS" / "60 × 3:00" after Strava match.
    func testForTimeCapDoesNotSeedAsCircuitRounds() throws {
        var session = EditorV2Session(title: "Ski Row Assault")
        let groupKey = session.startFormat(.fortime)
        session.updateGroup(groupKey) { $0.config.capMinutes = 60 }
        for name in ["Ski Erg", "Rowing Machine", "Assault Bike"] {
            let exercise = session.addExercise(named: name)
            session.updateExercise(exercise.id) {
                $0.durationSeconds = 180
                $0.reps = nil
                $0.sets = nil
            }
        }

        let blocks = session.toSocialImportBlocks()
        let block = try XCTUnwrap(blocks.first)
        XCTAssertEqual(block.type, "for-time")
        XCTAssertEqual(block.rounds, 1)
        XCTAssertEqual(block.timeCapSec, 60 * 60)
        XCTAssertTrue(block.label?.localizedCaseInsensitiveContains("60") == true)
        XCTAssertTrue(block.label?.localizedCaseInsensitiveContains("cap") == true)

        let draft = ActualsCaptureDraft(
            id: "ft-60",
            title: "Ski Row Assault bike 3 min each x 6",
            blockSummaries: ["Ski Erg", "Rowing Machine", "Assault Bike"],
            estimatedMinutes: 60,
            source: .built,
            sport: WorkoutSport.conditioning.rawValue,
            intervals: [],
            blocks: blocks
        )
        let workout = try XCTUnwrap(draft.toWorkoutForMatch())
        XCTAssertEqual(workout.blocks.first?.rounds, 1)
        let rows = StravaWorkoutStructureText.fillInExercises(from: workout)
        XCTAssertEqual(rows.count, 3)
        let header = try XCTUnwrap(rows.first?.structureHeader)
        XCTAssertFalse(header.contains("60 ROUNDS"))
        XCTAssertTrue(header.localizedCaseInsensitiveContains("for time")
            || header.localizedCaseInsensitiveContains("60"))
        XCTAssertEqual(rows.map(\.planned.sets), [1, 1, 1])
        XCTAssertEqual(rows[0].planned.note, "3:00")
    }

    /// Already-persisted fill-in rows with "CIRCUIT · 60 ROUNDS" heal on reopen.
    func testPersistedCircuitSixtyRoundsHealedOnPrepare() {
        let bad = [
            ExerciseActual(
                id: "ski",
                name: "Ski Erg",
                planned: ExerciseActualPlanned(sets: 60, reps: 1, note: "3:00"),
                structureHeader: "CIRCUIT · 60 ROUNDS",
                structureBlockIndex: 0
            ),
            ExerciseActual(
                id: "row",
                name: "Rowing Machine",
                planned: ExerciseActualPlanned(sets: 60, reps: 1, note: "3:00"),
                structureHeader: "CIRCUIT · 60 ROUNDS",
                structureBlockIndex: 0
            )
        ]
        let healed = StravaWorkoutStructureText.healMisencodedTimeCapRounds(exercises: bad)
        XCTAssertEqual(healed.map(\.planned.sets), [1, 1])
        XCTAssertEqual(healed[0].structureHeader, "FOR TIME · 60 MIN CAP")
        XCTAssertEqual(healed[0].planned.displayLine, "3:00")
        XCTAssertEqual(
            StravaWorkoutStructureText.healMisencodedTimeCapRounds(
                structureBody: "CIRCUIT · 60 ROUNDS\n⛷️ Ski Erg — 60 × 3:00"
            ),
            "FOR TIME · 60 MIN CAP\n⛷️ Ski Erg — 60 × 3:00"
        )
        // Genuine 6-round timed circuit must not be rewritten.
        let realCircuit = [
            ExerciseActual(
                id: "ski",
                name: "Ski Erg",
                planned: ExerciseActualPlanned(sets: 6, reps: 1, note: "3:00"),
                structureHeader: "CIRCUIT · 6 ROUNDS"
            )
        ]
        let untouched = StravaWorkoutStructureText.healMisencodedTimeCapRounds(exercises: realCircuit)
        XCTAssertEqual(untouched[0].planned.sets, 6)
        XCTAssertEqual(untouched[0].structureHeader, "CIRCUIT · 6 ROUNDS")
    }

    /// Legacy drafts that stuffed cap minutes into `rounds` still heal on match.
    func testLegacyForTimeRoundsAsMinutesHealedOnMatch() throws {
        let draft = ActualsCaptureDraft(
            id: "legacy-ft",
            title: "Legacy for time",
            blockSummaries: ["Ski Erg"],
            estimatedMinutes: 60,
            source: .built,
            sport: WorkoutSport.conditioning.rawValue,
            intervals: [],
            blocks: [
                SocialImportBlock(
                    label: nil,
                    rounds: 60,
                    exercises: [SocialImportExercise(name: "Ski Erg", seconds: 180)],
                    type: "for-time"
                )
            ]
        )
        let workout = try XCTUnwrap(draft.toWorkoutForMatch())
        XCTAssertEqual(workout.blocks.first?.rounds, 1)
        XCTAssertTrue(workout.blocks.first?.label?.contains("60") == true)
        let rows = StravaWorkoutStructureText.fillInExercises(from: workout)
        XCTAssertFalse(rows.first?.structureHeader?.contains("60 ROUNDS") == true)
        XCTAssertEqual(rows.first?.planned.sets, 1)
    }

    func testAMRAPAndTabataStructureBodiesIncludeHeaderAndSteps() {
        let amrap = Workout(
            id: "amrap",
            name: "12-min AMRAP",
            sport: .conditioning,
            duration: 12 * 60,
            blocks: [
                Block(
                    label: nil,
                    structure: .amrap,
                    rounds: 1,
                    exercises: [
                        Exercise(name: "Pull-up", canonicalName: nil, sets: 1, reps: "5", durationSeconds: nil, load: nil, restSeconds: nil, distance: nil, notes: nil, focus: nil, supersetGroup: nil),
                        Exercise(name: "Push-up", canonicalName: nil, sets: 1, reps: "10", durationSeconds: nil, load: nil, restSeconds: nil, distance: nil, notes: nil, focus: nil, supersetGroup: nil),
                        Exercise(name: "Air squat", canonicalName: nil, sets: 1, reps: "15", durationSeconds: nil, load: nil, restSeconds: nil, distance: nil, notes: nil, focus: nil, supersetGroup: nil)
                    ]
                )
            ],
            source: .manual
        )
        let amrapBody = StravaWorkoutStructureText.structureBody(from: amrap)
        XCTAssertTrue(amrapBody.contains("AMRAP"))
        XCTAssertTrue(amrapBody.contains("Pull-up"))
        XCTAssertEqual(StravaWorkoutStructureText.fillInExercises(from: amrap).map(\.name), [
            "Pull-up", "Push-up", "Air squat"
        ])

        let tabata = Workout(
            id: "tabata",
            name: "Tabata bike",
            sport: .cardio,
            duration: 8 * 60,
            blocks: [
                Block(
                    label: nil,
                    structure: .tabata,
                    rounds: 8,
                    exercises: [
                        Exercise(name: "Assault Bike", canonicalName: nil, sets: 1, reps: nil, durationSeconds: 20, load: nil, restSeconds: 10, distance: nil, notes: nil, focus: nil, supersetGroup: nil)
                    ]
                )
            ],
            source: .manual
        )
        let tabataRows = StravaWorkoutStructureText.fillInExercises(from: tabata)
        XCTAssertEqual(tabataRows[0].planned.sets, 8)
        XCTAssertEqual(tabataRows[0].planned.displayLine, "8 × 0:20")
        XCTAssertTrue(StravaWorkoutStructureText.structureBody(from: tabata).contains("8 ROUNDS"))
    }

    func testWarmupCooldownAndRestDoNotBecomeTimedWorkPlaceholders() throws {
        let data: [String: Any] = [
            "title": "Mixed session",
            "intervals": [
                ["kind": "warmup", "seconds": 300, "name": "Easy spin", "target": NSNull()],
                [
                    "kind": "repeat",
                    "reps": 3,
                    "intervals": [
                        ["kind": "reps", "sets": 1, "reps": 8, "name": "Thruster", "load": "40kg"],
                        ["kind": "rest", "seconds": 60]
                    ]
                ],
                ["kind": "cooldown", "seconds": 240, "target": "Walk"]
            ]
        ]
        let resolved = try XCTUnwrap(
            ActualsLibraryWorkoutResolver.workout(
                fromBlocksJSON: data,
                base: Workout(
                    id: "mixed",
                    name: "Mixed session",
                    sport: .mixed,
                    duration: 40 * 60,
                    blocks: [],
                    source: .manual
                )
            )
        )
        let names = resolved.blocks.flatMap(\.exercises).map(\.name)
        XCTAssertEqual(names, ["Easy spin", "Thruster", "Walk"])
        XCTAssertFalse(names.contains(where: ActualsLibraryWorkoutResolver.isPlaceholderName))
        let body = StravaWorkoutStructureText.structureBody(from: resolved)
        XCTAssertTrue(body.contains("Easy spin"))
        XCTAssertTrue(body.contains("Thruster"))
        XCTAssertTrue(body.contains("Walk"))
        XCTAssertFalse(body.contains("Timed Work"))
    }

    func testEmptyBlocksWithNamedIntervalsOnly() throws {
        let data: [String: Any] = [
            "title": "Intervals only",
            "blocks": [],
            "intervals": [
                ["kind": "time", "seconds": 90, "name": "Ski Erg", "target": NSNull()],
                ["kind": "time", "seconds": 90, "name": "Rowing Machine", "target": NSNull()]
            ]
        ]
        let resolved = try XCTUnwrap(
            ActualsLibraryWorkoutResolver.workout(
                fromBlocksJSON: data,
                base: Workout(id: "int", name: "Intervals only", sport: .cardio, duration: 20 * 60, blocks: [], source: .manual)
            )
        )
        XCTAssertEqual(resolved.blocks.flatMap(\.exercises).map(\.name), ["Ski Erg", "Rowing Machine"])
    }

    func testAllPlaceholderBlocksWithoutIntervalsReturnsNil() {
        let data: [String: Any] = [
            "title": "Broken",
            "blocks": [
                [
                    "type": "circuit",
                    "rounds": 4,
                    "exercises": [
                        ["name": "Timed Work", "duration_sec": 60]
                    ]
                ]
            ]
        ]
        let resolved = ActualsLibraryWorkoutResolver.workout(
            fromBlocksJSON: data,
            base: placeholderBikeSkiRowWorkout()
        )
        XCTAssertNil(resolved)
    }

    func testMatchedCardFromGarminSeedsSameStructureWithoutStravaWriteBack() throws {
        let workout = bikeSkiRowLibraryWorkout()
        let activity = ActualsUnmappedActivity(
            title: "Erg cardio",
            provider: .garmin,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 77 * 60,
            distanceMeters: nil,
            calories: 610,
            avgHR: 140,
            type: .other
        )
        let card = ActualsTodayDemoFeed.makeMatchedCard(
            request: .init(
                cardID: "garmin_erg_1",
                timeLabel: "10:15",
                title: workout.name,
                activity: activity,
                blockSummaries: [],
                sourceLabel: "Matched · Garmin",
                workout: workout
            )
        )
        let session = try XCTUnwrap(card.fillInSession)
        XCTAssertEqual(session.exercises.map(\.name), [
            "Assault Bike", "Ski Erg", "Rowing Machine", "Spin / Indoor Bike"
        ])
        XCTAssertEqual(session.exercises.map(\.planned.sets), [6, 6, 6, 6])
        XCTAssertEqual(session.exercises[0].planned.displayLine, "6 × 3:00")
        XCTAssertTrue(session.stravaStructureBody.contains("6 ROUNDS"))
        XCTAssertTrue(session.stravaStructureBody.contains("Assault Bike"))
        XCTAssertNil(session.stravaActivityId, "Garmin cards must not invent a Strava activity id")
        XCTAssertFalse(session.canEvaluateStravaWriteBack)
        XCTAssertEqual(card.sourceProvider, .garmin)
        XCTAssertEqual(card.stravaDecoration, .none)
    }

    func testMatchedCardFromStravaSeedsStructureAndWriteBackMetadata() throws {
        let workout = bikeSkiRowLibraryWorkout()
        var activity = ActualsUnmappedActivity(
            title: "Erg cardio",
            provider: .strava,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 77 * 60,
            distanceMeters: nil,
            calories: 610,
            avgHR: 140,
            type: .other
        )
        activity.stravaTypeRaw = "WeightTraining"
        activity.activityDescription = ""
        let card = ActualsTodayDemoFeed.makeMatchedCard(
            request: .init(
                cardID: "strava_19657976868",
                timeLabel: "10:15",
                title: workout.name,
                activity: activity,
                blockSummaries: [],
                sourceLabel: "Matched · Strava",
                workout: workout
            )
        )
        let session = try XCTUnwrap(card.fillInSession)
        XCTAssertEqual(session.stravaActivityId, "19657976868")
        XCTAssertEqual(session.stravaActivityType, "WeightTraining")
        XCTAssertTrue(session.canEvaluateStravaWriteBack)
        XCTAssertEqual(session.exercises.map(\.planned.sets), [6, 6, 6, 6])
        XCTAssertTrue(session.stravaStructureBody.contains("CIRCUIT · 6 ROUNDS")
                      || session.stravaStructureBody.contains("6 ROUNDS"))
        let decision = StravaWriteBackDecorator.evaluate(
            StravaWriteBackEvaluateInput(
                activityType: session.stravaActivityType ?? "",
                recordingApp: session.stravaRecordingApp,
                description: session.stravaCurrentDescription ?? "",
                isRace: session.stravaIsRace,
                rules: .default,
                structureBody: session.stravaStructureBody,
                rpe: 6
            )
        )
        XCTAssertTrue(decision.shouldWrite)
        let decorated = try XCTUnwrap(decision.decoratedDescription)
        XCTAssertTrue(decorated.contains("Assault Bike"))
        XCTAssertTrue(decorated.contains("6 ROUNDS"))
        XCTAssertTrue(decorated.contains(StravaWriteBackSignature.line))
        XCTAssertFalse(decorated.contains("Timed Work"))
    }

    func testAppleHealthMatchedCardAlsoGetsLibrarySteps() throws {
        let workout = bikeSkiRowLibraryWorkout()
        let activity = ActualsUnmappedActivity(
            title: "Traditional Strength Training",
            provider: .appleHealth,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 77 * 60,
            distanceMeters: nil,
            calories: 500,
            avgHR: nil,
            type: .strength
        )
        let card = ActualsTodayDemoFeed.makeMatchedCard(
            request: .init(
                cardID: "ah_strength_1",
                timeLabel: "10:15",
                title: workout.name,
                activity: activity,
                blockSummaries: [],
                sourceLabel: "Matched · Apple Health",
                workout: workout
            )
        )
        let session = try XCTUnwrap(card.fillInSession)
        XCTAssertEqual(session.exercises.count, 4)
        XCTAssertNil(session.stravaActivityId)
        XCTAssertFalse(session.canEvaluateStravaWriteBack)
        XCTAssertTrue(session.stravaStructureBody.contains("Ski Erg"))
    }

    func testResolveDetailFetchesBlocksJSONWhenIncomingIsPlaceholder() async throws {
        let mock = MockAPIService()
        mock.fetchWorkoutBlocksJSONResult = .success([
            "title": "Bike ski row repeats",
            "sport": "mixed",
            "blocks": [],
            "intervals": [
                ["kind": "round_start", "rounds": 6],
                ["kind": "time", "seconds": 180, "name": "Assault Bike", "target": NSNull()],
                ["kind": "time", "seconds": 180, "name": "Ski Erg", "target": NSNull()],
                ["kind": "time", "seconds": 180, "name": "Rowing Machine", "target": NSNull()],
                ["kind": "time", "seconds": 180, "name": "Spin / Indoor Bike", "target": NSNull()]
            ]
        ])
        let resolved = await ActualsLibraryWorkoutResolver.resolveDetail(
            for: placeholderBikeSkiRowWorkout(),
            api: mock
        )
        assertBikeSkiRowResolved(resolved)
        XCTAssertEqual(resolved.blocks.first?.rounds, 6)
        let fillIn = StravaWorkoutStructureText.fillInExercises(from: resolved)
        XCTAssertEqual(fillIn.map(\.planned.displayLine), [
            "6 × 3:00", "6 × 3:00", "6 × 3:00", "6 × 3:00"
        ])
    }

    private func bikeSkiRowLibraryWorkout() -> Workout {
        Workout(
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
                        Exercise(name: "Assault Bike", canonicalName: nil, sets: 1, reps: nil, durationSeconds: 180, load: nil, restSeconds: nil, distance: nil, notes: nil, focus: nil, supersetGroup: nil),
                        Exercise(name: "Ski Erg", canonicalName: nil, sets: 1, reps: nil, durationSeconds: 180, load: nil, restSeconds: nil, distance: nil, notes: nil, focus: nil, supersetGroup: nil),
                        Exercise(name: "Rowing Machine", canonicalName: nil, sets: 1, reps: nil, durationSeconds: 180, load: nil, restSeconds: nil, distance: nil, notes: nil, focus: nil, supersetGroup: nil),
                        Exercise(name: "Spin / Indoor Bike", canonicalName: nil, sets: 1, reps: nil, durationSeconds: 180, load: nil, restSeconds: nil, distance: nil, notes: nil, focus: nil, supersetGroup: nil)
                    ]
                )
            ],
            source: .manual
        )
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

    // MARK: - AMA-2403 verify + 403 mapping

    func testUnverifiedWriteBack403IsNotSignInAgain() {
        XCTAssertEqual(
            BFFStravaClientError.sessionNotVerified.errorDescription,
            "Verify this session in AmakaFlow before writing to Strava."
        )
        XCTAssertNotEqual(
            BFFStravaClientError.sessionNotVerified.errorDescription,
            BFFStravaClientError.authenticationRequired.errorDescription
        )
    }

    func testWriteBackProviderCallsVerifyBeforeApply() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        var paths: [String] = []
        var verifyBody: [String: Any]?
        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            paths.append(path)
            let data: Data
            if path.contains("/verify") {
                if let body = Self.httpBodyData(from: request),
                   let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                    verifyBody = json
                }
                data = Data(#"{"activity_id":42,"verified":true,"amakaflow_session_id":"sess-1"}"#.utf8)
            } else {
                data = Data(#"{"activity_id":42,"status":"written","written":true,"title":"Upper","description":"signed"}"#.utf8)
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, data)
        }

        let client = BFFStravaClient(
            baseURL: "https://mock.test/v1",
            session: MockURLProtocol.mockSession(),
            bearerTokenProvider: { "test-token" },
            userIDProvider: { "user-1" }
        )
        let provider = BFFStravaWriteBackProvider(client: client)
        let outcome = await provider.writeBack(
            StravaWriteBackRequest(
                activityId: "42",
                title: "Upper",
                structureBody: "Press 3x5",
                currentDescription: "",
                activityType: "WeightTraining",
                recordingApp: nil,
                isRace: false,
                rules: .default,
                rpe: 8,
                amakaflowSessionId: "sess-1"
            )
        )

        guard case .updated = outcome else {
            return XCTFail("expected updated, got \(outcome)")
        }
        XCTAssertEqual(paths.count, 2)
        XCTAssertTrue(paths[0].contains("/verify"), paths[0])
        XCTAssertTrue(paths[1].contains("/writeback"), paths[1])
        XCTAssertEqual(verifyBody?["amakaflow_session_id"] as? String, "sess-1")
    }

    func testWriteBackProviderFailsWhenVerifyReturnsUnverified() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        var paths: [String] = []
        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            paths.append(path)
            let data: Data
            if path.contains("/verify") {
                data = Data(#"{"activity_id":42,"verified":false,"amakaflow_session_id":"sess-1"}"#.utf8)
            } else {
                data = Data(#"{"activity_id":42,"status":"written","written":true,"title":"Upper","description":"signed"}"#.utf8)
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, data)
        }

        let client = BFFStravaClient(
            baseURL: "https://mock.test/v1",
            session: MockURLProtocol.mockSession(),
            bearerTokenProvider: { "test-token" },
            userIDProvider: { "user-1" }
        )
        let provider = BFFStravaWriteBackProvider(client: client)
        let outcome = await provider.writeBack(
            StravaWriteBackRequest(
                activityId: "42",
                title: "Upper",
                structureBody: "Press 3x5",
                currentDescription: "",
                activityType: "WeightTraining",
                recordingApp: nil,
                isRace: false,
                rules: .default,
                rpe: 8,
                amakaflowSessionId: "sess-1"
            )
        )

        guard case .failed(let message) = outcome else {
            return XCTFail("expected failed, got \(outcome)")
        }
        XCTAssertEqual(message, BFFStravaClientError.sessionNotVerified.localizedDescription)
        XCTAssertEqual(paths.count, 1)
        XCTAssertTrue(paths[0].contains("/verify"), paths[0])
    }

    func testWriteBackProviderFailsWhenVerifyThrowsSessionNotVerified() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        var paths: [String] = []
        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            paths.append(path)
            let data: Data
            if path.contains("/verify") {
                data = Data(
                    #"""
                    {"detail":{"code":"strava_writeback_unverified","message":"not verified","activity_id":42}}
                    """#.utf8
                )
            } else {
                data = Data(#"{"activity_id":42,"status":"written","written":true,"title":"Upper","description":"signed"}"#.utf8)
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: path.contains("/verify") ? 403 : 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, data)
        }

        let client = BFFStravaClient(
            baseURL: "https://mock.test/v1",
            session: MockURLProtocol.mockSession(),
            bearerTokenProvider: { "test-token" },
            userIDProvider: { "user-1" }
        )
        let provider = BFFStravaWriteBackProvider(client: client)
        let outcome = await provider.writeBack(
            StravaWriteBackRequest(
                activityId: "42",
                title: "Upper",
                structureBody: "Press 3x5",
                currentDescription: "",
                activityType: "WeightTraining",
                recordingApp: nil,
                isRace: false,
                rules: .default,
                rpe: 8,
                amakaflowSessionId: "sess-1"
            )
        )

        guard case .failed(let message) = outcome else {
            return XCTFail("expected failed, got \(outcome)")
        }
        XCTAssertEqual(message, BFFStravaClientError.sessionNotVerified.localizedDescription)
        XCTAssertEqual(paths.count, 1, "must not continue to writeback after sessionNotVerified")
        XCTAssertTrue(paths[0].contains("/verify"), paths[0])
    }

    func testNestedUnverified403MapsToSessionNotVerified() async {
        await assertUnverified403MapsToSessionNotVerified(
            body: Data(
                #"""
                {"detail":{"code":"strava_writeback_unverified","message":"not verified","activity_id":42}}
                """#.utf8
            )
        )
    }

    func testTopLevelUnverified403MapsToSessionNotVerified() async {
        await assertUnverified403MapsToSessionNotVerified(
            body: Data(#"{"code":"strava_writeback_unverified","message":"not verified"}"#.utf8)
        )
    }

    private func assertUnverified403MapsToSessionNotVerified(body: Data) async {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }
        MockURLProtocol.setResponse(statusCode: 403, data: body)

        let client = BFFStravaClient(
            baseURL: "https://mock.test/v1",
            session: MockURLProtocol.mockSession(),
            bearerTokenProvider: { "test-token" },
            userIDProvider: { "user-1" }
        )

        do {
            _ = try await client.applyWriteBack(
                activityId: "42",
                title: "Upper",
                description: "signed"
            )
            XCTFail("expected sessionNotVerified")
        } catch let error as BFFStravaClientError {
            XCTAssertEqual(error, .sessionNotVerified)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    /// URLSession often delivers POST bodies via `httpBodyStream` in URLProtocol.
    private static func httpBodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data.isEmpty ? nil : data
    }

}
