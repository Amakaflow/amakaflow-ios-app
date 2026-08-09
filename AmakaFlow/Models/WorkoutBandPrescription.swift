//
//  WorkoutBandPrescription.swift
//  AmakaFlow
//
//  AMA-2395 — ONE prescription grammar for every band row, whatever the
//  source: `3 × 8`, `3 × 8–12`, `500 M`, `1.0 KM`, `3:00`, `12 CAL`, `OPEN`,
//  with `· REST 90S` and `· ≈ 7 MIN` suffixes.
//

import Foundation

enum WorkoutBandPrescription {
    /// `3 × 8` · `3 × 8–12` · `500 M` · `1.0 KM` · `3:00` · `12 CAL` · `OPEN`,
    /// plus `· REST 90S` and `· ≈ 7 MIN` suffixes. One format everywhere.
    static func line(for exercise: Exercise, estimate: WorkoutDurationComponent?) -> String {
        var parts: [String] = []
        let primary = PrescriptionFormatter.primaryLine(
            PrescriptionFormatter.effective(from: exercise).primary
        )
        let resolved = primary.flatMap { $0.isEmpty ? nil : $0 } ?? "OPEN"
        parts.append(resolved.uppercased())

        if let rest = exercise.restSeconds, rest > 0 {
            parts.append("REST \(rest)S")
        }
        // Per-exercise minutes only earn their place on estimated (strength)
        // rows — a timed row already shows its own duration.
        if let estimate, estimate.isEstimate, estimate.seconds >= 60, exercise.durationSeconds == nil {
            parts.append(WorkoutDurationEstimate.label(seconds: estimate.seconds, isEstimate: true))
        }
        return parts.joined(separator: " · ")
    }

    static func distanceLabel(metres: Double) -> String {
        metres >= 1000
            ? String(format: "%.1f KM", metres / 1000)
            : "\(Int(metres.rounded())) M"
    }
}
