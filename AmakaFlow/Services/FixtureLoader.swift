//
//  FixtureLoader.swift
//  AmakaFlow
//
//  Loads workout fixtures from bundled JSON files for deterministic E2E testing.
//  Fixtures are shared across iOS and Android via amakaflow-automation/fixtures/.
//

#if DEBUG
import Foundation

/// Loads workout data from bundled JSON fixture files
/// Used when UITEST_USE_FIXTURES=true to provide deterministic test data
enum FixtureLoader {

    /// Load workouts based on UITEST_FIXTURES and UITEST_FIXTURE_STATE env vars
    static func loadWorkouts() throws -> [Workout] {
        let uiTestEnvironment = UITestEnvironment.shared

        // Handle special states
        if let state = uiTestEnvironment.fixtureState {
            switch state {
            case "empty":
                print("[FixtureLoader] UITEST_FIXTURE_STATE=empty, returning empty workouts")
                return []
            case "error":
                print("[FixtureLoader] UITEST_FIXTURE_STATE=error, simulating API failure")
                throw APIError.serverError(500)
            default:
                print("[FixtureLoader] Unknown UITEST_FIXTURE_STATE=\(state), ignoring")
            }
        }

        // Load specific fixtures or all
        if let names = uiTestEnvironment.fixtureNames {
            print("[FixtureLoader] Loading specific fixtures: \(names.joined(separator: ", "))")
            return try names.compactMap { name in
                try loadFixture(named: name)
            }
        } else {
            print("[FixtureLoader] Loading all bundled fixtures")
            return try loadAllFixtures()
        }
    }

    /// Load a single fixture file by name (without .json extension)
    static func loadFixture(named name: String) throws -> Workout {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            print("[FixtureLoader] ERROR: Fixture '\(name).json' not found in bundle")
            throw FixtureError.fixtureNotFound(name)
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            let workout = try decoder.decode(Workout.self, from: data)
            print("[FixtureLoader] Loaded fixture '\(name)': \(workout.name) (\(workout.intervals.count) intervals)")
            return workout
        } catch {
            print("[FixtureLoader] ERROR: Failed to decode '\(name).json': \(error)")
            throw FixtureError.decodingFailed(name, error)
        }
    }

    /// Load all fixture JSON files found in the bundle
    static func loadAllFixtures() throws -> [Workout] {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) else {
            print("[FixtureLoader] No JSON files found in bundle")
            return []
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        var workouts: [Workout] = []
        for url in urls {
            let filename = url.deletingPathExtension().lastPathComponent

            // Only load files that look like fixture workouts (have fixture- prefix)
            guard filename.hasPrefix("fixture-") || isKnownFixture(filename) else {
                continue
            }

            do {
                let data = try Data(contentsOf: url)
                let workout = try decoder.decode(Workout.self, from: data)
                workouts.append(workout)
                print("[FixtureLoader] Loaded '\(filename)': \(workout.name)")
            } catch {
                print("[FixtureLoader] WARNING: Skipping '\(filename).json': \(error.localizedDescription)")
            }
        }

        print("[FixtureLoader] Loaded \(workouts.count) fixture workout(s)")
        return workouts
    }

    /// Check if a filename matches a known fixture name
    private static func isKnownFixture(_ name: String) -> Bool {
        let knownFixtures = [
            "amrap_10min", "emom_strength", "for_time_conditioning",
            "strength_block_w1", "running_long", "hiit_follow_along"
        ]
        return knownFixtures.contains(name)
    }
}

// MARK: - Fixture Errors

enum FixtureError: LocalizedError {
    case fixtureNotFound(String)
    case decodingFailed(String, Error)

    var errorDescription: String? {
        switch self {
        case .fixtureNotFound(let name):
            return "Fixture '\(name).json' not found in app bundle"
        case .decodingFailed(let name, let error):
            return "Failed to decode fixture '\(name).json': \(error.localizedDescription)"
        }
    }
}
#endif
