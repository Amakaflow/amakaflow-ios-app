//
//  SocialImportViewModel.swift
//  AmakaFlow
//
//  AMA-2285: social ingest → editable preview → save to Library.
//  Edit is always allowed; AI never gatekeeps. Auth fail-fast via PairingService.
//

import Combine
import Foundation
import os.log
import SwiftUI

private let logger = Logger(subsystem: "com.myamaka.AmakaFlowCompanion", category: "SocialImport")

@MainActor
final class SocialImportViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case importing
        case clarify
        case preview
        case saving
        case saved(workoutId: String)
        case failed(SocialImportFailure)
    }

    @Published var phase: Phase = .idle
    @Published var draft: SocialImportDraft?
    /// Edit is always allowed once a draft exists — never gated on AI success.
    @Published private(set) var canEdit: Bool = true
    /// AMA-2305 clarify session (nil until suggest completes or falls back flat).
    @Published var clarifySession: StructureClarifySession?
    @Published var isReadingNote: Bool = false
    @Published var describeNote: String = ""

    private let dependencies: AppDependencies

    init(dependencies: AppDependencies = .current) {
        self.dependencies = dependencies
    }

    // MARK: - Import

    func importURL(_ urlString: String, platformHint: SocialImportPlatform? = nil) async {
        guard ensureAuthenticated() else { return }

        let trimmed = SocialImportPlatform.normalizeForIngest(
            urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        )
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
            await enterClarify(for: parsed)
        } catch {
            failImport(
                error,
                operation: "importURL",
                intendedURL: "\(AppEnvironment.current.ingestorAPIURL)/ingest/\(platform.ingestPath)"
            )
        }
    }

    func importPlainText(_ text: String, platform: SocialImportPlatform = .manual, sourceURL: String? = nil) async {
        guard ensureAuthenticated() else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            phase = .failed(.parse(message: "Paste workout text first."))
            return
        }

        phase = .importing

        do {
            let equipment = await dependencies.apiService.socialImportEquipmentContext()
            let data = try await dependencies.apiService.ingestSocialText(
                text: trimmed,
                source: sourceURL ?? platform.rawValue
            )
            let parsed = try SocialImportDraft.fromIngestJSON(
                data,
                platform: platform,
                sourceURL: sourceURL,
                equipmentEmpty: equipment.empty,
                equipmentNote: equipment.note
            )
            draft = parsed
            canEdit = true
            await enterClarify(for: parsed)
        } catch {
            failImport(
                error,
                operation: "importPlainText",
                intendedURL: "\(AppEnvironment.current.ingestorAPIURL)/ingest/text"
            )
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
            await enterClarify(for: parsed)
        } catch {
            failImport(
                error,
                operation: "importImage",
                intendedURL: "\(AppEnvironment.current.ingestorAPIURL)/ingest/image"
            )
        }
    }

    // MARK: - Clarify (AMA-2305)

    /// After parse — always land on clarify (never silent structural commit).
    func enterClarify(for draft: SocialImportDraft) async {
        let text = structureSuggestText(for: draft)
        let fallback = fallbackStructureExercises(from: draft)
        do {
            let result = try await dependencies.apiService.suggestStructure(
                text: text.isEmpty
                    ? fallback.map(\.name).joined(separator: "\n")
                    : text,
                source: draft.sourceURL ?? draft.platform.rawValue
            )
            let merged = result.exercises.isEmpty
                ? StructureSuggestResult(
                    exercises: fallback,
                    suggestions: result.suggestions,
                    blocks: result.blocks
                )
                : result
            clarifySession = StructureClarifySession.fromSuggest(merged, fallbackExercises: fallback)
        } catch {
            // Missing BFF → flat rows (MOCK/SKIP), never crash the import path.
            logger.warning("structure/suggest failed — falling back to flat clarify: \(String(describing: error))")
            clarifySession = StructureClarifySession.fromSuggest(
                StructureSuggestResult(exercises: fallback, suggestions: [], blocks: []),
                fallbackExercises: fallback
            )
        }
        phase = .clarify
    }

    /// Describe sheet → live structure/apply (replaces units; never stacks).
    func applyDescribeNote() async {
        guard ensureAuthenticated() else { return }
        guard var session = clarifySession else { return }
        let note = describeNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { return }

        isReadingNote = true
        defer { isReadingNote = false }

        let request = ApplyStructureRequest(
            blocks: session.workingBlocksForApply(),
            ops: nil,
            note: note
        )
        do {
            let result = try await dependencies.apiService.applyStructure(request)
            // Idempotent replace — never append/stack on prior groups.
            session.replace(withAppliedBlocks: result.blocks)
            clarifySession = session
            phase = .clarify
        } catch {
            failImport(
                error,
                operation: "applyDescribeNote",
                intendedURL: "\(AppEnvironment.current.mobileBFFURL)/v1/ingest/structure/apply"
            )
        }
    }

    /// Looks right — Save / Leave flat. Applies confirmed structure then saves.
    func saveFromClarify(leaveFlat: Bool) async {
        guard var draft, let session = clarifySession else {
            phase = .failed(.parse(message: "Nothing to save yet — import a workout first."))
            return
        }
        guard phase != .saving else { return }
        let blocks = session.blocksForSave(leaveFlat: leaveFlat)
            .filter { $0.structureSource != .inferred && $0.structureSource != .explicit }
        applyConfirmedStructure(blocks, to: &draft)
        self.draft = draft
        await saveToLibrary()
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

        let usableExercises = draft.exercises.filter {
            let name = $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return !name.isEmpty && name.lowercased() != "add exercises"
        }
        guard !usableExercises.isEmpty else {
            phase = .failed(.parse(message: "Add at least one exercise before saving — import didn't extract a usable list."))
            return
        }

        phase = .saving
        do {
            let request = draft.toWorkoutSaveRequest()
            let workout = try await dependencies.apiService.saveWorkout(request)
            let enriched = WorkoutLibraryDetailStore.enrichFromDraft(workout, draft: draft)
            switch WorkoutLibraryDetailStore.save(enriched) {
            case .success:
                self.draft = draft
                canEdit = true
                phase = .saved(workoutId: workout.id)
            case .failure(let error):
                logger.warning("saveToLibrary: server save succeeded but local detail cache failed — \(String(describing: error))")
                DebugLogService.shared.log(
                    "Social import: local detail cache failed after server save",
                    details: String(describing: error),
                    metadata: ["workoutId": workout.id]
                )
                self.draft = draft
                canEdit = true
                phase = .saved(workoutId: workout.id)
            }
        } catch {
            failImport(
                error,
                operation: "saveToLibrary",
                intendedURL: "\(AppEnvironment.current.mobileBFFURL)/v1/workouts/save"
            )
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
        clarifySession = nil
        isReadingNote = false
        describeNote = ""
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
