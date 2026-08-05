//
//  EnrichmentEnhanceUIPolishTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2378 UI polish — cooldown door always offered (default off), warm-up
//  Edit ramp is a full-width control, mobility chips carry SF Symbol icons.
//  Hosts each screen in a UIWindow on the simulator and writes PNGs under
//  /tmp/ama2378-polish-shots for visual confirmation.
//

import XCTest
import SwiftUI
import UIKit
@testable import AmakaFlowCompanion

@MainActor
final class EnrichmentEnhanceUIPolishTests: XCTestCase {
    private let outDir = URL(fileURLWithPath: "/tmp/ama2378-polish-shots")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    }

    func testDefaultPlanIncludesCooldownDoorUnchecked() {
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [
                SocialImportBlock(
                    label: "Main",
                    rounds: 1,
                    exercises: [SocialImportExercise(name: "Bench", sets: 3, reps: 8)],
                    type: "sets"
                )
            ],
            tombstones: [],
            prefs: .defaults,
            target: .apple
        )
        XCTAssertEqual(
            plan.offers.map(\.kind),
            [.sessionWarmup, .exerciseWarmupSets, .betweenSetRest, .cooldown]
        )
        XCTAssertEqual(plan.offer(.cooldown)?.isChecked, false)
    }

    func testDefaultCooldownSeedMatchesDesign() {
        let seed = WorkoutEnrichmentMutations.defaultCooldownActivities()
        XCTAssertEqual(seed.map(\.name), ["Stretch flow", "Treadmill"])
        XCTAssertEqual(seed[0].goal?.kind, .time)
        XCTAssertEqual(seed[0].goal?.value, 180)
        XCTAssertEqual(seed[1].goal?.kind, .open)
    }

    func testRenderEnhanceSheetIncludesFourRows() throws {
        let plan = WorkoutEnrichmentPushPlanner.plan(
            blocks: [
                SocialImportBlock(
                    label: "Main",
                    rounds: 1,
                    exercises: [
                        SocialImportExercise(name: "Deadlift", sets: 3, reps: 5),
                        SocialImportExercise(name: "Overhead Press", sets: 3, reps: 8)
                    ],
                    type: "sets"
                )
            ],
            tombstones: [],
            prefs: .defaults,
            target: .apple
        )
        XCTAssertNotNil(plan.offer(.cooldown))
        XCTAssertEqual(plan.offers.map(\.kind).last, .cooldown)

        let view = WorkoutEnrichmentPushSheet(
            plan: plan,
            prefs: .defaults,
            onConfirm: { _ in },
            onSkip: {},
            onClose: {}
        )
        try snapshot(view, named: "enhance-sheet-with-cooldown.png")
    }

    func testRenderWarmupPickWithFullWidthEditRamp() throws {
        let view = NavigationStack {
            EnrichmentWarmupPickScreen(
                ramps: .constant([
                    PerExerciseRamp(
                        exerciseRef: "Deadlift",
                        enabled: true,
                        sets: WorkoutEnrichmentMutations.defaultRampSets()
                    ),
                    PerExerciseRamp(
                        exerciseRef: "Leg Press",
                        enabled: false,
                        sets: []
                    )
                ]),
                exercises: ["Deadlift", "Leg Press"],
                workingSetCounts: [3, 4]
            )
        }
        try snapshot(view, named: "warmup-pick-edit-ramp.png")
    }

    func testRenderMobilityChipsWithIcons() throws {
        let view = NavigationStack {
            EnrichmentSequenceScreen(
                activities: .constant([
                    EnrichmentActivityPref(
                        name: "Jump rope",
                        goal: try? ActivityGoal(kind: .open, value: nil)
                    )
                ]),
                kind: .mobility
            )
        }
        try snapshot(view, named: "mobility-chips-with-icons.png")
    }

    // MARK: - Simulator window snapshot

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
        // Guard against empty/placeholder renders (all-black or tiny payloads).
        XCTAssertGreaterThan(data.count, 8_000, "snapshot \(name) looks empty (\(data.count) bytes)")
        try data.write(to: outDir.appendingPathComponent(name))
    }
}
