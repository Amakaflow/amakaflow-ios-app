//
//  MapperWorkoutKitPlanProvider.swift
//  AmakaFlow
//
//  AMA-2351 — fetch mapper WKPlanDTO JSON via BFF for Apple Start cutover.
//

import Foundation

/// Fetches mapper WKPlanDTO JSON (via BFF). Production uses stored blocks_json.
protocol WorkoutKitPlanProviding: Sendable {
    func fetchMapperPlanJSON(for workout: Workout) async throws -> Data
}

struct MapperWorkoutKitPlanProvider: WorkoutKitPlanProviding {
    let api: any APIServiceProviding
    let deliveryPrefs: [String: Any]?

    init(api: any APIServiceProviding = APIService.shared, deliveryPrefs: [String: Any]? = nil) {
        self.api = api
        self.deliveryPrefs = deliveryPrefs
    }

    func fetchMapperPlanJSON(for workout: Workout) async throws -> Data {
        var blocksJSON = try await api.fetchWorkoutBlocksJSON(workoutId: workout.id)
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
