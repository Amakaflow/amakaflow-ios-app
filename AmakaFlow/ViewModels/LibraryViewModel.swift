//
//  LibraryViewModel.swift
//  AmakaFlow
//
//  AMA-2004: saved-content Library tab state + filters.
//  AMA-2291: merge saved workouts into Library; route workouts to unified detail.
//  AMA-2298: delete knowledge + workout Library imports (optimistic, recoverable).
//  AMA-2297: suppress Library -999 cancelled errors on superseded reloads.
//

import Combine
import Foundation
import os.log

let libraryLogger = Logger(subsystem: "com.myamaka.AmakaFlowCompanion", category: "Library")

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

    @Published var state: ScreenState = .loading
    /// Knowledge cards only — retained for existing filters/tests.
    @Published var items: [LibraryItem] = []
    /// AMA-2291 unified Library rows (workouts + non-workout knowledge).
    @Published var entries: [LibraryListEntry] = []
    @Published var ctaError: CTAError?
    @Published var selectedKinds: Set<LibraryKind> = []
    @Published var selectedTag: String?
    var lastFailedAction: FailedAction?
    var workoutsByID: [String: Workout] = [:]

    let apiService: APIServiceProviding
    /// AMA-2376: local-first collections/pins state; pruned to known workout IDs
    /// after every load and workout delete so stale memberships never linger.
    let collectionsStore: LibraryCollectionsStore
    var allItems: [LibraryItem] = []
    var allWorkouts: [Workout] = []
    /// Serializes delete so a second tap cannot race the optimistic restore path.
    var isDeleting = false
    /// Bumped when a delete starts so in-flight `load()` results are dropped.
    var contentEpoch = 0
    /// Bumps on each load(); stale completions ignore cancelled superseded requests.
    var loadGeneration = 0
    private var cancellables = Set<AnyCancellable>()

    init(apiService: APIServiceProviding? = nil, collectionsStore: LibraryCollectionsStore? = nil) {
        self.apiService = apiService ?? AppDependencies.current.apiService
        let resolvedCollectionsStore = collectionsStore ?? LibraryCollectionsStore()
        self.collectionsStore = resolvedCollectionsStore
        // AMA-2376: LibraryView reads `collectionsStore` off this view model rather than
        // observing it directly, so its @Published changes (pin/unpin, membership edits)
        // never trigger a re-render unless forwarded through our own objectWillChange.
        // Capture the publisher (not `[weak self]`) so the relay stays live for the
        // VM lifetime — weak self inside init-created sinks can miss early publishes.
        let viewModelWillChange = objectWillChange
        resolvedCollectionsStore.objectWillChange
            .sink { _ in
                viewModelWillChange.send()
            }
            .store(in: &cancellables)
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
        case .knowledgeDetail, .onYourWatches, .appleScheduled, .garminQueue, .libraryPick, .collection:
            return nil
        }
    }

    func load() async {
        // Avoid stomping an in-flight optimistic delete.
        guard !isDeleting else { return }

        loadGeneration += 1
        let generation = loadGeneration
        let epoch = contentEpoch
        let hadContent = !allItems.isEmpty || !allWorkouts.isEmpty
        if !hadContent { state = .loading }
        ctaError = nil
        lastFailedAction = nil

        func isStale() -> Bool {
            generation != loadGeneration || epoch != contentEpoch || isDeleting
        }

        do {
            // AMA-2004: fetch knowledge cards for multi-kind client filtering.
            // AMA-2291: also fetch saved workouts (social/manual/coach) for unified detail.
            async let knowledgeTask = apiService.listLibraryItems(kind: nil, tag: nil)
            async let workoutsTask = apiService.fetchWorkouts(isRetry: false)

            let response = try await knowledgeTask
            guard !isStale() else {
                logSuppressedLoad(reason: "stale_after_listLibraryItems", generation: generation)
                return
            }

            let workouts: [Workout]
            do {
                workouts = try await workoutsTask
            } catch {
                guard !isStale() else {
                    logSuppressedLoad(reason: "stale_after_fetchWorkouts", generation: generation)
                    return
                }
                workouts = workoutsAfterFetchFailure(error, generation: generation)
            }

            guard !isStale() else {
                logSuppressedLoad(reason: "stale_before_apply", generation: generation)
                return
            }
            allItems = response.items ?? []
            allWorkouts = WorkoutLibraryDetailStore.enrichCollection(workouts)
            workoutsByID = Dictionary(uniqueKeysWithValues: allWorkouts.map { ($0.id, $0) })
            syncCollectionsAfterLoad()
            applyFilters()
        } catch {
            guard !isStale() else {
                logSuppressedLoad(reason: "stale_listLibraryItems_error", generation: generation)
                return
            }
            if CTAError.isCancellation(error) {
                logSuppressedLoad(
                    reason: "listLibraryItems_cancelled",
                    generation: generation,
                    error: error
                )
                return
            }
            let mapped = CTAError.map(error)
            ctaError = mapped
            if !hadContent { state = .error(mapped) }
            lastFailedAction = .load
        }
    }

    /// - Returns: `true` when a delete retry removed the entry (detail should dismiss).
    @discardableResult
    func retryLastAction() async -> Bool {
        switch lastFailedAction {
        case .load:
            await load()
            return false
        case .delete(let entry):
            return await deleteEntry(entry)
        case .none:
            return false
        }
    }

    /// AMA-2376: IDs that may own collection membership / pins — saved workouts
    /// plus workout-kind knowledge cards (synthetic unified-detail destinations).
    /// Video/article/plan knowledge IDs are excluded (`knowledgeDetail` only).
    var knownCollectionWorkoutIDs: Set<String> {
        var ids = Set(allWorkouts.map(\.id))
        for item in allItems where item.kind == .workout {
            ids.insert(item.id)
        }
        return ids
    }

    /// AMA-2376: refresh collections; skip orphan wipe when known set is empty.
    func syncCollectionsAfterLoad() {
        let knownWorkoutIDs = knownCollectionWorkoutIDs
        if knownWorkoutIDs.isEmpty {
            try? collectionsStore.reload()
        } else {
            try? collectionsStore.pruneOrphans(knownWorkoutIds: knownWorkoutIDs)
        }
    }

    func workoutsAfterFetchFailure(_ error: Error, generation: Int) -> [Workout] {
        if CTAError.isCancellation(error) {
            logSuppressedLoad(
                reason: "fetchWorkouts_cancelled",
                generation: generation,
                error: error
            )
        } else {
            ctaError = CTAError.map(error)
            lastFailedAction = .load
        }
        return allWorkouts
    }
}

enum LibraryCopy {
    static let emptyTitle = "Save workouts and ideas as you find them"
    static let emptySubtitle = "Paste a link to save workouts, videos, articles, and plans. Saved items from your coach and imports will appear here too."
    static let pasteLink = "Paste a link"
}
