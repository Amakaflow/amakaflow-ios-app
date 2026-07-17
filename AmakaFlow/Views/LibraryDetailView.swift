//
//  LibraryDetailView.swift
//  AmakaFlow
//
//  AMA-2005: saved-content Library detail screen.
//  AMA-2298: Delete knowledge Library imports with confirmation.
//

import SwiftUI

struct LibraryDetailView: View {
    let itemID: String
    @StateObject private var viewModel: LibraryDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var loadedItemID: String?
    @State private var showingDeleteConfirm = false
    @State private var isDeleting = false
    /// AMA-2298: delete saved knowledge import; return `true` to dismiss.
    var onDelete: (() async -> Bool)?

    init(
        itemID: String,
        viewModel: LibraryDetailViewModel? = nil,
        onDelete: (() async -> Bool)? = nil
    ) {
        self.itemID = itemID
        self.onDelete = onDelete
        _viewModel = StateObject(wrappedValue: viewModel ?? LibraryDetailViewModel())
    }

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            Group {
                switch viewModel.state {
                case .loading:
                    loadingView
                case .content:
                    if let item = viewModel.item {
                        contentView(item)
                    } else {
                        emptyView
                    }
                case .empty:
                    emptyView
                case .error:
                    errorView
                }
            }
        }
        .navigationBarHidden(true)
        .overlay(alignment: .top) {
            if let error = viewModel.ctaError {
                ErrorToast(
                    actionTitle: "Couldn't load Library item",
                    error: error,
                    onRetry: error.isRetryable ? { Task { await viewModel.retryLastAction() } } : nil,
                    onReport: { viewModel.reportError() },
                    onDismiss: { viewModel.dismissError() }
                )
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
            }
        }
        .alert("Delete from Library?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Task {
                    guard let onDelete else { return }
                    isDeleting = true
                    let deleted = await onDelete()
                    isDeleting = false
                    if deleted {
                        dismiss()
                    }
                }
            }
            .accessibilityIdentifier("af_library_delete_confirm")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("af_library_delete_cancel")
        } message: {
            Text("“\(viewModel.item?.title ?? "This item")” will be removed. You can import it again later.")
        }
        .task(id: itemID) {
            guard loadedItemID != itemID else { return }
            loadedItemID = itemID
            await viewModel.load(id: itemID)
        }
        .accessibilityIdentifier("library_detail_screen")
    }

    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
                .tint(Theme.Colors.textPrimary)
            Text("Loading saved item")
                .afMuted()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("library_detail_loading")
    }

    private func contentView(_ item: LibraryDetailViewModel.LibraryItemDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                topBar
                    .padding(.horizontal, -Theme.Spacing.lg)

                hero(for: item)
                header(for: item)
                bodySection(for: item)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, 100)
        }
    }

    private var emptyView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            topBar

            Spacer()

            AFCard {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "text.badge.xmark")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(Theme.Colors.textTertiary)
                    Text("Nothing to preview yet")
                        .afH2()
                        .multilineTextAlignment(.center)
                    Text("This saved item has no summary or takeaways yet. Structured workouts, plans, and notes are coming later.")
                        .afMuted()
                        .multilineTextAlignment(.center)

                    if let item = viewModel.item, let url = viewModel.sourceURL {
                        Button {
                            openURL(url)
                        } label: {
                            Text(LibraryDetailViewModel.openButtonTitle(for: item.kind))
                        }
                        .buttonStyle(AFPrimaryButtonStyle(size: .md))
                        .accessibilityIdentifier("af_library_detail_open")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Theme.Spacing.lg)

            Spacer()
        }
    }

    private var errorView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            topBar

            Spacer()

            AFCard {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundColor(Theme.Colors.accentRed)
                    Text("We couldn't load this item.")
                        .afH2()
                        .multilineTextAlignment(.center)
                    Text("Retry when you’re back online. Your saved Library stays unchanged.")
                        .afMuted()
                        .multilineTextAlignment(.center)
                    if loadError?.isRetryable == true {
                        Button {
                            Task { await viewModel.retryLastAction() }
                        } label: {
                            Text("Retry")
                        }
                        .buttonStyle(AFPrimaryButtonStyle(size: .md))
                        .accessibilityIdentifier("library_detail_retry_load")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Theme.Spacing.lg)

            Spacer()
        }
    }

    private var topBar: some View {
        AFTopBar(
            title: "Library",
            subtitle: viewModel.sourceCaption,
            backIdentifier: "af_library_detail_back",
            backAction: { dismiss() },
            right: {
                if onDelete != nil {
                    Button {
                        showingDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Theme.Colors.accentRed)
                    }
                    .buttonStyle(.plain)
                    .disabled(isDeleting)
                    .accessibilityLabel("Delete")
                    .accessibilityIdentifier("af_library_detail_delete")
                }
            }
        )
    }

    private func hero(for item: LibraryDetailViewModel.LibraryItemDetail) -> some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [placeholderColor(for: item.kind).opacity(0.95), placeholderColor(for: item.kind).opacity(0.40)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: LibraryViewModel.kindIcon(item.kind))
                .font(.system(size: 44, weight: .semibold))
                .foregroundColor(Theme.Colors.primaryForeground.opacity(0.92))
            AFChip(text: LibraryViewModel.kindSingularLabel(item.kind), outline: false)
                .padding(Theme.Spacing.md)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous)
                .stroke(Theme.Colors.borderLight, lineWidth: 1)
        )
        .accessibilityLabel("\(LibraryViewModel.kindSingularLabel(item.kind)) placeholder")
    }

    private func header(for item: LibraryDetailViewModel.LibraryItemDetail) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(item.title)
                .font(Theme.Typography.title1)
                .foregroundColor(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("af_library_detail_title")

            Text(viewModel.sourceCaption)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)

            if !viewModel.tags.isEmpty {
                DetailTagPills(tags: viewModel.tags)
            }

            if let url = viewModel.sourceURL {
                Button {
                    openURL(url)
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(LibraryDetailViewModel.openButtonTitle(for: item.kind))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .buttonStyle(AFPrimaryButtonStyle(size: .md, isWide: false))
                .padding(.top, Theme.Spacing.xs)
                .accessibilityIdentifier("af_library_detail_open")
            }
        }
    }

    private func bodySection(for item: LibraryDetailViewModel.LibraryItemDetail) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if let previewMessage = LibraryDetailViewModel.previewOnlyMessage(for: item.kind) {
                previewOnlyCard(message: previewMessage)
            }

            if item.kind == .video {
                videoOpenCard
            }

            if let summary = viewModel.summaryText {
                detailCard(title: summaryTitle(for: item.kind), systemImage: "text.alignleft") {
                    Text(summary)
                        .afBody()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !viewModel.takeaways.isEmpty {
                detailCard(title: "Key takeaways", systemImage: "checkmark.seal.fill") {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        ForEach(viewModel.takeaways, id: \.self) { takeaway in
                            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                                Circle()
                                    .fill(Theme.Colors.readyHigh)
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 8)
                                Text(takeaway)
                                    .afBody()
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }

            notesDeferredCard
        }
    }

    private var videoOpenCard: some View {
        AFCard {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Theme.Colors.accentBlue)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Video source")
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("Open the saved YouTube link in your browser. Embedded playback is deferred for v1.1.")
                        .afMuted()
                }
            }
        }
    }

    private func previewOnlyCard(message: String) -> some View {
        AFCard {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Theme.Colors.accentOrange)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(message)
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("Sets, reps, weeks, and use/start actions are not available in the current Library contract.")
                        .afMuted()
                }
            }
        }
    }

    private var notesDeferredCard: some View {
        AFCard {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: "note.text")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Theme.Colors.textTertiary)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Notes")
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("Notes are read-only for now. Editable notes arrive in AMA-2046.")
                        .afMuted()
                }
            }
        }
    }

    private func detailCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        AFCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: systemImage)
                        .foregroundColor(Theme.Colors.readyHigh)
                    Text(title)
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.textPrimary)
                }
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func summaryTitle(for kind: LibraryDetailViewModel.LibraryKind) -> String {
        switch kind {
        case .article:
            return "Summary"
        case .video:
            return "Video summary"
        case .workout:
            return "Workout preview"
        case .plan:
            return "Plan preview"
        }
    }

    private func placeholderColor(for kind: LibraryDetailViewModel.LibraryKind) -> Color {
        switch kind {
        case .workout: return Theme.Colors.readyHigh
        case .video: return Theme.Colors.accentBlue
        case .article: return Theme.Colors.accentOrange
        case .plan: return Theme.Colors.readyModerate
        }
    }

    private var loadError: CTAError? {
        if case .error(let error) = viewModel.state {
            return error
        }
        return viewModel.ctaError
    }
}

private struct DetailTagPills: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(tags.prefix(4), id: \.self) { tag in
                Text(tag)
                    .font(Theme.Typography.label)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.Colors.chipBackground)
                    .clipShape(Capsule())
            }
            if tags.count > 4 {
                Text("+\(tags.count - 4)")
                    .font(Theme.Typography.label)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
    }
}

#if DEBUG
#Preview("Library detail") {
    NavigationStack {
        LibraryDetailView(itemID: "mock-strength-basics", viewModel: LibraryDetailViewModel(apiService: FixtureAPIService()))
    }
}
#endif
