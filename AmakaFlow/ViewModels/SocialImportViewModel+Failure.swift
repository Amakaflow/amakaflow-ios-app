//
//  SocialImportViewModel+Failure.swift
//  AmakaFlow
//
//  AMA-2308 — honest failure mapping.
//  Kept in an extension so SocialImportViewModel stays under type_body_length.
//

import Foundation

extension SocialImportViewModel {
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
