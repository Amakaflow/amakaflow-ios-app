//
//  CollectionPresentationTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2376: collection duration formatting and LAST DONE presentation.
//

import XCTest
@testable import AmakaFlowCompanion

final class CollectionPresentationTests: XCTestCase {

    // MARK: - Duration formatting

    func testFormattedTotalDurationHoursAndMinutes() {
        XCTAssertEqual(CollectionPresentation.formattedTotalDuration(seconds: 15_000), "~4H 10M")
    }

    func testFormattedTotalDurationMinutesOnly() {
        XCTAssertEqual(CollectionPresentation.formattedTotalDuration(seconds: 2_400), "~40M")
    }

    func testFormattedTotalDurationZero() {
        XCTAssertEqual(CollectionPresentation.formattedTotalDuration(seconds: 0), "~0H")
    }

    func testUncategorizedIDSentinel() {
        XCTAssertEqual(CollectionPresentation.uncategorizedID, "uncategorized")
    }

    // MARK: - LibraryDestination.collection

    func testCollectionDestinationID() {
        XCTAssertEqual(
            LibraryDestination.collection(id: "hyrox-prep").id,
            "collection:hyrox-prep"
        )
        XCTAssertEqual(
            LibraryDestination.collection(id: CollectionPresentation.uncategorizedID).id,
            "collection:uncategorized"
        )
    }

    // MARK: - LAST DONE

    func testLastDoneLineReturnsNilWhenNoMatchingCompletions() {
        let completions = [
            makeCompletion(id: "c1", workoutId: "other", startedAt: thursdayDate)
        ]
        XCTAssertNil(
            WorkoutLastDonePresentation.line(from: completions, workoutId: "target")
        )
    }

    func testLastDoneLineReturnsNilForEmptyCompletions() {
        XCTAssertNil(
            WorkoutLastDonePresentation.line(from: [], workoutId: "target")
        )
    }

    func testLastDoneLineSingleCompletion() {
        let completions = [
            makeCompletion(
                id: "c1",
                workoutId: "w1",
                startedAt: thursdayDate,
                source: .garmin
            )
        ]
        XCTAssertEqual(
            WorkoutLastDonePresentation.line(from: completions, workoutId: "w1"),
            "Thu · on Garmin · 1× total"
        )
    }

    func testLastDoneLineMultiCountUsesMostRecentForWeekdayAndDevice() {
        let older = makeCompletion(
            id: "c1",
            workoutId: "w1",
            startedAt: thursdayDate,
            source: .appleWatch
        )
        let newer = makeCompletion(
            id: "c2",
            workoutId: "w1",
            startedAt: thursdayDate.addingTimeInterval(86_400),
            source: .garmin
        )
        let unrelated = makeCompletion(
            id: "c3",
            workoutId: "w2",
            startedAt: thursdayDate,
            source: .phone
        )
        let line = WorkoutLastDonePresentation.line(
            from: [older, newer, unrelated],
            workoutId: "w1"
        )
        XCTAssertEqual(line, "Fri · on Garmin · 2× total")
    }

    func testLastDoneLineOmitsRPEWithoutDetailData() {
        let completions = [
            makeCompletion(
                id: "c1",
                workoutId: "w1",
                startedAt: thursdayDate,
                source: .garmin
            )
        ]
        let line = WorkoutLastDonePresentation.line(from: completions, workoutId: "w1")
        XCTAssertNotNil(line)
        XCTAssertFalse(line?.contains("RPE") ?? true)
    }

    func testLastDoneLineIncludesRPEWhenProvided() {
        let completions = [
            makeCompletion(
                id: "c1",
                workoutId: "w1",
                startedAt: thursdayDate,
                source: .garmin
            )
        ]
        XCTAssertEqual(
            WorkoutLastDonePresentation.line(from: completions, workoutId: "w1", rpe: 8),
            "Thu · RPE 8 · on Garmin · 1× total"
        )
    }

    // MARK: - Helpers

    /// Aug 6, 2026 is a Thursday in Gregorian calendars.
    private var thursdayDate: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 6
        components.hour = 12
        return calendar.date(from: components)!
    }

    private func makeCompletion(
        id: String,
        workoutId: String?,
        startedAt: Date,
        source: WorkoutCompletion.CompletionSource = .garmin
    ) -> WorkoutCompletion {
        WorkoutCompletion(
            id: id,
            workoutName: "Test workout",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1_800),
            durationSeconds: 1_800,
            avgHeartRate: nil,
            maxHeartRate: nil,
            activeCalories: nil,
            distanceMeters: nil,
            source: source,
            syncedToStrava: nil,
            workoutId: workoutId,
            originalWorkout: nil,
            isSimulated: nil
        )
    }
}
