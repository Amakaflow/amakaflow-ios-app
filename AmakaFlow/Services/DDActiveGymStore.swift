//
//  DDActiveGymStore.swift
//  AmakaFlow
//
//  Persists the user's active gym locally until backend sync exists.
//

import Foundation

enum DDActiveGymStore {
    struct ActiveGym: Codable, Equatable {
        let id: String
        let name: String
    }

    private static let defaultsKey = "dd_active_gym_v1"

    static func save(id: String, name: String) {
        let gym = ActiveGym(id: id, name: name)
        guard let data = try? JSONEncoder().encode(gym) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    static func load() -> ActiveGym? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(ActiveGym.self, from: data)
    }
}
