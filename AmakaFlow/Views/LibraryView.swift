//
//  LibraryView.swift
//  AmakaFlow
//
//  AMA-2004: saved-content Library tab.
//  Daily Driver: DDBuildScreen — search, source pills, unified provenance rows.
//  AMA-2298: swipe / context / detail delete with confirmation.
//

import SwiftUI

struct LibraryView: View {
    @StateObject var viewModel: LibraryViewModel
    @Environment(\.openCreateSheet) private var openCreateSheet
    @State private var searchText = ""
    @State private var sourceFilter: DDPlatform = .all
    @State private var pendingDelete: LibraryListEntry?
    @State var navigationPath: [LibraryDestination] = []
    @StateObject private var watchesVM = OnYourWatchesViewModel()
    @State var isPresentingNewCollection = false
    @State var newCollectionName = ""
    @State var collectionsAlertMessage: String?
    /// Gates content/empty `.task` so state flips don't double-refresh watches.
    @State private var watchesDidInitialRefresh = false
    /// AMA-2375: Garmin Fix opens the editor directly (not detail → Edit).
    @State private var garminFixWorkoutID: String?

    init(viewModel: LibraryViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? LibraryViewModel())
    }

    private func refreshWatches(force: Bool = false) async {
        if !force {
            guard !watchesDidInitialRefresh else { return }
            watchesDidInitialRefresh = true
        }
        await watchesVM.refresh()
    }

    private var filteredEntries: [LibraryListEntry] {
        viewModel.entries.filter { entry in
            let matchesSource: Bool
            let title: String
            let creator: String

            switch entry {
            case .workout(let workout):
                matchesSource = sourceFilter.matches(workout: workout)
                title = workout.name
                creator = DDLibraryPresentation.creatorLabel(for: workout)
            case .knowledge(let item):
                matchesSource = sourceFilter.matches(knowledge: item)
                title = item.title
                creator = item.sourceDomain ?? ""
            }

            guard matchesSource else { return false }
            return DDLibraryPresentation.matchesSearch(searchText, title: title, creator: creator)
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                DailyDriver.screenBackground.ignoresSafeArea()

                Group {
                    switch viewModel.state {
                    case .loading:
                        loadingView
                    case .content:
                        contentView
                    case .empty:
                        emptyView
                    case .error:
                        loadErrorView
                    }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: LibraryDestination.self) { destination in
                libraryDestinationView(destination)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(
            isPresented: Binding(
                get: { garminFixWorkoutID != nil },
                set: { if !$0 { garminFixWorkoutID = nil } }
            ),
            onDismiss: {
                Task { await viewModel.load() }
            },
            content: {
                if let workoutID = garminFixWorkoutID,
                   let workout = viewModel.workout(for: workoutID)
                    ?? viewModel.resolveWorkout(for: .unifiedWorkout(workoutID: workoutID)) {
                    WorkoutEditorView(workout: workout)
                        .accessibilityIdentifier("af_garmin_queue_fix_editor")
                } else {
                    Text("Workout unavailable")
                        .font(Theme.Typography.caption)
                        .foregroundColor(DailyDriver.foregroundMuted)
                        .accessibilityIdentifier("af_garmin_queue_fix_editor_missing")
                }
            }
        )
        .overlay(alignment: .top) {
            if let error = viewModel.ctaError {
                ErrorToast(
                    actionTitle: viewModel.errorToastTitle,
                    error: error,
                    onRetry: error.isRetryable ? {
                        Task {
                            // Capture before retry clears `lastFailedAction`.
                            let failedDestination: LibraryDestination?
                            if case .delete(let entry) = viewModel.lastFailedAction {
                                failedDestination = entry.destination
                            } else {
                                failedDestination = nil
                            }
                            let deleted = await viewModel.retryLastAction()
                            // Only pop if the visible detail still belongs to that entry.
                            if deleted, navigationPath.last == failedDestination {
                                navigationPath.removeLast()
                            }
                        }
                    } : nil,
                    onReport: { viewModel.reportError() },
                    onDismiss: { viewModel.dismissError() }
                )
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
            }
        }
        .alert(
            GarminLifecycleCopy.deleteWorkoutTitle,
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                guard let entry = pendingDelete else { return }
                pendingDelete = nil
                Task { await viewModel.deleteEntry(entry) }
            }
            .accessibilityIdentifier("af_library_delete_confirm")
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
            .accessibilityIdentifier("af_library_delete_cancel")
        } message: {
            if let pendingDelete {
                Text(
                    GarminLifecycleCopy.deleteWorkoutMessage(
                        name: pendingDelete.title,
                        isWorkout: pendingDelete.isWorkout
                    )
                )
            }
        }
        .task {
            await viewModel.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryContentDidChange)) { note in
            // Skip reload when this VM just deleted — entries already updated locally.
            if note.object as AnyObject? === viewModel { return }
            Task { await viewModel.load() }
        }
        .accessibilityIdentifier("library_screen")
    }
}

