//
//  LibraryViewModel+LibraryActions.swift
//  AmakaFlow
//
//  Delete, filter, and presentation helpers for LibraryViewModel.
//

import Foundation
import os.log

extension LibraryViewModel {
    /// Resolve which delete API a unified-workout detail should call.
    func deleteTarget(forWorkoutID workoutID: String) -> LibraryListEntry? {
        if let workout = workoutsByID[workoutID] {
            return .workout(workout)
        }
        if let knowledge = allItems.first(where: { $0.id == workoutID }) {
            return .knowledge(knowledge)
        }
        return nil
    }

    /// Knowledge detail delete target.
    func deleteTarget(forKnowledgeID itemID: String) -> LibraryListEntry? {
        guard let knowledge = allItems.first(where: { $0.id == itemID }) else { return nil }
        return .knowledge(knowledge)
    }

    /// Optimistic remove from Library; restores row + toast on API failure.
    /// - Returns: `true` when the remote delete succeeded.
    @discardableResult
    func deleteEntry(_ entry: LibraryListEntry) async -> Bool {
        guard !isDeleting else { return false }
        isDeleting = true
        // Invalidate in-flight loads so they cannot re-add the row mid-delete.
        contentEpoch += 1
        let epoch = contentEpoch
        defer { isDeleting = false }

        let startedAt = CFAbsoluteTimeGetCurrent()
        ctaError = nil
        lastFailedAction = nil

        let previousItems = allItems
        let previousWorkouts = allWorkouts

        switch entry {
        case .knowledge(let item):
            allItems.removeAll { $0.id == item.id }
        case .workout(let workout):
            // Keep any ID-colliding knowledge card; it reappears after workout delete.
            allWorkouts.removeAll { $0.id == workout.id }
        }
        workoutsByID = Dictionary(uniqueKeysWithValues: allWorkouts.map { ($0.id, $0) })
        applyFilters()

        do {
            switch entry {
            case .knowledge(let item):
                try await apiService.deleteKnowledgeCard(id: item.id)
            case .workout(let workout):
                try await apiService.deleteWorkout(id: workout.id)
                // AMA-2376: optimistic removal already dropped this workout; known set
                // still includes workout-kind knowledge IDs that open synthetic detail.
                try? collectionsStore.pruneOrphans(knownWorkoutIds: knownCollectionWorkoutIDs)
            }

            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
            DebugLogService.shared.log(
                "Library delete",
                details: "entry=\(entry.id) elapsedMs=\(elapsedMs)",
                metadata: [
                    "entryId": entry.id,
                    "elapsedMs": "\(elapsedMs)"
                ]
            )

            // Notify other surfaces. `object: self` lets LibraryView skip a redundant
            // full refetch after its own optimistic remove (efficiency bar).
            NotificationCenter.default.post(name: .libraryContentDidChange, object: self)
            return true
        } catch {
            // Only restore if this delete is still the latest content mutation.
            if epoch == contentEpoch {
                allItems = previousItems
                allWorkouts = previousWorkouts
                workoutsByID = Dictionary(uniqueKeysWithValues: allWorkouts.map { ($0.id, $0) })
                applyFilters()
            }
            if CTAError.isCancellation(error) {
                return false
            }
            ctaError = CTAError.map(error)
            lastFailedAction = .delete(entry)
            return false
        }
    }

    func toggleKind(_ kind: LibraryKind) {
        if selectedKinds.contains(kind) {
            selectedKinds.remove(kind)
        } else {
            selectedKinds.insert(kind)
        }
        applyFilters()
    }

    func clearKindFilters() {
        selectedKinds.removeAll()
        applyFilters()
    }

    func selectTag(_ tag: String?) {
        let normalized = tag.flatMap(Self.normalizedTag)
        if selectedTag == normalized {
            selectedTag = nil
        } else {
            selectedTag = normalized
        }
        applyFilters()
    }

    func clearFilters() {
        selectedKinds.removeAll()
        selectedTag = nil
        applyFilters()
    }

    func isKindSelected(_ kind: LibraryKind) -> Bool {
        selectedKinds.contains(kind)
    }

    func isTagSelected(_ tag: String) -> Bool {
        guard let selectedTag else { return false }
        return Self.tagsEqual(tag, selectedTag)
    }

    func dismissError() {
        let currentError = ctaError
        ctaError = nil

        if case .load = lastFailedAction, let currentError, allItems.isEmpty, allWorkouts.isEmpty {
            state = .error(currentError)
        }
    }

    func reportError(reporter: ErrorReporting? = nil) {
        guard let ctaError else { return }
        let reporter = reporter ?? ErrorReporter.shared
        let action: String
        let endpoint: String
        switch lastFailedAction {
        case .delete(let entry):
            action = "library_item_delete"
            switch entry {
            case .knowledge:
                endpoint = "/v1/knowledge/cards/{card_id}"
            case .workout:
                endpoint = "/workouts/{workout_id}"
            }
        case .load, .none:
            action = "library_items_load"
            endpoint = "/v1/library/items"
        }
        reporter.report(
            action: action,
            error: ctaError,
            endpoint: endpoint,
            userId: PairingService.shared.userProfile?.id
        )
    }

