//
//  LibraryView.swift
//  AmakaFlow
//
//  AMA-2004: saved-content Library tab.
//

import SwiftUI

struct LibraryView: View {
    @StateObject private var viewModel: LibraryViewModel
    @State private var addDestination: LibraryAddDestination?

    init(viewModel: LibraryViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? LibraryViewModel())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

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
            // AMA-2292: Proto FAB — one tap from Library root to create.
            .overlay(alignment: .bottomTrailing) {
                libraryCreateFAB
            }
        }
        .overlay(alignment: .top) {
            if let error = viewModel.ctaError {
                ErrorToast(
                    actionTitle: "Couldn't load Library",
                    error: error,
                    onRetry: error.isRetryable ? { Task { await viewModel.retryLastAction() } } : nil,
                    onReport: { viewModel.reportError() },
                    onDismiss: { viewModel.dismissError() }
                )
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
            }
        }
        .sheet(item: $addDestination) { destination in
            switch destination {
            case .knowledge:
                AddKnowledgeView(
                    onSocialURLDetected: { url in
                        let next: LibraryAddDestination = .socialImport(
                            url: SocialImportPlatform.normalizeForIngest(url),
                            platform: SocialImportPlatform.detect(from: url)
                        )
                        // Dismiss knowledge sheet first so social import can present cleanly.
                        addDestination = nil
                        DispatchQueue.main.async {
                            addDestination = next
                        }
                    },
                    onSaved: {
                        Task { await viewModel.load() }
                    }
                )
            case .socialImport(let url, let platform):
                SocialImportFlowView(
                    mode: .url(platformHint: platform),
                    initialURL: url
                ) {
                    Task { await viewModel.load() }
                }
            }
        }
        .task {
            await viewModel.load()
        }
        .accessibilityIdentifier("library_screen")
    }

    private var libraryCreateFAB: some View {
        Button {
            presentAddSheet()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(Theme.Colors.primaryForeground)
                .frame(width: 56, height: 56)
                .background(Theme.Colors.readyHigh)
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.trailing, Theme.Spacing.lg)
        .padding(.bottom, 108)
        .accessibilityLabel("Create library entry")
        .accessibilityIdentifier("af_library_fab")
    }

    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .tint(Theme.Colors.textPrimary)
            Text("Loading your Library")
                .afMuted()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("library_loading")
    }

    private var contentView: some View {
        scrollContainer {
            filterSection
            itemList
        }
    }

    private var emptyView: some View {
        scrollContainer {
            if viewModel.hasActiveFilters {
                filterSection
            }
            LibraryEmptyStateView(
                clearFilters: viewModel.hasActiveFilters ? { viewModel.clearFilters() } : nil,
                pasteLink: { presentAddSheet() }
            )
        }
    }

    private var loadErrorView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            topBar

            Spacer()

            AFCard {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundColor(Theme.Colors.accentRed)
                    Text("We couldn't load your Library.")
                        .afH2()
                        .multilineTextAlignment(.center)
                    Text("Retry when you’re back online. Saved items stay unchanged.")
                        .afMuted()
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
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Theme.Spacing.lg)

            Spacer()
        }
    }

    @ViewBuilder
    private func scrollContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                topBar
                    .padding(.horizontal, -Theme.Spacing.lg)

                content()
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, 100)
        }
        .refreshable {
            await viewModel.load()
        }
    }

    private var topBar: some View {
        AFTopBar(
            title: "Library",
            subtitle: viewModel.savedSubtitle,
            left: { EmptyView() },
            right: { topBarActions }
        )
    }

    private var topBarActions: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Theme.Colors.textSecondary)
                .accessibilityHidden(true)

            Button {
                presentAddSheet()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Theme.Colors.chipBackground)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add to Library")
            .accessibilityIdentifier("af_library_add")
        }
    }

    private func presentAddSheet() {
        // AMA-2297: IG/TikTok/YouTube clipboard → SocialImportFlowView, never knowledge bookmark.
        addDestination = LibraryPasteRouter.destination()
    }

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            kindChips
            if !viewModel.availableTags.isEmpty {
                tagChips
            }
        }
    }

    private var kindChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                filterChip(
                    title: "All",
                    selected: viewModel.selectedKinds.isEmpty,
                    identifier: "af_library_kind_all"
                ) {
                    viewModel.clearKindFilters()
                }

                ForEach(LibraryViewModel.displayKinds, id: \.self) { kind in
                    filterChip(
                        title: LibraryViewModel.kindLabel(kind),
                        selected: viewModel.isKindSelected(kind),
                        identifier: "af_library_kind_\(kind.rawValue)"
                    ) {
                        viewModel.toggleKind(kind)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var tagChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                filterChip(
                    title: "All tags",
                    selected: viewModel.selectedTag == nil,
                    identifier: "af_library_tag_all"
                ) {
                    viewModel.selectTag(nil)
                }

                ForEach(viewModel.availableTags, id: \.self) { tag in
                    filterChip(
                        title: tag,
                        selected: viewModel.isTagSelected(tag),
                        identifier: "af_library_tag_\(tag)"
                    ) {
                        viewModel.selectTag(tag)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func filterChip(
        title: String,
        selected: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.footnote.weight(.semibold))
                .foregroundColor(selected ? Theme.Colors.primaryForeground : Theme.Colors.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(selected ? Theme.Colors.primary : Theme.Colors.chipBackground)
                .overlay(
                    Capsule().stroke(selected ? Color.clear : Theme.Colors.borderLight, lineWidth: 1)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var itemList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            AFLabel(text: "Saved Content")
                .accessibilityAddTraits(.isHeader)

            LazyVStack(spacing: Theme.Spacing.md) {
                ForEach(viewModel.entries) { entry in
                    NavigationLink(value: entry.destination) {
                        LibraryEntryCard(entry: entry)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("af_library_item_\(entry.id)")
                }
            }
        }
    }

    @ViewBuilder
    private func libraryDestinationView(_ destination: LibraryDestination) -> some View {
        switch destination {
        case .unifiedWorkout(let workoutID):
            if let workout = viewModel.resolveWorkout(for: destination) {
                UnifiedWorkoutDetailView(workout: workout) {
                    await viewModel.load()
                    return viewModel.workout(for: workoutID)
                        ?? viewModel.resolveWorkout(for: destination)
                }
            } else {
                // Honest fallback if workout vanished mid-nav.
                Text("Workout unavailable")
                    .afMuted()
                    .accessibilityIdentifier("af_workout_detail_missing_\(workoutID)")
            }
        case .knowledgeDetail(let itemID):
            LibraryDetailView(itemID: itemID)
        }
    }

    private var loadError: CTAError? {
        if case .error(let error) = viewModel.state {
            return error
        }
        return viewModel.ctaError
    }
}

private struct LibraryEntryCard: View {
    let entry: LibraryListEntry

    var body: some View {
        switch entry {
        case .workout(let workout):
            LibraryItemCard(
                kindLabel: "Workout",
                kindIcon: LibraryViewModel.kindIcon(.workout),
                title: workout.name,
                sourceCaption: WorkoutSourceProvenance.badge(for: workout.source.rawValue)?.label
                    ?? "Workout",
                tags: provenanceTags(for: workout),
                placeholderColor: Theme.Colors.readyHigh
            )
        case .knowledge(let item):
            LibraryItemCard(
                kindLabel: LibraryViewModel.kindSingularLabel(item.kind),
                kindIcon: LibraryViewModel.kindIcon(item.kind),
                title: item.title,
                sourceCaption: knowledgeSourceCaption(item),
                tags: item.tags ?? [],
                placeholderColor: knowledgeColor(item.kind)
            )
        }
    }

    private func provenanceTags(for workout: Workout) -> [String] {
        if let badge = WorkoutSourceProvenance.badge(for: workout.source.rawValue) {
            return [badge.label]
        }
        return []
    }

    private func knowledgeSourceCaption(_ item: LibraryViewModel.LibraryItem) -> String {
        guard let sourceDomain = item.sourceDomain?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sourceDomain.isEmpty else {
            return LibraryViewModel.kindSingularLabel(item.kind)
        }
        return sourceDomain
    }

    private func knowledgeColor(_ kind: LibraryViewModel.LibraryKind) -> Color {
        switch kind {
        case .workout: return Theme.Colors.readyHigh
        case .video: return Theme.Colors.accentBlue
        case .article: return Theme.Colors.accentOrange
        case .plan: return Theme.Colors.readyModerate
        }
    }
}

private struct LibraryItemCard: View {
    let kindLabel: String
    let kindIcon: String
    let title: String
    let sourceCaption: String
    let tags: [String]
    let placeholderColor: Color

    var body: some View {
        AFCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                placeholder
                    .aspectRatio(16 / 9, contentMode: .fit)

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                        AFChip(text: kindLabel, outline: true)
                        Spacer()
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Theme.Colors.textTertiary)
                            .accessibilityHidden(true)
                    }

                    Text(title)
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(2)

                    Text(sourceCaption)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)

                    if !tags.isEmpty {
                        FlowPills(tags: tags)
                    }
                }
                .padding(Theme.Spacing.md)
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [placeholderColor.opacity(0.95), placeholderColor.opacity(0.40)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: kindIcon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(Theme.Colors.primaryForeground.opacity(0.92))
        }
        .accessibilityLabel("\(kindLabel) placeholder")
    }
}

