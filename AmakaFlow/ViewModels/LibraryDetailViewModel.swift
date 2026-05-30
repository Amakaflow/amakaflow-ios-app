//
//  LibraryDetailViewModel.swift
//  AmakaFlow
//
//  AMA-2005: saved-content Library detail state.
//

import Combine
import Foundation

@MainActor
final class LibraryDetailViewModel: ObservableObject {
    typealias LibraryItemDetail = Components.Schemas.LibraryItemDetail
    typealias LibraryKind = Components.Schemas.LibraryKind

    enum ScreenState: Equatable {
        case loading
        case content
        case empty
        case error(CTAError)
    }

    enum FailedAction: Equatable {
        case load(id: String)
    }

    @Published private(set) var state: ScreenState = .loading
    @Published private(set) var item: LibraryItemDetail?
    @Published private(set) var ctaError: CTAError?
    private(set) var lastFailedAction: FailedAction?

    private let apiService: APIServiceProviding

    init(apiService: APIServiceProviding? = nil) {
        self.apiService = apiService ?? AppDependencies.current.apiService
    }

    var title: String {
        item?.title ?? "Library detail"
    }

    var sourceCaption: String {
        guard let item else { return "Saved item" }
        let source = Self.trimmed(item.sourceDomain)
        let saved = Self.savedDateText(item.savedAt)

        switch (source, saved) {
        case let (.some(source), .some(saved)):
            return "\(source) • \(saved)"
        case let (.some(source), .none):
            return source
        case let (.none, .some(saved)):
            return saved
        case (.none, .none):
            return LibraryViewModel.kindSingularLabel(item.kind)
        }
    }

    var summaryText: String? {
        Self.trimmed(item?.summary)
    }

    var takeaways: [String] {
        item?.keyTakeaways?.compactMap { Self.trimmed($0) } ?? []
    }

    var tags: [String] {
        item?.tags?.compactMap { Self.trimmed($0) } ?? []
    }

    var sourceURL: URL? {
        guard let sourceUrl = Self.trimmed(item?.sourceUrl) else { return nil }
        return URL(string: sourceUrl)
    }

    var canOpenInBrowser: Bool {
        sourceURL != nil
    }

    func load(id: String) async {
        state = .loading
        ctaError = nil
        lastFailedAction = nil

        do {
            let fetched = try await apiService.getLibraryItem(id: id)
            item = fetched
            state = Self.hasBody(fetched) ? .content : .empty
        } catch {
            let mapped = CTAError.map(error)
            ctaError = mapped
            state = .error(mapped)
            lastFailedAction = .load(id: id)
        }
    }

    func retryLastAction() async {
        switch lastFailedAction {
        case .load(let id):
            await load(id: id)
        case .none:
            break
        }
    }

    func dismissError() {
        let currentError = ctaError
        ctaError = nil

        if case .load = lastFailedAction, let currentError {
            state = .error(currentError)
        }
    }

    func reportError(reporter: ErrorReporting? = nil) {
        guard let ctaError else { return }
        let reporter = reporter ?? ErrorReporter.shared
        reporter.report(
            action: "library_item_detail_load",
            error: ctaError,
            endpoint: "/v1/library/items/{id}",
            userId: PairingService.shared.userProfile?.id
        )
    }

    static func hasBody(_ item: LibraryItemDetail) -> Bool {
        trimmed(item.summary) != nil || !(item.keyTakeaways?.compactMap { trimmed($0) }.isEmpty ?? true)
    }

    static func openButtonTitle(for kind: LibraryKind) -> String {
        switch kind {
        case .video:
            return "Open video"
        default:
            return "Open in browser"
        }
    }

    static func previewOnlyMessage(for kind: LibraryKind) -> String? {
        switch kind {
        case .workout:
            return "Preview only — full import coming soon"
        case .plan:
            return "Preview only — full import coming soon"
        case .article, .video:
            return nil
        }
    }

    static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func savedDateText(_ savedAt: String?) -> String? {
        guard let savedAt = trimmed(savedAt) else { return nil }
        let date = iso8601FractionalFormatter.date(from: savedAt) ?? iso8601Formatter.date(from: savedAt)
        guard let date else { return "Saved" }
        return "Saved \(savedDateFormatter.string(from: date))"
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let iso8601FractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let savedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
