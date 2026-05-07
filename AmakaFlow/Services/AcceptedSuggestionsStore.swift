//
//  AcceptedSuggestionsStore.swift
//  AmakaFlow
//
//  Local persistence for accepted Suggest-Workout results so they survive
//  app refreshes / re-fetches. The backend doesn't yet have an
//  accept-suggestion endpoint (TODO: AMA-1751-bug-1 backend follow-up),
//  so until that ships we keep accepted workouts in UserDefaults and merge
//  them into WorkoutsViewModel.incomingWorkouts after every API fetch.
//
//  When a workout is completed, it's removed from the store so it doesn't
//  resurface on the next load.
//

import Foundation

protocol AcceptedSuggestionsStoring {
    func all() -> [Workout]
    @discardableResult
    func save(_ workout: Workout) -> Bool
    func remove(id: String)
    func removeAll()
}

final class AcceptedSuggestionsStore: AcceptedSuggestionsStoring {

    static let shared = AcceptedSuggestionsStore()

    private let defaults: UserDefaults
    private let key = "amakaflow.acceptedSuggestions.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func all() -> [Workout] {
        guard let data = defaults.data(forKey: key) else { return [] }
        let decoder = JSONDecoder()

        do {
            return try decoder.decode([Workout].self, from: data)
        } catch {
            print("[AcceptedSuggestionsStore] Failed to decode accepted suggestions: \(error)")
            Task { @MainActor in
                DebugLogService.shared.log(
                    "Accepted suggestions decode failed",
                    details: error.localizedDescription
                )
            }
            return []
        }
    }

    @discardableResult
    func save(_ workout: Workout) -> Bool {
        var current = all()
        current.removeAll { $0.id == workout.id }
        current.append(workout)
        return write(current)
    }

    func remove(id: String) {
        var current = all()
        let before = current.count
        current.removeAll { $0.id == id }
        if current.count != before {
            write(current)
        }
    }

    func removeAll() {
        defaults.removeObject(forKey: key)
    }

    @discardableResult
    private func write(_ workouts: [Workout]) -> Bool {
        let encoder = JSONEncoder()

        do {
            let data = try encoder.encode(workouts)
            defaults.set(data, forKey: key)
            return defaults.synchronize()
        } catch {
            print("[AcceptedSuggestionsStore] Failed to encode accepted suggestions: \(error)")
            Task { @MainActor in
                DebugLogService.shared.log(
                    "Accepted suggestions encode failed",
                    details: error.localizedDescription
                )
            }
            return false
        }
    }
}
