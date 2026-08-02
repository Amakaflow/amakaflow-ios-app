// AmakaFlowCompanionTests/WorkoutTypeFavoritesOrderingTests.swift
import XCTest
@testable import AmakaFlowCompanion

final class WorkoutTypeFavoritesOrderingTests: XCTestCase {
    func testOrdersByCanonicalCategorySequenceThenDisplayName() {
        // Alpha-by-category would put ride before run; sequence puts run before strength before ride.
        let items = [
            item(id: "ride1", category: "ride", name: "Endurance Ride", ai: true),
            item(id: "str1", category: "strength", name: "Zebra Push", ai: true),
            item(id: "run_tempo", category: "run", name: "Tempo Run", ai: true),
            item(id: "run_long", category: "run", name: "Long Run", ai: true),
            item(id: "skip", category: "run", name: "Not A Preset", ai: false),
        ]

        let ordered = WorkoutTypeFavoritesOrdering.orderedPresets(items)

        XCTAssertEqual(ordered.map(\.id), ["run_long", "run_tempo", "str1", "ride1"])
    }

    func testUnknownCategorySortsAfterKnown() {
        let items = [
            item(id: "weird", category: "zzz_future", name: "Alpha", ai: true),
            item(id: "run1", category: "run", name: "Tempo Run", ai: true),
        ]
        let ordered = WorkoutTypeFavoritesOrdering.orderedPresets(items)
        XCTAssertEqual(ordered.map(\.id), ["run1", "weird"])
    }

    func testVisibleChipLimitIsEight() {
        XCTAssertEqual(WorkoutTypeFavoritesOrdering.visibleChipLimit, 8)
    }

    #if DEBUG
    @MainActor
    func testFixtureServiceProvidesAtLeastEightAiPresets() async throws {
        let fixtures = FixtureAPIService()
        let items = try await fixtures.fetchWorkoutTypes(aiPresetOnly: true)
        XCTAssertGreaterThanOrEqual(
            items.filter(\.aiPreset).count,
            WorkoutTypeFavoritesOrdering.visibleChipLimit
        )
    }
    #endif

    private func item(id: String, category: String, name: String, ai: Bool) -> WorkoutTypeItem {
        WorkoutTypeItem(
            id: id,
            category: category,
            format: "steady_state",
            focus: [],
            displayName: name,
            aliases: [],
            aiPreset: ai,
            equipment: [],
            platformTags: [:]
        )
    }
}
