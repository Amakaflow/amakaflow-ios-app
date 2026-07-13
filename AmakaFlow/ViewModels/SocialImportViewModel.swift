//
//  SocialImportViewModel.swift
//  AmakaFlow
//
//  AMA-2285: social ingest → editable preview → save to Library.
//  Edit is always allowed; AI never gatekeeps. Auth fail-fast via PairingService.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class SocialImportViewModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case importing
        case preview
        case saving
        case saved(workoutId: String)
        case failed(SocialImportFailure)
    }

    @Published var phase: Phase = .idle
    @Published var draft: SocialImportDraft?
    /// Edit is always allowed once a draft exists — never gated on AI success.
    @Published private(set) var canEdit: Bool = true

    private let dependencies: AppDependencies

    init(dependencies: AppDependencies = .current) {
        self.dependencies = dependencies
    }

    // MARK: - Import

    func importURL(_ urlString: String, platformHint: SocialImportPlatform? = nil) async {
        guard ensureAuthenticated() else { return }

        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            phase = .failed(.parse(message: "Paste a workout URL first."))
            return
        }

        phase = .importing
        let platform = platformHint ?? SocialImportPlatform.detect(from: trimmed)

        do {
            let equipment = await dependencies.apiService.socialImportEquipmentContext()
            let data = try await dependencies.apiService.ingestSocialURL(url: trimmed, platform: platform)
            let parsed = try SocialImportDraft.fromIngestJSON(
                data,
                platform: platform,
                sourceURL: trimmed,
                equipmentEmpty: equipment.empty,
                equipmentNote: equipment.note
            )
            draft = parsed
            canEdit = true
            phase = .preview
        } catch {
            phase = .failed(SocialImportFailure.map(error))
        }
    }

    func importPlainText(_ text: String, sourceURL: String? = nil) async {
        guard ensureAuthenticated() else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            phase = .failed(.parse(message: "Paste workout text first."))
            return
        }

        phase = .importing
        let platform: SocialImportPlatform = .manual

        do {
            let equipment = await dependencies.apiService.socialImportEquipmentContext()
            let data = try await dependencies.apiService.ingestSocialText(text: trimmed, source: sourceURL)
            let parsed = try SocialImportDraft.fromIngestJSON(
                data,
                platform: platform,
                sourceURL: sourceURL,
                equipmentEmpty: equipment.empty,
                equipmentNote: equipment.note
            )
            draft = parsed
            canEdit = true
            phase = .preview
        } catch {
            phase = .failed(SocialImportFailure.map(error))
        }
    }

    func importImageData(_ imageData: Data, filename: String = "workout.jpg") async {
        guard ensureAuthenticated() else { return }
        guard !imageData.isEmpty else {
            phase = .failed(.parse(message: "No image data to import."))
            return
        }

        phase = .importing
        let platform: SocialImportPlatform = .image

        do {
            let equipment = await dependencies.apiService.socialImportEquipmentContext()
            let data = try await dependencies.apiService.ingestSocialImage(imageData: imageData, filename: filename)
            let parsed = try SocialImportDraft.fromIngestJSON(
                data,
                platform: platform,
                sourceURL: nil,
                equipmentEmpty: equipment.empty,
                equipmentNote: equipment.note
            )
            draft = parsed
            canEdit = true
            phase = .preview
        } catch {
            phase = .failed(SocialImportFailure.map(error))
        }
    }

    // MARK: - Edit

    func updateTitle(_ title: String) {
        guard canEdit, var draft else { return }
        draft.title = title
        self.draft = draft
    }

    func updateExercise(id: UUID, name: String? = nil, sets: Int? = nil, reps: Int? = nil, seconds: Int? = nil, notes: String? = nil) {
        guard canEdit, var draft else { return }
        guard let index = draft.exercises.firstIndex(where: { $0.id == id }) else { return }
        if let name { draft.exercises[index].name = name }
        if let sets { draft.exercises[index].sets = sets }
        if let reps { draft.exercises[index].reps = reps }
        if let seconds { draft.exercises[index].seconds = seconds }
        if let notes { draft.exercises[index].notes = notes }
        self.draft = draft
    }

    func addExercise() {
        guard canEdit, var draft else { return }
        draft.exercises.append(SocialImportExercise(name: "New exercise", sets: 3, reps: 10))
        self.draft = draft
    }

    func removeExercise(id: UUID) {
        guard canEdit, var draft else { return }
        draft.exercises.removeAll { $0.id == id }
        if draft.exercises.isEmpty {
            draft.exercises = [SocialImportExercise(name: "Add exercises", sets: 3, reps: 10)]
        }
        self.draft = draft
    }

    // MARK: - Save

    func saveToLibrary() async {
        guard ensureAuthenticated() else { return }
        guard let draft else {
            phase = .failed(.parse(message: "Nothing to save yet — import a workout first."))
            return
        }

        phase = .saving
        do {
            let request = draft.toWorkoutSaveRequest()
            let workout = try await dependencies.apiService.saveWorkout(request)
            self.draft = draft
            canEdit = true
            phase = .saved(workoutId: workout.id)
        } catch {
            phase = .failed(SocialImportFailure.map(error))
        }
    }

    func loadDraft(_ draft: SocialImportDraft) {
        self.draft = draft
        canEdit = true
        phase = .preview
    }

    func reset() {
        phase = .idle
        draft = nil
        canEdit = true
    }

    // MARK: - Auth

    @discardableResult
    private func ensureAuthenticated() -> Bool {
        guard dependencies.pairingService.isPaired else {
            phase = .failed(.auth(message: "Open AmakaFlow and sign in, then try importing again."))
            return false
        }
        return true
    }
}
