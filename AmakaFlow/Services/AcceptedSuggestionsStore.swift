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
    func save(_ workout: Workout)
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
        return (try? decoder.decode([Workout].self, from: data)) ?? []
    }

    func save(_ workout: Workout) {
        var current = all()
        current.removeAll { $0.id == workout.id }
        current.append(workout)
        write(current)
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

    private func write(_ workouts: [Workout]) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(workouts) else { return }
        defaults.set(data, forKey: key)
    }
}
