//
//  SocialImportViewModel+Failure.swift
//  AmakaFlow
//
//  AMA-2308 — honest failure mapping + draft lifecycle helpers.
//  Kept in an extension so SocialImportViewModel stays under type_body_length.
//

import Foundation

extension SocialImportViewModel {
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

    /// Maps transport/auth failures into phase + structured diagnostics (AMA-2308).
    func failImport(_ error: Error, operation: String, intendedURL: String?) {
        SocialImportTransportDiagnostics.record(
            error,
            operation: operation,
            intendedURL: intendedURL
        )
        guard let failure = SocialImportFailure.map(error) else { return }
        phase = .failed(failure)
    }
}
