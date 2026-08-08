//
//  ActualsMergeClassifierTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2387: certain/uncertain merge, sticky Keep-both, Split, provenance.
//

import XCTest
@testable import AmakaFlowCompanion

final class ActualsMergeClassifierTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Certain

    func testCertainWhenStartWithinTwoMinutesAndShapeAgrees() {
        let a = recording(
            id: "aw", provider: .appleHealth, device: .watch,
            start: base, duration: 3600, distance: 8000, richness: 5
        )
        let b = recording(
            id: "g", provider: .garmin, device: .watch,
            start: base.addingTimeInterval(90), duration: 3550, distance: 7950, richness: 4
        )
        XCTAssertEqual(ActualsMergeClassifier.classify(a, b), .certain)
    }

    func testCertainWhenExternalRefsMatch() {
        let a = recording(
            id: "s1", provider: .strava, device: .phone,
            start: base, duration: 1800, externalRef: "act-99", richness: 2
        )
        let b = recording(
            id: "g1", provider: .garmin, device: .watch,
            start: base.addingTimeInterval(600), duration: 900,
            externalRef: "act-99", richness: 4
        )
        // Far apart in time — external ref still forces certain.
        XCTAssertEqual(ActualsMergeClassifier.classify(a, b), .certain)
    }

    // MARK: - Uncertain

    func testUncertainWhenCloseButOutsideCertainWindow() {
        let a = recording(
            id: "s", provider: .strava, device: .phone,
            start: base, duration: 3540, distance: 8200, richness: 2
        )
        let b = recording(
            id: "g", provider: .garmin, device: .watch,
            start: base.addingTimeInterval(4 * 60), duration: 3480, distance: 8100, richness: 3
        )
        XCTAssertEqual(ActualsMergeClassifier.classify(a, b), .uncertain)
    }

    // MARK: - Separate / sticky Keep-both

    func testSeparateWhenFarApart() {
        let a = recording(
            id: "a", provider: .appleHealth, device: .watch,
            start: base, duration: 1800, richness: 3
        )
        let b = recording(
            id: "b", provider: .strava, device: .phone,
            start: base.addingTimeInterval(3 * 3600), duration: 1800, richness: 2
        )
        XCTAssertEqual(ActualsMergeClassifier.classify(a, b), .separate)
    }

    func testKeepBothIsStickyAcrossClassify() {
        let a = recording(
            id: "s", provider: .strava, device: .phone,
            start: base, duration: 3540, distance: 8200, richness: 2
        )
        let b = recording(
            id: "g", provider: .garmin, device: .watch,
            start: base.addingTimeInterval(60), duration: 3480, distance: 8100, richness: 3
        )
        XCTAssertEqual(ActualsMergeClassifier.classify(a, b), .certain)

        var memory = ActualsMergeMemory()
        ActualsMergeClassifier.applyKeepBoth(a, b, memory: &memory)
        XCTAssertEqual(ActualsMergeClassifier.classify(a, b, memory: memory), .separate)
        // Re-sync with same pair still separate.
        XCTAssertEqual(ActualsMergeClassifier.classify(b, a, memory: memory), .separate)
    }

    // MARK: - Roles / provenance

    func testWatchBeatsPhoneAndRichestIsPrimary() {
        let phone = recording(
            id: "phone", provider: .strava, device: .phone,
            start: base, duration: 3600, richness: 9
        )
        let watchLean = recording(
            id: "watch", provider: .appleHealth, device: .watch,
            start: base, duration: 3600, richness: 2
        )
        let garmin = recording(
            id: "garmin", provider: .garmin, device: .watch,
            start: base, duration: 3600, richness: 5
        )
        let session = ActualsMergeClassifier.merge([phone, watchLean, garmin])
        XCTAssertEqual(session.mergeBadge, "MERGED · 3 SOURCES")
        XCTAssertEqual(session.primaryRecording?.id, "garmin")
        XCTAssertEqual(session.recordings.first(where: { $0.id == "garmin" })?.role, .primary)
        XCTAssertEqual(session.recordings.first(where: { $0.id == "watch" })?.role, .attached)
        XCTAssertEqual(session.recordings.first(where: { $0.id == "phone" })?.role, .hidden)
        // Hidden must not count.
        XCTAssertEqual(session.countingRecordings.count, 2)
        XCTAssertFalse(session.countingRecordings.contains(where: { $0.role == .hidden }))
    }

    // MARK: - Split restore

    func testSplitFullyRestoresSeparatePrimaries() {
        let a = recording(
            id: "aw", provider: .appleHealth, device: .watch,
            start: base, duration: 3600, richness: 5
        )
        let b = recording(
            id: "g", provider: .garmin, device: .watch,
            start: base, duration: 3600, richness: 4
        )
        let c = recording(
            id: "s", provider: .strava, device: .phone,
            start: base, duration: 3600, richness: 2
        )
        let session = ActualsMergeClassifier.merge([a, b, c])
        let restored = ActualsMergeClassifier.split(session)
        XCTAssertEqual(restored.count, 3)
        XCTAssertTrue(restored.allSatisfy { $0.role == .primary })
        XCTAssertEqual(Set(restored.map(\.id)), Set(["aw", "g", "s"]))
    }

    // MARK: - Badge + copy

    func testMergeBadgeAndAskCopy() {
        XCTAssertEqual(ActualsMergeBadge.text(sourceCount: 3), "MERGED · 3 SOURCES")
        XCTAssertEqual(ActualsCopy.mergeAskTitle, "Same session?")
        XCTAssertEqual(ActualsCopy.mergeAskAccessibilityID, "af_actuals_merge_ask")
        XCTAssertEqual(ActualsCopy.mergeAskMergeAccessibilityID, "af_actuals_merge_ask_merge")
        XCTAssertEqual(ActualsCopy.mergeAskKeepAccessibilityID, "af_actuals_merge_ask_keep")
        XCTAssertEqual(ActualsCopy.mergedSplitAccessibilityID, "af_actuals_merged_split")
    }

    // MARK: - Helpers

    private func recording(
        id: String,
        provider: ActualsSourceProvider,
        device: ActualsDeviceKind,
        start: Date,
        duration: TimeInterval,
        distance: Double? = nil,
        externalRef: String? = nil,
        richness: Int
    ) -> ActualsSourceRecording {
        ActualsSourceRecording(
            id: id,
            provider: provider,
            deviceKind: device,
            title: id,
            startDate: start,
            durationSeconds: duration,
            distanceMeters: distance,
            externalRef: externalRef,
            streamRichness: richness
        )
    }
}
