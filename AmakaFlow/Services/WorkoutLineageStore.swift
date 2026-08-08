//
//  WorkoutLineageStore.swift
//  AmakaFlow
//
//  AMA-2389: Client-side lineageId persistence until BFF exposes the field.
//

import Foundation

protocol WorkoutLineageStoring: Sendable {
    func lineageId(forWorkoutId workoutId: String) -> String?
    func setLineageId(_ lineageId: String, forWorkoutId workoutId: String)
    func fingerprint(forWorkoutId workoutId: String) -> String?
    func setFingerprint(_ fingerprint: String, forWorkoutId workoutId: String)
}

final class UserDefaultsWorkoutLineageStore: WorkoutLineageStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let lineageKey = "ama2389.workout.lineage"
    private let fingerprintKey = "ama2389.workout.fingerprint"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func lineageId(forWorkoutId workoutId: String) -> String? {
        dictionary(for: lineageKey)[workoutId]
    }

    func setLineageId(_ lineageId: String, forWorkoutId workoutId: String) {
        var map = dictionary(for: lineageKey)
        map[workoutId] = lineageId
        defaults.set(map, forKey: lineageKey)
    }

    func fingerprint(forWorkoutId workoutId: String) -> String? {
        dictionary(for: fingerprintKey)[workoutId]
    }

    func setFingerprint(_ fingerprint: String, forWorkoutId workoutId: String) {
        var map = dictionary(for: fingerprintKey)
        map[workoutId] = fingerprint
        defaults.set(map, forKey: fingerprintKey)
    }

    private func dictionary(for key: String) -> [String: String] {
        defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }
}
