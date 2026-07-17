//
//  DDEditorBackfillStore.swift
//  AmakaFlow
//
//  Persists profile backfill editor drafts locally until completion API exists.
//

import Foundation

enum DDEditorBackfillStore {
    private static let defaultsKey = "dd_profile_backfill_draft_v1"

    struct Payload: Codable {
        var title: String
        var savedAt: Date
        var blockCount: Int
        var exerciseCount: Int
    }

    static func save(title: String, blocks: [DDEditorBlockDraft]) {
        let payload = Payload(
            title: title,
            savedAt: Date(),
            blockCount: blocks.count,
            exerciseCount: blocks.reduce(0) { $0 + $1.exercises.count }
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    static func load() -> Payload? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }
}
