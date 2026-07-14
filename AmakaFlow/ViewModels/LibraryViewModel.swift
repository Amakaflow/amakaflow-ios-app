//
//  LibraryViewModel.swift
//  AmakaFlow
//
//  AMA-2004: saved-content Library tab state + filters.
//  AMA-2291: merge saved workouts into Library; route workouts to unified detail.
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

    init(apiService: APIServiceProviding? = nil) {
        self.apiService = apiService ?? AppDependencies.current.apiService
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
            let workouts: [Workout]
            do {
                workouts = try await workoutsTask
            } catch {
                // Knowledge still usable if workout fetch fails — surface toast, keep going.
                ctaError = CTAError.map(error)
                lastFailedAction = .load
                workouts = allWorkouts
            }

            allItems = response.items ?? []
            allWorkouts = workouts
            workoutsByID = Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0) })
            applyFilters()
        } catch {
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
        case .none:
            break
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

        if lastFailedAction == .load, let currentError, allItems.isEmpty, allWorkouts.isEmpty {
            state = .error(currentError)
        }
    }

    func reportError(reporter: ErrorReporting? = nil) {
        guard let ctaError else { return }
        let reporter = reporter ?? ErrorReporter.shared
        reporter.report(
            action: "library_items_load",
            error: ctaError,
            endpoint: "/v1/library/items",
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
