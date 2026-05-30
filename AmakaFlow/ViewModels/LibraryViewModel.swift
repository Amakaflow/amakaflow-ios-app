//
//  LibraryViewModel.swift
//  AmakaFlow
//
//  AMA-2004: saved-content Library tab state + filters.
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
    @Published private(set) var items: [LibraryItem] = []
    @Published private(set) var ctaError: CTAError?
    @Published private(set) var selectedKinds: Set<LibraryKind> = []
    @Published private(set) var selectedTag: String?
    private(set) var lastFailedAction: FailedAction?

    private let apiService: APIServiceProviding
    private var allItems: [LibraryItem] = []

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
            let total = allItems.count
            return total == 1 ? "1 saved item" : "\(total) saved items"
        }
    }

    var availableTags: [String] {
        let tags = allItems.flatMap { $0.tags ?? [] }
            .compactMap(Self.normalizedTag)
        return Array(Set(tags)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var hasActiveFilters: Bool {
        !selectedKinds.isEmpty || selectedTag != nil
    }

    func load() async {
        state = .loading
        ctaError = nil
        lastFailedAction = nil

        do {
            // AMA-2004: fetch all and apply the design's multi-kind filters client-side.
            // The API accepts a single kind, but this list is intentionally small.
            let response = try await apiService.listLibraryItems(kind: nil, tag: nil)
            allItems = response.items ?? []
            applyFilters()
        } catch {
            let mapped = CTAError.map(error)
            ctaError = mapped
            state = .error(mapped)
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

        if lastFailedAction == .load, let currentError {
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
        state = items.isEmpty ? .empty : .content
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
    static let emptySubtitle = "Paste a link when Add to Library lands. Until then, saved items from your coach and imports will appear here."
    static let pasteLink = "Paste a link"
}
