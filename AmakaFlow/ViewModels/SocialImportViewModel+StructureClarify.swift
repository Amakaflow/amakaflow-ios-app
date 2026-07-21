//
//  SocialImportViewModel+StructureClarify.swift
//  AmakaFlow
//
//  AMA-2305 — clarify step between social parse and save (ADR-017).
//

import Foundation

extension SocialImportViewModel {
    func confirmClarifyGroup(_ id: UUID) {
        guard var session = clarifySession else { return }
        session.confirm(groupID: id)
        clarifySession = session
    }

    func confirmAllClarifyGroups() {
        guard var session = clarifySession else { return }
        session.confirmAll()
        clarifySession = session
    }

    func undoClarifyGroup(_ id: UUID) {
        guard var session = clarifySession else { return }
        session.undo(groupID: id)
        clarifySession = session
    }

    func bumpClarifyRounds(_ id: UUID, delta: Int) {
        guard var session = clarifySession else { return }
        session.bumpRounds(groupID: id, delta: delta)
        clarifySession = session
    }

    func toggleClarifyRow(_ id: UUID) {
        guard var session = clarifySession else { return }
        session.toggleRowSelection(id)
        clarifySession = session
    }

    func clearClarifySelection() {
        guard var session = clarifySession else { return }
        session.clearSelection()
        clarifySession = session
    }

    func groupClarifySelection(as type: StructureBlockType) {
        guard var session = clarifySession else { return }
        session.groupSelected(as: type)
        clarifySession = session
    }

    /// Text fed to structure/suggest — caption preferred, else reconstructed list.
    func structureSuggestText(for draft: SocialImportDraft) -> String {
        if let caption = draft.postProvenance?.captionSnippet?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !caption.isEmpty {
            return caption
        }
        if let description = draft.workoutDescription?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !description.isEmpty {
            return description
        }
        return draft.exercises
            .map(\.name)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    func fallbackStructureExercises(from draft: SocialImportDraft) -> [StructureExerciseModel] {
        draft.exercises.map { exercise in
            StructureExerciseModel(
                name: exercise.name,
                sets: exercise.sets,
                reps: exercise.reps,
                restSec: nil,
                distanceM: exercise.distanceMeters,
                notes: exercise.detailInstruction
            )
        }
    }

    func applyConfirmedStructure(_ blocks: [StructureBlockModel], to draft: inout SocialImportDraft) {
        let socialBlocks: [SocialImportBlock] = blocks.map { block in
            SocialImportBlock(
                label: block.label,
                rounds: max(1, block.rounds ?? 1),
                exercises: block.exercises.map { model in
                    SocialImportExercise(
                        name: model.name,
                        sets: model.sets,
                        reps: model.reps,
                        distanceMeters: model.distanceM,
                        notes: model.notes
                    )
                },
                type: block.type.canonical.rawValue,
                restSec: block.restSec,
                structureSource: block.structureSource.rawValue
            )
        }
        draft.blocks = socialBlocks
        draft.exercises = socialBlocks.flatMap(\.exercises)
    }
}

extension StructureBlockModel {
    /// Assert save payload never contains unconfirmed inferred structure.
    var isPersistableConfirmedStructure: Bool {
        switch structureSource {
        case .inferred:
            return false
        case .explicit, .userConfirmed, .userNote, .unknown:
            return true
        }
    }
}
