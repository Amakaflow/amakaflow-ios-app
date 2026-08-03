//
//  WorkoutEnrichmentPushCopyTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2371: Peloton-style toggle-row copy for the enhance sheet
//  (spec 2026-08-02 send/enhance flow iOS UI redesign).
//

import XCTest
@testable import AmakaFlowCompanion

final class WorkoutEnrichmentPushCopyTests: XCTestCase {
    func testWatchReadyTitle() {
        XCTAssertEqual(WorkoutEnrichmentPushCopy.sheetTitle, "Make it watch-ready?")
    }

    func testPrimaryCTACountsCheckedOffers() {
        XCTAssertEqual(WorkoutEnrichmentPushCopy.primaryCTA(checkedCount: 3), "Add 3 & send")
        XCTAssertEqual(WorkoutEnrichmentPushCopy.primaryCTA(checkedCount: 0), "Send")
    }

    func testSendAsIsLabel() {
        XCTAssertEqual(WorkoutEnrichmentPushCopy.sendAsIsCTA, "Send as-is — no changes")
    }

    func testOfferTitlesAreShortenedPelotonStyle() {
        XCTAssertEqual(
            WorkoutEnrichmentPushCopy.offerTitle(for: .sessionWarmup, target: .garmin),
            "Mobility prep"
        )
        XCTAssertEqual(
            WorkoutEnrichmentPushCopy.offerTitle(for: .exerciseWarmupSets, target: .garmin),
            "Warm-up sets"
        )
        XCTAssertEqual(
            WorkoutEnrichmentPushCopy.offerTitle(for: .betweenSetRest, target: .garmin),
            "Rest between sets"
        )
        XCTAssertEqual(
            WorkoutEnrichmentPushCopy.offerTitle(for: .betweenSetRest, target: .apple),
            "Rest between sets"
        )
    }

    func testDeviceNameMatchesTarget() {
        XCTAssertEqual(WorkoutEnrichmentPushCopy.deviceName(for: .garmin), "Garmin")
        XCTAssertEqual(WorkoutEnrichmentPushCopy.deviceName(for: .apple), "Apple Watch")
    }

    func testRestOpenSegmentLabelMatchesTarget() {
        XCTAssertEqual(WorkoutEnrichmentPushCopy.restOpenSegmentLabel(target: .apple), "Open rest")
        XCTAssertEqual(WorkoutEnrichmentPushCopy.restOpenSegmentLabel(target: .garmin), "Lap button")
        XCTAssertEqual(WorkoutEnrichmentPushCopy.restTimedSegmentLabel, "Timed")
    }

    // MARK: - AMA-2371 review fix: persisted restSec must not bypass 15...300

    func testNormalizedRestSecClampsPersistedValueAboveNewRange() {
        // A standing pref saved under the old 15...600 stepper (e.g. 600)
        // must not render/confirm out-of-range once the sheet narrows to 300.
        XCTAssertEqual(WorkoutEnrichmentPushCopy.normalizedRestSec(600), 300)
    }

    func testNormalizedRestSecClampsBelowRangeToMinimum() {
        XCTAssertEqual(WorkoutEnrichmentPushCopy.normalizedRestSec(5), 15)
        XCTAssertEqual(WorkoutEnrichmentPushCopy.normalizedRestSec(0), 15)
    }

    func testNormalizedRestSecSnapsToFifteenSecondGrid() {
        XCTAssertEqual(WorkoutEnrichmentPushCopy.normalizedRestSec(22), 15)
        XCTAssertEqual(WorkoutEnrichmentPushCopy.normalizedRestSec(23), 30)
    }

    func testNormalizedRestSecPassesThroughInRangeAlignedValue() {
        XCTAssertEqual(WorkoutEnrichmentPushCopy.normalizedRestSec(90), 90)
    }

    func testNormalizedRestSecDefaultsToSixtyWhenNil() {
        XCTAssertEqual(WorkoutEnrichmentPushCopy.normalizedRestSec(nil), 60)
    }
}