extension LibraryView {
    fileprivate func presentAddSheet() {
        openCreateSheet()
    }
}

extension LibraryView {
    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .tint(DailyDriver.foreground)
            Text("Loading your Library")
                .font(Theme.Typography.caption)
                .foregroundColor(DailyDriver.foregroundMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("library_loading")
    }

    private var contentView: some View {
        VStack(spacing: 0) {
            DDScreenHeader(title: "Library") {
                HStack(spacing: 10) {
                    if watchesVM.snapshot.hasAnyWearable {
                        LibraryWatchHeaderButton(badgeCount: watchesVM.snapshot.badgeCount) {
                            navigationPath.append(.onYourWatches)
                        }
                    }
                    DDLibraryHeaderAddButton(action: presentAddSheet)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DDSearchField(text: $searchText)
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                        .accessibilityIdentifier("af_library_search")

                    DDSourceFilterPills(selection: $sourceFilter)
                        .padding(.horizontal, 18)
                        .padding(.top, 10)

                    LibraryPinnedSection(
                        pinnedWorkouts: pinnedWorkouts,
                        onSelect: { workoutID in
                            navigationPath.append(.unifiedWorkout(workoutID: workoutID))
                        },
                        onUnpin: unpinWorkout
                    )
                    .padding(.horizontal, 18)
                    .padding(.top, 18)

                    LibraryCollectionsGrid(
                        items: viewModel.collectionsStore.gridModels(workoutsByID: viewModel.workoutsByID),
                        workoutsByID: viewModel.workoutsByID,
                        onSelectCollection: { collectionID in
                            navigationPath.append(.collection(id: collectionID))
                        },
                        onNewCollection: {
                            newCollectionName = ""
                            isPresentingNewCollection = true
                        }
                    )
                    .padding(.horizontal, 18)
                    .padding(.top, 22)

                    if watchesVM.snapshot.hasAnyWearable {
                        OnYourWatchesSummaryRow(summaryLine: watchesVM.snapshot.librarySummaryLine) {
                            navigationPath.append(.onYourWatches)
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 22)
                    }

                    if hasLocalFilters {
                        Text("Results")
                            .ddDisplayText(19, weight: .heavy)
                            .foregroundColor(DailyDriver.foreground)
                            .padding(.horizontal, 18)
                            .padding(.top, 22)
                            .accessibilityIdentifier("af_library_results")

                        if filteredEntries.isEmpty {
                            ddNoMatchesMessage
                                .padding(.horizontal, 18)
                                .padding(.top, 10)
                        } else {
                            itemList
                                .padding(.horizontal, 18)
                                .padding(.top, 10)
                        }
                    }
                }
                .padding(.bottom, 100)
            }
            .refreshable {
                await viewModel.load()
                await refreshWatches(force: true)
            }
        }
        .task {
            await refreshWatches()
        }
        .libraryNewCollectionAlert(
            isPresented: $isPresentingNewCollection,
            name: $newCollectionName,
            onCreate: createCollection
        )
        .libraryCollectionsFailureAlert(message: $collectionsAlertMessage)
    }

    private var emptyView: some View {
        VStack(spacing: 0) {
            DDScreenHeader(title: "Library") {
                HStack(spacing: 10) {
                    if watchesVM.snapshot.hasAnyWearable {
                        LibraryWatchHeaderButton(badgeCount: watchesVM.snapshot.badgeCount) {
                            navigationPath.append(.onYourWatches)
                        }
                    }
                    DDLibraryHeaderAddButton(action: presentAddSheet)
                }
            }

            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    if watchesVM.snapshot.hasAnyWearable {
                        OnYourWatchesSummaryRow(summaryLine: watchesVM.snapshot.librarySummaryLine) {
                            navigationPath.append(.onYourWatches)
                        }
                    }

                    if hasLocalFilters {
                        DDSearchField(text: $searchText)
                        DDSourceFilterPills(selection: $sourceFilter)
                    }

                    if hasLocalFilters && !filteredEntries.isEmpty {
                        itemList
                    } else if hasLocalFilters {
                        ddNoMatchesMessage
                    } else {
                        LibraryEmptyStateView(clearFilters: nil) {
                            presentAddSheet()
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 100)
            }
            .task {
                await refreshWatches()
            }
        }
    }

    private var hasLocalFilters: Bool {
        !searchText.isEmpty || sourceFilter != .all
    }

