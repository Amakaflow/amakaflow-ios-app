//
//  AddKnowledgeView.swift
//  AmakaFlow
//
//  AMA-2006: Add-to-Library sheet for saving URL-based knowledge cards.
//

import Combine
import SwiftUI
import UIKit

struct AddKnowledgeView: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel: AddToLibraryViewModel
    private let onSaved: () -> Void

    init(
        viewModel: AddToLibraryViewModel? = nil,
        onSaved: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: viewModel ?? AddToLibraryViewModel())
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        header
                        urlSection
                        previewSection
                        kindSection
                        tagSection
                        comingSoonSection
                        saveButton
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.lg)
                }
            }
            .navigationTitle("Add to Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Theme.Colors.accentBlue)
                }
            }
            .overlay(alignment: .top) {
                if let error = viewModel.ctaError {
                    ErrorToast(
                        actionTitle: viewModel.errorActionTitle,
                        error: error,
                        onRetry: error.isRetryable ? { Task { await viewModel.retryLastAction() } } : nil,
                        onReport: { viewModel.reportError() },
                        onDismiss: { viewModel.dismissError() }
                    )
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.md)
                }
            }
            .task {
                viewModel.detectClipboardURL(UIPasteboard.general.string)
            }
            .onChange(of: viewModel.didSave) { _, didSave in
                guard didSave else { return }
                onSaved()
                dismiss()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Save a link")
                .afH1()
            Text("Paste a workout, video, article, or plan URL. AmakaFlow will save the real card and show whatever the backend returns in Library.")
                .afMuted()
        }
    }

    private var urlSection: some View {
        AFCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                AFLabel(text: "URL")
                HStack(spacing: Theme.Spacing.sm) {
                    TextField("https://example.com/workout", text: $viewModel.urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .accessibilityIdentifier("af_addlibrary_url")

                    if viewModel.isFetchingPreview {
                        ProgressView()
                            .tint(Theme.Colors.textPrimary)
                    }
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                        .stroke(Theme.Colors.borderLight, lineWidth: 1)
                )

                HStack(spacing: Theme.Spacing.sm) {
                    Button("Load preview") {
                        Task { await viewModel.fetchPreview() }
                    }
                    .buttonStyle(AFGhostButtonStyle(size: .sm, isWide: false))
                    .disabled(!viewModel.canFetchPreview)

                    if viewModel.detectedClipboardURL != nil {
                        Text("Detected from clipboard")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        switch viewModel.previewState {
        case .idle:
            EmptyView()
        case .loading:
            AFCard {
                HStack(spacing: Theme.Spacing.md) {
                    ProgressView().tint(Theme.Colors.textPrimary)
                    Text("Fetching preview…")
                        .afMuted()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .content(let preview):
            OGPreviewCard(preview: preview, host: viewModel.currentHost)
        case .failed:
            AFCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(Theme.Colors.accentOrange)
                        Text("Couldn't load a preview")
                            .font(Theme.Typography.title3)
                            .foregroundColor(Theme.Colors.textPrimary)
                    }
                    Text("You can still save the URL. The Library will show the card once the backend ingests it.")
                        .afMuted()
                    Button("Try preview again") {
                        Task { await viewModel.fetchPreview() }
                    }
                    .buttonStyle(AFGhostButtonStyle(size: .sm, isWide: false))
                }
            }
        }
    }

    private var kindSection: some View {
        AFCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                AFLabel(text: "Kind")
                Text("Auto-detected from the URL. Override if it belongs elsewhere.")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.sm) {
                    ForEach(LibraryViewModel.displayKinds, id: \.self) { kind in
                        kindButton(kind)
                    }
                }
            }
        }
    }

    private func kindButton(_ kind: Components.Schemas.LibraryKind) -> some View {
        Button {
            viewModel.selectKind(kind)
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: LibraryViewModel.kindIcon(kind))
                Text(LibraryViewModel.kindSingularLabel(kind))
                    .font(Theme.Typography.footnote.weight(.semibold))
            }
            .foregroundColor(viewModel.selectedKind == kind ? Theme.Colors.primaryForeground : Theme.Colors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(viewModel.selectedKind == kind ? Theme.Colors.primary : Theme.Colors.chipBackground)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("af_addlibrary_kind_\(kind.rawValue)")
        .accessibilityAddTraits(viewModel.selectedKind == kind ? .isSelected : [])
    }

    private var tagSection: some View {
        AFCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                AFLabel(text: "Tags")
                HStack(spacing: Theme.Spacing.sm) {
                    TextField("strength, mobility, race", text: $viewModel.tagDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .onSubmit { viewModel.commitTagDraft() }

                    Button("Add") { viewModel.commitTagDraft() }
                        .buttonStyle(AFGhostButtonStyle(size: .sm, isWide: false))
                        .disabled(!viewModel.canCommitTagDraft)
                }

                if !viewModel.tags.isEmpty {
                    FlowPills(tags: viewModel.tags) { tag in
                        viewModel.removeTag(tag)
                    }
                } else {
                    Text("Optional. Tags are sent with the save intent; Library will only display tags the backend returns.")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }
        }
    }

    private var comingSoonSection: some View {
        AFCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                AFLabel(text: "More ways to add")
                comingSoonRow(icon: "qrcode.viewfinder", title: "Scan QR")
                comingSoonRow(icon: "square.and.arrow.down", title: "From shared")
                comingSoonRow(icon: "note.text", title: "Write a note")
            }
        }
    }

    private func comingSoonRow(icon: String, title: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .frame(width: 22)
            Text(title)
            Spacer()
            Text("Coming soon")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .font(Theme.Typography.body)
        .foregroundColor(Theme.Colors.textTertiary)
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), coming soon")
    }

    private var saveButton: some View {
        Button {
            Task { await viewModel.save() }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                if viewModel.isSaving {
                    ProgressView()
                        .tint(Theme.Colors.primaryForeground)
                }
                Text(viewModel.saveButtonTitle)
            }
        }
        .buttonStyle(AFPrimaryButtonStyle(size: .lg))
        .disabled(!viewModel.canSave)
        .accessibilityIdentifier("af_addlibrary_save")
    }
}

