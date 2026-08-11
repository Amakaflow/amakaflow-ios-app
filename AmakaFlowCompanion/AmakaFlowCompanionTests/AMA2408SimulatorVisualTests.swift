//
//  AMA2408SimulatorVisualTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2408 — simulator-hosted visual dogfood for the two claims worth
//  eyeballing: phantom warm-ups (row ON, pick nothing) and reopen-keeps-picks.
//  Renders the real sheet in a UIWindow and writes PNGs under
//  /tmp/ama2408-sim-shots.
//

import XCTest
import SwiftUI
import UIKit
@testable import AmakaFlowCompanion

@MainActor
final class AMA2408SimulatorVisualTests: XCTestCase {
    private let outDir = URL(fileURLWithPath: "/tmp/ama2408-sim-shots")
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: EnrichmentPrefsStore!

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        suiteName = "ama2408.sim.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        let readiness = WatchItemReadinessStore(defaults: defaults)
        store = EnrichmentPrefsStore(defaults: defaults, readinessStore: readiness)
    }

    override func tearDown() {
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        super.tearDown()
    }

    /// Claim 1: Warm-up ON + pick nothing → amber CTA + applied prefs have ZERO ramps.
    func testPhantomWarmups_rowOnPickNothing_zeroAppliedRamps() throws {
        let plan = Self.strengthPlan(names: ["Bench Press", "Row", "Curl", "Fly"])
        let state = EnrichmentState.seed(
            workoutPrefs: nil,
            globalDefaults: .defaults,
            plan: plan
        )
        // Fresh seed may check warm-ups from plan defaults — force ON + empty ramps.
        var onEmpty = state
        onEmpty.checkedKinds.insert(.exerciseWarmupSets)
        onEmpty.perExerciseRamps = []

        XCTAssertEqual(
            onEmpty.summary(for: .exerciseWarmupSets),
            EnrichmentRowSummary.noRampsYet
        )

        let application = try WorkoutEnrichmentPushPlanner.application(
            plan: plan,
            decision: onEmpty.decision,
            prefs: .defaults,
            tombstones: []
        )
        XCTAssertEqual(application.prefs.exerciseWarmupSets.perExercise, [])
        let effective = LegacyOptInRampMigration.optInEffectiveRamps(
            prefs: application.prefs.exerciseWarmupSets,
            candidateNames: ["Bench Press", "Row", "Curl", "Fly"]
        )
        XCTAssertTrue(effective.isEmpty, "phantom warm-ups: expected zero applied ramps, got \(effective.keys)")

        let sheet = WorkoutEnrichmentPushSheet(
            plan: plan,
            prefs: .defaults,
            workoutId: "ama2408-phantom",
            prefsStore: store,
            onConfirm: { _ in },
            onSkip: {},
            onClose: {}
        )
        try snapshot(sheet, named: "01-phantom-warmups-on-empty.png")
    }

    /// Claim 2: Configure 2 ramps → persist → reopen identical (real UserDefaults store).
    func testReopenKeepsMyPicks_roundTripThroughRealStore() throws {
        let workoutID = "ama2408-reopen-\(UUID().uuidString)"
        let plan = Self.strengthPlan(names: [
            "Incline Smith", "Row", "Curl", "Press", "Fly", "Raise", "Squat"
        ])
        var state = EnrichmentState.seed(
            workoutPrefs: nil,
            globalDefaults: .defaults,
            plan: plan
        )
        state = EnrichmentReducer.reduce(state, actions: [
            .toggleExercise("Incline Smith"),
            .toggleExercise("Row"),
            .confirm
        ])
        XCTAssertEqual(
            EnrichmentRowSummary.enabledRamps(
                in: state.perExerciseRamps,
                candidates: state.candidateExerciseNames
            ).count,
            2
        )
        XCTAssertEqual(
            state.summary(for: .exerciseWarmupSets),
            "INCLINE SMITH + 1 MORE · 2 OF 7"
        )

        store.save(workoutID: workoutID, prefs: state.persisted())

        let reopened = EnrichmentState.seed(
            workoutPrefs: store.load(workoutID: workoutID),
            globalDefaults: .defaults,
            plan: plan
        )
        XCTAssertEqual(reopened.perExerciseRamps, state.perExerciseRamps)
        XCTAssertEqual(reopened.summary(for: .exerciseWarmupSets), state.summary(for: .exerciseWarmupSets))

        let sheet = WorkoutEnrichmentPushSheet(
            plan: plan,
            prefs: .defaults,
            workoutId: workoutID,
            prefsStore: store,
            onConfirm: { _ in },
            onSkip: {},
            onClose: {}
        )
        try snapshot(sheet, named: "02-reopen-two-ramps.png")
    }

    /// Cool-down OFF → no sub-line (title + toggle only).
    func testCooldownOffRendersNilSummary() throws {
        let plan = Self.strengthPlan(names: ["Bench"])
        var state = EnrichmentState.seed(
            workoutPrefs: nil,
            globalDefaults: .defaults,
            plan: plan
        )
        state.checkedKinds.remove(.cooldown)
        state.cooldownActivities = WorkoutEnrichmentMutations.defaultCooldownActivities()
        XCTAssertNil(state.summary(for: EnrichmentKind.cooldown))

        let sheet = WorkoutEnrichmentPushSheet(
            plan: plan,
            prefs: .defaults,
            workoutId: "ama2408-cooldown-off",
            prefsStore: store,
            onConfirm: { _ in },
            onSkip: {},
            onClose: {}
        )
        try snapshot(sheet, named: "03-cooldown-off.png")
    }

    // MARK: - Helpers

    private static func strengthPlan(names: [String]) -> WorkoutEnrichmentPushPlanner.Plan {
        let blocks = [
            SocialImportBlock(
                label: "Main",
                rounds: 1,
                exercises: names.map { SocialImportExercise(name: $0, sets: 3, reps: 8) },
                type: "sets"
            )
        ]
        return WorkoutEnrichmentPushPlanner.plan(
            blocks: blocks,
            tombstones: [],
            prefs: .defaults,
            target: .apple
        )
    }

    private func snapshot<V: View>(_ view: V, named name: String) throws {
        let size = CGSize(width: 390, height: 780)
        let host = UIHostingController(rootView: view.preferredColorScheme(.dark))
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.backgroundColor = .black
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        for _ in 0..<5 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            host.view.layoutIfNeeded()
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { _ in
            host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        window.isHidden = true

        guard let data = image.pngData() else {
            XCTFail("Failed to encode \(name)")
            return
        }
        XCTAssertGreaterThan(data.count, 8_000, "snapshot \(name) looks empty (\(data.count) bytes)")
        let url = outDir.appendingPathComponent(name)
        try data.write(to: url)
        print("[AMA-2408] wrote \(url.path) (\(data.count) bytes)")
    }
}
