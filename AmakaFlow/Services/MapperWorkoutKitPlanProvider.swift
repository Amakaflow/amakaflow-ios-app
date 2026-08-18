//
//  MapperWorkoutKitPlanProvider.swift
//  AmakaFlow
//
//  AMA-2351 — fetch mapper WKPlanDTO JSON via BFF for Apple Start cutover.
//

import Foundation

/// Fetches mapper WKPlanDTO JSON (via BFF). Uses stored blocks_json unless a
/// derived watch plan was supplied (AMA-2453).
protocol WorkoutKitPlanProviding: Sendable {
    func fetchMapperPlanJSON(for workout: Workout) async throws -> Data
}

struct MapperWorkoutKitPlanProvider: WorkoutKitPlanProviding {
    let api: any APIServiceProviding
    let deliveryPrefs: [String: Any]?
    /// When set, compose from this derived plan instead of re-fetching stored workout_data.
    let planBlocksJSON: [String: Any]?

    init(
        api: any APIServiceProviding = AppDependencies.current.apiService,
        deliveryPrefs: [String: Any]? = nil,
        planBlocksJSON: [String: Any]? = nil
    ) {
        self.api = api
        self.deliveryPrefs = deliveryPrefs
        self.planBlocksJSON = planBlocksJSON
    }

    func fetchMapperPlanJSON(for workout: Workout) async throws -> Data {
        var blocksJSON: [String: Any]
        if let planBlocksJSON {
            blocksJSON = planBlocksJSON
        } else {
            blocksJSON = try await api.fetchWorkoutBlocksJSON(workoutId: workout.id)
        }
        if blocksJSON["title"] == nil {
            blocksJSON["title"] = workout.name
        }
        if (blocksJSON["blocks"] as? [Any])?.isEmpty != false,
           (blocksJSON["intervals"] as? [Any])?.isEmpty != false {
            // Empty stored payload — fail visibly rather than inventing structure.
            throw AppleStartMapperError.emptyBlocks
        }
        return try await api.mapToWorkoutKit(
            blocksJSON: blocksJSON,
            deliveryPrefs: deliveryPrefs
        )
    }
}

enum AppleStartMapperError: LocalizedError {
    case emptyBlocks
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .emptyBlocks:
            return "Workout has no stored blocks to compose for Apple Watch."
        case .invalidResponse:
            return "Mapper returned an unreadable WorkoutKit plan."
        }
    }
}
