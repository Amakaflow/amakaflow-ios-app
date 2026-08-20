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
                // Total for the same reason the outer map is: dropping a
                // missing member would let a LATER member impersonate the row
                // title and would hide the loss entirely.
                let members = group.memberIDs.map { exercises[$0]?.name ?? Self.missingRowTitle }
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

    /// Rows for the NESTED reorder sheet: every `order` entry contributes a
    /// row, and a group's members follow their header as their own rows so
    /// they can be dragged WITHIN the block. Same totality rule as
    /// `reorderRows` — one header per `order` entry, one row per member, so
    /// `reorderNested(fromOffsets:toOffset:)` can translate flat indices back
    /// to (`order` index, member index) by walking this exact shape.
    var reorderNestedRows: [EditorV2ReorderEntry] {
        order.flatMap { row -> [EditorV2ReorderEntry] in
            switch row {
            case .loose(let id):
                return [EditorV2ReorderEntry(
                    id: row.id,
                    title: exercises[id]?.name ?? Self.missingRowTitle,
                    caption: nil,
                    memberNames: [],
                    accent: nil
                )]
            case .group(let key):
                guard let group = groups[key] else {
                    return [EditorV2ReorderEntry(
                        id: row.id,
                        title: Self.missingRowTitle,
                        caption: nil,
                        memberNames: [],
                        accent: nil
                    )]
                }
                let header = EditorV2ReorderEntry(
                    id: row.id,
                    title: group.name,
                    caption: "MOVES AS ONE BLOCK",
                    memberNames: [],
                    accent: group.type,
                    groupKey: key
                )
                let members = group.memberIDs.map { memberID in
                    EditorV2ReorderEntry(
                        id: memberID,
                        title: exercises[memberID]?.name ?? Self.missingRowTitle,
                        caption: nil,
                        memberNames: [],
                        accent: group.type,
                        groupKey: key,
                        isMember: true
                    )
                }
                return [header] + members
            }
        }
    }

    /// Translate a drag over `reorderNestedRows` into the right command:
    /// a member row reorders inside its own block (`.reorderGroupMembers`);
    /// a header or loose row reorders `order` (`.reorder`). A member dropped
    /// outside its block is rejected — the list snaps back.
    @discardableResult
    mutating func reorderNested(fromOffsets: IndexSet, toOffset: Int) -> ApplyResult {
        guard let source = fromOffsets.first, fromOffsets.count == 1 else {
            return .rejected(.invalidState)
        }
        // Walk `order` mirroring reorderNestedRows: headerFlat[i] is the flat
        // index of order[i]'s own row; a group's members occupy the next
        // `memberCounts[i]` slots.
        var headerFlat: [Int] = []
        var memberCounts: [Int] = []
        var flat = 0
        for row in order {
            headerFlat.append(flat)
            let count: Int
            if case .group(let key) = row { count = groups[key]?.memberIDs.count ?? 0 } else { count = 0 }
            memberCounts.append(count)
            flat += 1 + count
        }
        let flatCount = flat
        guard source < flatCount, toOffset >= 0, toOffset <= flatCount else {
            return .rejected(.invalidState)
        }

        if let top = headerFlat.firstIndex(of: source) {
            // Header / loose row → top-level reorder. An insertion point that
            // falls inside another block's members means "after that block".
            let topTo = headerFlat.filter { $0 < toOffset }.count
            return apply(.reorder(fromOffsets: IndexSet(integer: top), toOffset: topTo))
        }

        // Member row: find its block and keep the drop inside it.
        guard let top = headerFlat.lastIndex(where: { $0 < source }),
              case .group(let key) = order[top] else {
            return .rejected(.invalidState)
        }
        let membersStart = headerFlat[top] + 1
        let membersEnd = membersStart + memberCounts[top]
        guard source < membersEnd, toOffset >= membersStart, toOffset <= membersEnd else {
            return .rejected(.invalidState)
        }
        return apply(.reorderGroupMembers(
            key: key,
            fromOffsets: IndexSet(integer: source - membersStart),
            toOffset: toOffset - membersStart
        ))
    }
}