private struct FlowPills: View {
    let tags: [String]

    var body: some View {
        // Keep the first row compact for v1; detailed tag browsing follows in AMA-2005/2006.
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(tags.prefix(3), id: \.self) { tag in
                Text(tag)
                    .font(Theme.Typography.label)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.Colors.chipBackground)
                    .clipShape(Capsule())
            }
            if tags.count > 3 {
                Text("+\(tags.count - 3)")
                    .font(Theme.Typography.label)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
    }
}

private struct LibraryEmptyStateView: View {
    let clearFilters: (() -> Void)?
    let pasteLink: () -> Void

    var body: some View {
        AFCard {
            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "bookmark.badge.plus")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(Theme.Colors.readyHigh)
                Text(LibraryCopy.emptyTitle)
                    .afH2()
                    .multilineTextAlignment(.center)
                Text(LibraryCopy.emptySubtitle)
                    .afMuted()
                    .multilineTextAlignment(.center)

                Button(action: pasteLink) {
                    Text(LibraryCopy.pasteLink)
                }
                .buttonStyle(AFPrimaryButtonStyle(size: .md))
                .accessibilityIdentifier("af_library_empty_paste")

                if let clearFilters {
                    Button("Clear filters", action: clearFilters)
                        .buttonStyle(AFGhostButtonStyle(size: .sm, isWide: false))
                        .accessibilityIdentifier("af_library_clear_filters")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("library_empty_state")
    }
}
#if DEBUG
#Preview("Library") {
    LibraryView(viewModel: LibraryViewModel(apiService: FixtureAPIService()))
}
#endif
