//
//  LibraryViewModel.swift
//  AmakaFlow
//
//  AMA-2004: saved-content Library tab state + filters.
//  AMA-2291: merge saved workouts into Library; route workouts to unified detail.
//  AMA-2298: delete knowledge + workout Library imports (optimistic, recoverable).
//

import Combine
import Foundation

@MainActor
final class LibraryViewModel: ObservableObject {
    typealias LibraryItem = Components.Schemas.LibraryItem
    typealias LibraryKind = Components.Schemas.LibraryKind
    typealias LibraryItemList = Components.Schemas.LibraryItemList

    enum ScreenState: Equatable {
        case loading
        case content
        case empty
        case error(CTAError)
    }

    enum FailedAction: Equatable {
        case load
        case delete(LibraryListEntry)
    }

    @Published private(set) var state: ScreenState = .loading
    /// Knowledge cards only — retained for existing filters/tests.
    @Published private(set) var items: [LibraryItem] = []
    /// AMA-2291 unified Library rows (workouts + non-workout knowledge).
    @Published private(set) var entries: [LibraryListEntry] = []
    @Published private(set) var ctaError: CTAError?
    @Published private(set) var selectedKinds: Set<LibraryKind> = []
    @Published private(set) var selectedTag: String?
    private(set) var lastFailedAction: FailedAction?
    private(set) var workoutsByID: [String: Workout] = [:]

    private let apiService: APIServiceProviding
    private var allItems: [LibraryItem] = []
    private var allWorkouts: [Workout] = []
    /// Serializes delete so a second tap cannot race the optimistic restore path.
    private var isDeleting = false
    /// Bumped when a delete starts so in-flight `load()` results are dropped.
    private var contentEpoch = 0

    init(apiService: APIServiceProviding? = nil) {
        self.apiService = apiService ?? AppDependencies.current.apiService
    }

    /// Toast title for the current recoverable error (load vs delete).
    var errorToastTitle: String {
        switch lastFailedAction {
        case .delete:
            return "Couldn't delete Library item"
        case .load, .none:
            return "Couldn't load Library"
        }
    }

    var savedSubtitle: String {
        switch state {
        case .loading:
            return "Loading saved ideas"
        case .error:
            return "Unable to load"
        default:
            let total = entries.count
            return total == 1 ? "1 saved item" : "\(total) saved items"
        }
    }

    var availableTags: [String] {
        let knowledgeTags = allItems.flatMap { $0.tags ?? [] }
        let workoutTags = allWorkouts.compactMap { workout -> [String] in
            if let badge = WorkoutSourceProvenance.badge(for: workout.source.rawValue) {
                return [badge.label.lowercased()]
            }
            return []
        }.flatMap { $0 }
        let tags = (knowledgeTags + workoutTags).compactMap(Self.normalizedTag)
        return Array(Set(tags)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var hasActiveFilters: Bool {
        !selectedKinds.isEmpty || selectedTag != nil
    }

    func workout(for id: String) -> Workout? {
        workoutsByID[id]
    }

    /// Resolve a Library destination to a concrete Workout (synthetic when knowledge-only).
    func resolveWorkout(for destination: LibraryDestination) -> Workout? {
        switch destination {
        case .unifiedWorkout(let workoutID):
            if let existing = workoutsByID[workoutID] {
                return existing
            }
            if let knowledge = allItems.first(where: { $0.id == workoutID }) {
                return Self.syntheticWorkout(from: knowledge)
            }
            return nil
        case .knowledgeDetail:
            return nil
        }
    }

    func load() async {
        // Avoid stomping an in-flight optimistic delete.
        guard !isDeleting else { return }

        let epoch = contentEpoch
        let hadContent = !allItems.isEmpty || !allWorkouts.isEmpty
        if !hadContent { state = .loading }
        ctaError = nil
        lastFailedAction = nil

        do {
            // AMA-2004: fetch knowledge cards for multi-kind client filtering.
            // AMA-2291: also fetch saved workouts (social/manual/coach) for unified detail.
            async let knowledgeTask = apiService.listLibraryItems(kind: nil, tag: nil)
            async let workoutsTask = apiService.fetchWorkouts(isRetry: false)

            let response = try await knowledgeTask
            guard epoch == contentEpoch, !isDeleting else { return }

            let workouts: [Workout]
            do {
                workouts = try await workoutsTask
            } catch {
                guard epoch == contentEpoch, !isDeleting else { return }
                // Knowledge still usable if workout fetch fails — surface toast, keep going.
                ctaError = CTAError.map(error)
                lastFailedAction = .load
                workouts = allWorkouts
            }

            guard epoch == contentEpoch, !isDeleting else { return }
            allItems = response.items ?? []
            allWorkouts = WorkoutLibraryDetailStore.enrichCollection(workouts)
            workoutsByID = Dictionary(uniqueKeysWithValues: allWorkouts.map { ($0.id, $0) })
            applyFilters()
        } catch {
            guard epoch == contentEpoch, !isDeleting else { return }
            let mapped = CTAError.map(error)
            ctaError = mapped
            if !hadContent { state = .error(mapped) }
            lastFailedAction = .load
        }
    }

    func retryLastAction() async {
        switch lastFailedAction {
        case .load:
            await load()
        case .delete(let entry):
            await deleteEntry(entry)
        case .none:
            break
        }
    }

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
            if let urlError = error as? URLError, urlError.code == .cancelled {
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

    private func applyFilters() {
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

    private static func normalizedTag(_ tag: String) -> String? {
        let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func tagsEqual(_ lhs: String, _ rhs: String) -> Bool {
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

enum LibraryCopy {
    static let emptyTitle = "Save workouts and ideas as you find them"
    static let emptySubtitle = "Paste a link to save workouts, videos, articles, and plans. Saved items from your coach and imports will appear here too."
    static let pasteLink = "Paste a link"
}
