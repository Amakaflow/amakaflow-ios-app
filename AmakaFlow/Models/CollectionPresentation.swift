//
//  CollectionPresentation.swift
//  AmakaFlow
//
//  AMA-2376: pure presentation helpers for Library collections grid.
//

import Foundation

enum CollectionPresentation {
    /// Sentinel id for derived Uncategorized folder (not a DB row).
    static let uncategorizedID = "uncategorized"

    /// Approximate total duration for collection cards, e.g. `~4H 10M`, `~40M`, `~0H`.
    static func formattedTotalDuration(seconds: Int) -> String {
        guard seconds > 0 else { return "~0H" }

        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours > 0 {
            return "~\(hours)H \(minutes)M"
        }
        return "~\(minutes)M"
    }
}
