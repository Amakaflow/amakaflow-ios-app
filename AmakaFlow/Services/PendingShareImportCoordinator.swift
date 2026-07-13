//
//  PendingShareImportCoordinator.swift
//  AmakaFlow
//
//  AMA-2285: consume Share Extension results written to the App Group
//  (`group.com.amakaflow.companion` / `pending_workout_imports`) and surface
//  an editable preview in the main app.
//

import Foundation
import Combine

/// Reads pending share-extension import results and exposes a draft for preview.
@MainActor
final class PendingShareImportCoordinator: ObservableObject {

    static let suiteName = "group.com.amakaflow.companion"
    static let pendingImportsKey = "pending_workout_imports"

    /// Mirror of AmakaFlowShare.SharedContainerManager.ImportResult
    struct ShareImportResult: Codable, Equatable {
        let url: String
        let platform: String
        let title: String?
        let workoutType: String?
        let success: Bool
        let errorMessage: String?
        let timestamp: Date
    }

    @Published var pendingDraft: SocialImportDraft?
    @Published var lastFailure: SocialImportFailure?

    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: PendingShareImportCoordinator.suiteName)) {
        self.defaults = defaults
    }

    /// Call on launch / becoming active. Consumes the newest successful import.
    func consumePendingImports() {
        let results = readPendingImports()
        guard !results.isEmpty else { return }

        if let success = results.reversed().first(where: { $0.success }) {
            pendingDraft = draft(from: success)
            lastFailure = nil
        } else if let failure = results.last {
            pendingDraft = nil
            lastFailure = .parse(
                message: failure.errorMessage ?? "Share import failed. Try pasting the link in Sources."
            )
        }

        clearPendingImports()
    }

    func clearPresentedDraft() {
        pendingDraft = nil
        lastFailure = nil
    }

    func readPendingImports() -> [ShareImportResult] {
        guard let defaults,
              let data = defaults.data(forKey: Self.pendingImportsKey) else {
            return []
        }
        return (try? JSONDecoder().decode([ShareImportResult].self, from: data)) ?? []
    }

    func clearPendingImports() {
        defaults?.removeObject(forKey: Self.pendingImportsKey)
    }

    private func draft(from result: ShareImportResult) -> SocialImportDraft {
        let platform = platform(from: result.platform, url: result.url)
        let title = (result.title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? "Imported Workout"
        let sport = (result.workoutType ?? "strength").lowercased()

        return SocialImportDraft(
            title: title,
            sport: sport,
            platform: platform,
            sourceURL: result.url,
            exercises: [SocialImportExercise(name: "Add exercises", sets: 3, reps: 10)],
            equipmentNote: "Imported from Share Extension — edit structure before saving.",
            equipmentEmpty: true
        )
    }

    private func platform(from raw: String, url: String) -> SocialImportPlatform {
        let lowered = raw.lowercased()
        if lowered.contains("instagram") { return .instagram }
        if lowered.contains("tiktok") { return .tiktok }
        if lowered.contains("youtube") { return .youtube }
        if lowered.contains("image") || lowered.contains("screenshot") { return .image }
        return SocialImportPlatform.detect(from: url)
    }
}