private struct OGPreviewCard: View {
    let preview: OGPreview
    let host: String?

    var body: some View {
        AFCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Rectangle()
                        .fill(Theme.Colors.chipBackground)
                    if let imageURL = preview.imageURL {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                Image(systemName: "link")
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundColor(Theme.Colors.textTertiary)
                            }
                        }
                    } else {
                        Image(systemName: "link")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                }
                .frame(height: 150)
                .clipped()

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text(preview.title ?? "Untitled link")
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(2)
                    Text(preview.siteName ?? host ?? "Preview loaded")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .padding(Theme.Spacing.md)
            }
        }
        .accessibilityIdentifier("af_addlibrary_preview")
    }
}

private struct FlowPills: View {
    let tags: [String]
    let onRemove: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: Theme.Spacing.xs)], alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(tags, id: \.self) { tag in
                Button {
                    onRemove(tag)
                } label: {
                    HStack(spacing: 4) {
                        Text(tag)
                            .lineLimit(1)
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .font(Theme.Typography.label)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Theme.Colors.chipBackground)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct OGPreview: Equatable {
    let url: URL
    let title: String?
    let imageURL: URL?
    let siteName: String?
}

protocol OGPreviewFetching {
    func fetchPreview(for url: URL) async throws -> OGPreview
}

struct URLSessionOGPreviewFetcher: OGPreviewFetching {
    func fetchPreview(for url: URL) async throws -> OGPreview {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw APIError.decodingError(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "HTML was not UTF-8")))
        }
        return AddToLibraryHTMLParser.preview(from: html, baseURL: url)
    }
}