    private var ddNoMatchesMessage: some View {
        Text("Nothing matches — clear the filter or import something new with ＋")
            .font(Theme.Typography.caption)
            .foregroundColor(DailyDriver.foregroundDim)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
    }

    private var loadErrorView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            DDScreenHeader(title: "Library")

            Spacer()

            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(DailyDriver.coral)
                Text("We couldn't load your Library.")
                    .ddDisplayText(18, weight: .bold)
                    .multilineTextAlignment(.center)
                Text("Retry when you’re back online. Saved items stay unchanged.")
                    .font(Theme.Typography.caption)
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .multilineTextAlignment(.center)
                if loadError?.isRetryable == true {
                    Button {
                        Task { await viewModel.load() }
                    } label: {
                        Text("Retry")
                    }
                    .buttonStyle(AFPrimaryButtonStyle(size: .md))
                    .accessibilityIdentifier("library_retry_load")
                }
            }
            .padding(Theme.Spacing.lg)
            .background(DailyDriver.card)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DailyDriver.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 18)

            Spacer()
        }
    }

    private var itemList: some View {
        LazyVStack(spacing: 9) {
            ForEach(filteredEntries) { entry in
                NavigationLink(value: entry.destination) {
                    ddRow(for: entry)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("af_library_item_\(entry.id)")
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDelete = entry
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .accessibilityIdentifier("af_library_delete_\(entry.id)")
                }
                .contextMenu {
                    Button(role: .destructive) {
                        pendingDelete = entry
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .accessibilityIdentifier("af_library_delete_\(entry.id)")
                }
            }

            if filteredEntries.isEmpty {
                ddNoMatchesMessage
            }
        }
    }

    @ViewBuilder
    private func ddRow(for entry: LibraryListEntry) -> some View {
        switch entry {
        case .workout(let workout):
            let row = DDLibraryPresentation.row(for: workout)
            DDLibraryRow(
                title: workout.name,
                metaLine: row.meta,
                platform: row.platform,
                thumbIcon: row.icon,
                gradientColors: row.gradient
            )
        case .knowledge(let item):
            let row = DDLibraryPresentation.row(for: item)
            DDLibraryRow(
                title: item.title,
                metaLine: row.meta,
                platform: row.platform,
                thumbIcon: row.icon,
                gradientColors: row.gradient
            )
        }
    }

    @ViewBuilder
    private func libraryDestinationView(_ destination: LibraryDestination) -> some View {
        switch destination {
        case .unifiedWorkout(let workoutID):
            if let workout = viewModel.resolveWorkout(for: destination) {
                UnifiedWorkoutDetailView(
                    workout: workout,
                    collectionsStore: viewModel.collectionsStore,
                    onEditorDismiss: {
                        await viewModel.load()
                        return viewModel.workout(for: workoutID)
                            ?? viewModel.resolveWorkout(for: destination)
                    },
                    onDelete: {
                        guard let target = viewModel.deleteTarget(forWorkoutID: workoutID) else {
                            return false
                        }
                        return await viewModel.deleteEntry(target)
                    }
                )
            } else {
                Text("Workout unavailable")
                    .font(Theme.Typography.caption)
                    .foregroundColor(DailyDriver.foregroundMuted)
                    .accessibilityIdentifier("af_workout_detail_missing_\(workoutID)")
            }
        case .knowledgeDetail(let itemID):
            LibraryDetailView(itemID: itemID) {
                guard let target = viewModel.deleteTarget(forKnowledgeID: itemID) else {
                    return false
                }
                return await viewModel.deleteEntry(target)
            }
        case .onYourWatches:
            OnYourWatchesView(viewModel: watchesVM)
        case .appleScheduled:
            AppleWatchScheduledListView {
                navigationPath.append(.libraryPick(.appleSchedule))
            }
        case .garminQueue:
            GarminWatchQueueView(
                onPushFromLibrary: {
                    navigationPath.append(.libraryPick(.garminPush))
                },
                onFix: { item in
                    garminFixWorkoutID = item.workoutID
                }
            )
        case .libraryPick(let target):
            WatchLibraryPickView(target: target) { workoutID in
                navigationPath.append(.unifiedWorkout(workoutID: workoutID))
            }
        case .collection(let collectionID):
            CollectionDetailView(
                collectionID: collectionID,
                collectionsStore: viewModel.collectionsStore,
                workoutsByID: viewModel.workoutsByID
            ) { workoutID in
                navigationPath.append(.unifiedWorkout(workoutID: workoutID))
            }
        }
    }

    private var loadError: CTAError? {
        if case .error(let error) = viewModel.state {
            return error
        }
        return viewModel.ctaError
    }
}
