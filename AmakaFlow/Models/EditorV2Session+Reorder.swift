//
//  EditorV2Session+Reorder.swift
//  AmakaFlow
//
//  AMA-2459 — the reorder sheet must drag the SAME list `.reorder` mutates.
//
//  Split from EditorV2Session.swift, which is at the SwiftLint file_length
//  limit.
//

import Foundation

extension EditorV2Session {
    /// Rows for the reorder sheet, in the SAME sequence `order` holds — because
/// `.reorder(fromOffsets:toOffset:)` moves entries of `order`, so the list
/// the user drags MUST be that list. AMA-2459: this used to iterate
/// `exercises.values`, an unordered dictionary at exercise granularity, so
/// the sheet showed a different sequence than the editor AND the drag
/// offsets indexed a different collection than the command mutated.
///
/// A group is one draggable row (that is what `order` moves); its members
/// are listed on the row so the user can see what travels with it.
var reorderRows: [EditorV2ReorderEntry] {
    order.compactMap { row in
        switch row {
        case .loose(let id):
            guard let exercise = exercises[id] else { return nil }
            return EditorV2ReorderEntry(
                id: row.id,
                title: exercise.name,
                caption: nil,
                memberNames: [],
                accent: nil
            )
        case .group(let key):
            guard let group = groups[key] else { return nil }
            let members = group.memberIDs.compactMap { exercises[$0]?.name }
            return EditorV2ReorderEntry(
                id: row.id,
                title: members.first ?? group.name,
                caption: group.name.uppercased(),
                memberNames: Array(members.dropFirst()),
                accent: group.type
            )
        }
    }
}
}