enum AddToLibraryHTMLParser {
    static func preview(from html: String, baseURL: URL) -> OGPreview {
        OGPreview(
            url: baseURL,
            title: metaContent(property: "og:title", in: html) ?? titleTag(in: html),
            imageURL: metaContent(property: "og:image", in: html).flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL },
            siteName: metaContent(property: "og:site_name", in: html)
        )
    }

    private static func metaContent(property: String, in html: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: property)
        let patterns = [
            #"<meta[^>]+property=["']\#(escaped)["'][^>]+content=["']([^"']+)["'][^>]*>"#,
            #"<meta[^>]+content=["']([^"']+)["'][^>]+property=["']\#(escaped)["'][^>]*>"#,
            #"<meta[^>]+name=["']\#(escaped)["'][^>]+content=["']([^"']+)["'][^>]*>"#
        ]
        for pattern in patterns {
            if let match = firstCapture(pattern: pattern, in: html) {
                return decodeHTML(match)
            }
        }
        return nil
    }

    private static func titleTag(in html: String) -> String? {
        firstCapture(pattern: #"<title[^>]*>(.*?)</title>"#, in: html).map(decodeHTML)
    }

    private static func firstCapture(pattern: String, in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: nsRange),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{26}amp;", with: "\u{26}")
            .replacingOccurrences(of: "\u{26}quot;", with: "\"")
            .replacingOccurrences(of: "\u{26}#39;", with: "'")
            .replacingOccurrences(of: "\u{26}lt;", with: "<")
            .replacingOccurrences(of: "\u{26}gt;", with: ">")
    }
}

protocol KnowledgeCardSaving {
    func saveLibraryCard(
        url: URL,
        kind: Components.Schemas.LibraryKind,
        tags: [String],
        preview: OGPreview?
    ) async throws -> KnowledgeCard
}

extension KnowledgeService: KnowledgeCardSaving {
    func saveLibraryCard(
        url: URL,
        kind: Components.Schemas.LibraryKind,
        tags: [String],
        preview: OGPreview?
    ) async throws -> KnowledgeCard {
        try await ingest(url: url.absoluteString, kind: kind, tags: tags, preview: preview)
    }
}

@MainActor
final class AddToLibraryViewModel: ObservableObject {
    typealias LibraryKind = Components.Schemas.LibraryKind

    enum PreviewState: Equatable {
        case idle
        case loading
        case content(OGPreview)
        case failed(CTAError)
    }

    enum FailedAction: Equatable {
        case fetchPreview
        case save
    }

    @Published var urlText: String
    @Published private(set) var previewState: PreviewState = .idle
    @Published private(set) var selectedKind: LibraryKind
    @Published var tagDraft: String = ""
    @Published private(set) var tags: [String] = []
    @Published private(set) var ctaError: CTAError?
    @Published private(set) var isSaving = false
    @Published private(set) var didSave = false
    @Published private(set) var detectedClipboardURL: URL?
    private(set) var lastFailedAction: FailedAction?

    private let previewFetcher: OGPreviewFetching
    private let saver: KnowledgeCardSaving

    init(
        urlText: String = "",
        selectedKind: LibraryKind = .article,
        previewFetcher: OGPreviewFetching = URLSessionOGPreviewFetcher(),
        saver: KnowledgeCardSaving = KnowledgeService.shared
    ) {
        self.urlText = urlText
        self.selectedKind = selectedKind
        self.previewFetcher = previewFetcher
        self.saver = saver
        if let url = Self.normalizedURL(from: urlText) {
            self.selectedKind = Self.autoDetectKind(for: url)
        }
    }

    var canFetchPreview: Bool {
        Self.normalizedURL(from: urlText) != nil && !isFetchingPreview
    }

    var canSave: Bool {
        Self.normalizedURL(from: urlText) != nil && !isSaving
    }

    var canCommitTagDraft: Bool {
        !Self.normalizedTags(from: tagDraft).isEmpty
    }

    var isFetchingPreview: Bool {
        previewState == .loading
    }

    var saveButtonTitle: String {
        isSaving ? "Saving…" : "Save"
    }

    var errorActionTitle: String {
        lastFailedAction == .save ? "Couldn't save link" : "Couldn't load preview"
    }

