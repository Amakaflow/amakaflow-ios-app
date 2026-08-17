//
//  EditorV2WheelLayout.swift
//  AmakaFlow
//
//  AMA-2443 slice 5 — which wheels the focused numbers sheet shows.
//
//  screens-editor3.jsx "Numbers sheet v3.1": TRACK is exclusive, Weight is an
//  add-on, and the row never exceeds three columns. Keeping that as a pure
//  function makes the three-column rule a unit test instead of a code review.
//

import Foundation

enum EditorV2WheelColumn: String, Equatable {
    case sets
    case reps
    case seconds
    case meters
    case calories
    /// Legacy rep range — one column carrying both bounds, so a ranged
    /// exercise can still show weight without a fourth column.
    case range
    case weight

    /// Stable across the stepper→wheel swap — `e2e/maestro/ama-2379-edit-sheet-v2.yaml`
    /// and the AMA-2446 scenario matrix address these by name.
    var accessibilityIdentifier: String {
        switch self {
        case .sets: return "af_exsheet_sets"
        case .reps: return "af_exsheet_reps"
        case .seconds: return "af_exsheet_work"
        case .meters: return "af_exsheet_meters"
        case .calories: return "af_exsheet_calories"
        case .range: return "af_exsheet_range"
        case .weight: return "af_exsheet_weight"
        }
    }
}

enum EditorV2WheelLayout {
    static let maxColumns = 3

    static func columns(
        track: EditorV2EditTargetKind,
        weightOn: Bool
    ) -> [EditorV2WheelColumn] {
        var columns = quantityColumns(for: track)
        if weightOn {
            columns.append(.weight)
        }
        assert(
            columns.count <= maxColumns,
            "\(track) with weight=\(weightOn) produced \(columns.count) wheels"
        )
        return columns
    }

    /// Distance drops SETS — a 400 m row is one effort, not four (rig line 606).
    /// Open goal has no quantity to spin at all.
    private static func quantityColumns(for track: EditorV2EditTargetKind) -> [EditorV2WheelColumn] {
        switch track {
        case .reps: return [.sets, .reps]
        case .timed: return [.sets, .seconds]
        case .distance: return [.meters]
        case .cals: return [.sets, .calories]
        case .range: return [.sets, .range]
        case .open: return []
        }
    }
}
