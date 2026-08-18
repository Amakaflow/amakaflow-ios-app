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
    ///
    /// This mapping is deliberately TOTAL — one row out per `order` entry, never
    /// `compactMap`. Dropping an entry whose exercise or group is missing would
    /// shorten the list relative to `order`, shifting every later index and
    /// reintroducing the very desynchronisation this property exists to prevent.
    /// A dangling reference is shown as an unnamed row rather than vanishing.
    var reorderRows: [EditorV2ReorderEntry] {
        order.map { row in
            switch row {
            case .loose(let id):
                return EditorV2ReorderEntry(
                    id: row.id,
                    title: exercises[id]?.name ?? Self.missingRowTitle,
                    caption: nil,
                    memberNames: [],
                    accent: nil
                )
            case .group(let key):
                guard let group = groups[key] else {
                    return EditorV2ReorderEntry(
                        id: row.id,
                        title: Self.missingRowTitle,
                        caption: nil,
                        memberNames: [],
                        accent: nil
                    )
                }
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

    /// Shown when an `order` entry points at an exercise or group that is no
    /// longer present. It still occupies its slot so the drag maths stays exact.
    static let missingRowTitle = "Untitled exercise"
}