    var currentHost: String? {
        Self.normalizedURL(from: urlText)?.host?.removingWWWPrefix()
    }

    func detectClipboardURL(_ clipboardString: String?) {
        guard urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let clipboardString,
              let url = Self.normalizedURL(from: clipboardString) else {
            return
        }
        detectedClipboardURL = url
        urlText = url.absoluteString
        selectedKind = Self.autoDetectKind(for: url)
    }

    func fetchPreview() async {
        guard let url = Self.normalizedURL(from: urlText) else {
            applyFailure(.unknown(description: "Enter a valid http or https URL."), action: .fetchPreview)
            return
        }

        previewState = .loading
        ctaError = nil
        lastFailedAction = nil
        selectedKind = Self.autoDetectKind(for: url)

        do {
            let preview = try await previewFetcher.fetchPreview(for: url)
            previewState = .content(preview)
        } catch {
            let mapped = CTAError.map(error)
            applyFailure(mapped, action: .fetchPreview)
        }
    }

    func selectKind(_ kind: LibraryKind) {
        selectedKind = kind
    }

    func commitTagDraft() {
        let newTags = Self.normalizedTags(from: tagDraft)
        guard !newTags.isEmpty else { return }
        for tag in newTags where !tags.contains(where: { $0.compare(tag, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            tags.append(tag)
        }
        tagDraft = ""
    }

    func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }

    func save() async {
        commitTagDraft()
        guard let url = Self.normalizedURL(from: urlText) else {
            applyFailure(.unknown(description: "Enter a valid http or https URL."), action: .save)
            return
        }

        isSaving = true
        ctaError = nil
        lastFailedAction = nil

        do {
            _ = try await saver.saveLibraryCard(
                url: url,
                kind: selectedKind,
                tags: tags,
                preview: currentPreview
            )
            didSave = true
        } catch {
            let mapped = CTAError.map(error)
            applyFailure(mapped, action: .save)
        }

        isSaving = false
    }

    func retryLastAction() async {
        switch lastFailedAction {
        case .fetchPreview:
            await fetchPreview()
        case .save:
            await save()
        case .none:
            break
        }
    }

    func dismissError() {
        let currentError = ctaError
        ctaError = nil
        if lastFailedAction == .fetchPreview, let currentError {
            previewState = .failed(currentError)
        }
    }

    func reportError(reporter: ErrorReporting? = nil) {
        guard let ctaError else { return }
        let reporter = reporter ?? ErrorReporter.shared
        reporter.report(
            action: lastFailedAction == .save ? "add_library_save" : "add_library_preview",
            error: ctaError,
            endpoint: lastFailedAction == .save ? "/v1/knowledge/cards" : currentHost,
            userId: PairingService.shared.userProfile?.id
        )
    }

    private var currentPreview: OGPreview? {
        if case .content(let preview) = previewState { return preview }
        return nil
    }

    private func applyFailure(_ error: CTAError, action: FailedAction) {
        ctaError = error
        lastFailedAction = action
        if action == .fetchPreview {
            previewState = .failed(error)
        }
    }

    static func normalizedURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }

    static func autoDetectKind(for url: URL) -> LibraryKind {
        let host = (url.host ?? "").lowercased()
        if host.contains("youtube") || host.contains("youtu.be") || host.contains("vimeo") || host.contains("tiktok") || host.contains("instagram") {
            return .video
        }
        if host.contains("trainingpeaks") || host.contains("finalsurge") || host.contains("todaysplan") {
            return .plan
        }
        if host.contains("strava") || host.contains("connect.garmin") || host.contains("intervals.icu") {
            return .workout
        }
        return .article
    }

    static func normalizedTags(from input: String) -> [String] {
        input
            .split { $0 == "," || $0 == "\n" }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
            .filter { !$0.isEmpty }
    }
}

private extension String {
    func removingWWWPrefix() -> String {
        hasPrefix("www.") ? String(dropFirst(4)) : self
    }
}

// MARK: - Preview

#Preview {
    AddKnowledgeView()
        .preferredColorScheme(.dark)
}