    /// Debug-only trail when a superseded Library reload is dropped (incl. URLError -999).
    /// Surfaces in Console (os.Logger) and Settings → Debug Log for TestFlight diagnosis.
    func logSuppressedLoad(reason: String, generation: Int, error: Error? = nil) {
        var metadata: [String: String] = [
            "reason": reason,
            "generation": "\(generation)",
            "currentGeneration": "\(loadGeneration)",
            "contentEpoch": "\(contentEpoch)"
        ]
        if let error {
            metadata["error"] = String(describing: error)
            if let urlError = error as? URLError {
                metadata["urlErrorCode"] = "\(urlError.code.rawValue)"
            }
        }
        let details = metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
        libraryLogger.debug("load suppressed (\(reason)): \(details)")
        DebugLogService.shared.log(
            "Library reload superseded",
            details: details,
            metadata: metadata
        )
    }

    func applyFilters() {
        items = Self.filtered(
            allItems,
            selectedKinds: selectedKinds,
            selectedTag: selectedTag
        )
        entries = Self.mergedEntries(
            workouts: allWorkouts,
            knowledge: allItems,
            selectedKinds: selectedKinds,
            selectedTag: selectedTag
        )
        state = entries.isEmpty ? .empty : .content
    }

    static func filtered(
        _ source: [LibraryItem],
        selectedKinds: Set<LibraryKind>,
        selectedTag: String?
    ) -> [LibraryItem] {
        let normalizedSelectedTag = selectedTag.flatMap(normalizedTag)
        return source.filter { item in
            let kindMatches = selectedKinds.isEmpty || selectedKinds.contains(item.kind)
            let tagMatches: Bool
            if let normalizedSelectedTag {
                tagMatches = (item.tags ?? []).contains { tag in
                    tagsEqual(tag, normalizedSelectedTag)
                }
            } else {
                tagMatches = true
            }
            return kindMatches && tagMatches
        }
    }

    /// Workouts first (any source), then non-workout knowledge cards. Knowledge `.workout`
    /// cards that don't match a saved Workout stay as synthetic workout entries via tap routing.
    static func mergedEntries(
        workouts: [Workout],
        knowledge: [LibraryItem],
        selectedKinds: Set<LibraryKind>,
        selectedTag: String?
    ) -> [LibraryListEntry] {
        let showWorkouts = selectedKinds.isEmpty || selectedKinds.contains(.workout)
        let normalizedTag = selectedTag.flatMap(normalizedTag)

        var result: [LibraryListEntry] = []

        if showWorkouts {
            for workout in workouts {
                if let normalizedTag {
                    let badge = WorkoutSourceProvenance.badge(for: workout.source.rawValue)?.label.lowercased()
                    let matches = badge.map { tagsEqual($0, normalizedTag) } ?? false
                    if !matches { continue }
                }
                result.append(.workout(workout))
            }
        }

        let knowledgeFiltered = filtered(knowledge, selectedKinds: selectedKinds, selectedTag: selectedTag)
        for item in knowledgeFiltered {
            // Prefer the structured Workout row when IDs collide.
            if case .workout = item.kind, workouts.contains(where: { $0.id == item.id }) {
                continue
            }
            // Knowledge workout without a matching Workout still appears; detail synthesizes.
            result.append(.knowledge(item))
        }

        return result
    }

    static func syntheticWorkout(from item: LibraryItem) -> Workout {
        let source = inferredSource(from: item)
        return Workout(
            id: item.id,
            name: item.title,
            sport: .strength,
            duration: 0,
            blocks: [],
            description: item.sourceDomain,
            source: source,
            sourceUrl: item.sourceUrl
        )
    }

    static func inferredSource(from item: LibraryItem) -> WorkoutSource {
        let domain = (item.sourceDomain ?? item.sourceUrl ?? "").lowercased()
        if domain.contains("instagram") { return .instagram }
        if domain.contains("tiktok") { return .tiktok }
        if domain.contains("youtube") || domain.contains("youtu.be") { return .youtube }
        if domain.contains("coach") || domain.contains("amakaflow") { return .coach }
        return .manual
    }

    static func normalizedTag(_ tag: String) -> String? {
        let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    static func tagsEqual(_ lhs: String, _ rhs: String) -> Bool {
        guard let normalizedLeft = normalizedTag(lhs), let normalizedRight = normalizedTag(rhs) else {
            return false
        }
        return normalizedLeft.compare(
            normalizedRight,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) == .orderedSame
    }

    static var displayKinds: [LibraryKind] {
        [.workout, .video, .article, .plan]
    }

    static func kindLabel(_ kind: LibraryKind) -> String {
        switch kind {
        case .workout: return "Workouts"
        case .video: return "Videos"
        case .article: return "Articles"
        case .plan: return "Plans"
        }
    }

    static func kindSingularLabel(_ kind: LibraryKind) -> String {
        switch kind {
        case .workout: return "Workout"
        case .video: return "Video"
        case .article: return "Article"
        case .plan: return "Plan"
        }
    }

    static func kindIcon(_ kind: LibraryKind) -> String {
        switch kind {
        case .workout: return "figure.strengthtraining.traditional"
        case .video: return "play.rectangle.fill"
        case .article: return "doc.text.fill"
        case .plan: return "calendar.badge.clock"
        }
    }
}
