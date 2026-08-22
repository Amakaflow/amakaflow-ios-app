//
//  DebugLogService.swift
//  AmakaFlow
//
//  Centralized error logging service for debugging API and device failures
//

import Foundation
import Combine

// MARK: - Log Entry Types

enum DebugLogType: String, Codable {
    case apiError = "API_ERROR"
    case apiSuccess = "API_SUCCESS"
    case watchError = "WATCH_ERROR"
    case watchEvent = "WATCH_EVENT"
    case completionError = "COMPLETION_ERROR"
    case networkError = "NETWORK_ERROR"
    case authError = "AUTH_ERROR"
    case general = "GENERAL"
}

// MARK: - Log Entry

struct DebugLogEntry: Identifiable, Codable {
    let id: String
    let timestamp: Date
    let type: DebugLogType
    let title: String
    let details: String
    let metadata: [String: String]?

    init(type: DebugLogType, title: String, details: String, metadata: [String: String]? = nil) {
        self.id = UUID().uuidString
        self.timestamp = Date()
        self.type = type
        self.title = title
        self.details = details
        self.metadata = metadata
    }

    init(
        id: String,
        timestamp: Date,
        type: DebugLogType,
        title: String,
        details: String,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.title = title
        self.details = details
        self.metadata = metadata
    }

    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: timestamp)
    }

    var copyableText: String {
        var text = "[\(formattedTimestamp)] \(type.rawValue)\n"
        text += "Title: \(title)\n"
        text += "Details: \(details)\n"
        if let metadata = metadata, !metadata.isEmpty {
            for (key, value) in metadata.sorted(by: { $0.key < $1.key }) {
                text += "\(key): \(value)\n"
            }
        }
        return text
    }
}

// MARK: - Debug Log Service

@MainActor
class DebugLogService: ObservableObject {
    static let shared = DebugLogService()

    private let maxEntries = 100
    private let store: DiagnosticEventStore
    private let redactor: DiagnosticRedactor
    private let accountIdentifierProvider: @MainActor @Sendable () -> String?
    private let accountIdentifierPublisher: @MainActor @Sendable () -> AnyPublisher<String?, Never>

    @Published private(set) var entries: [DebugLogEntry] = []

    private var pendingWriteTasks: [Task<Void, Never>] = []
    private var writeTail: Task<Void, Never>?
    private var accountLoadTask: Task<Void, Never>?
    private var migrationTask: Task<Void, Never>?
    private var accountStateCancellable: AnyCancellable?
    private var currentAccountHash: String?
    private var accountLoadGeneration = 0
    private var hasLocalMutation = false

    init(
        store: DiagnosticEventStore = DiagnosticEventStore(),
        redactor: DiagnosticRedactor = DiagnosticRedactor(),
        accountIdentifierProvider: @escaping @MainActor @Sendable () -> String? = {
            AuthViewModel.shared.userProfile?.id
        },
        accountIdentifierPublisher: @escaping @MainActor @Sendable () -> AnyPublisher<String?, Never> = {
            AuthViewModel.shared.$userProfile
                .map { $0?.id }
                .removeDuplicates()
                .eraseToAnyPublisher()
        }
    ) {
        self.store = store
        self.redactor = redactor
        self.accountIdentifierProvider = accountIdentifierProvider
        self.accountIdentifierPublisher = accountIdentifierPublisher
        self.migrationTask = Task.detached(priority: .utility) { [store] in
            do {
                try await store.migrateLegacyIfNeeded()
            } catch {
                print("[DebugLogService] Failed to load diagnostic events")
            }
        }
        bindAccountState()
    }

    // MARK: - Public API

    /// Log an API error
    func logAPIError(
        endpoint: String,
        method: String = "GET",
        statusCode: Int? = nil,
        response: String? = nil,
        error: Error? = nil,
        requestID: String? = nil
    ) {
        var metadata: [String: String] = [
            "Endpoint": endpoint,
            "Method": method
        ]
        if let statusCode = statusCode {
            metadata["Status"] = "\(statusCode)"
        }
        // AMA-1823: surface the request_id so debug log entries can be
        // correlated with Sentry breadcrumbs and BFF/mapper-api logs.
        if let requestID = requestID {
            metadata["request_id"] = requestID
            SupportDiagnosticsRuntimeState.shared.recordRequestID(requestID)
        }

        let details = error?.localizedDescription
            ?? statusCode.map { "HTTP \($0) response omitted from diagnostics" }
            ?? "API request failed"
        let event = redactor.redact(
            category: .api,
            severity: .error,
            name: "api.request.failed",
            displayTitle: "\(method) \(endpoint) failed",
            message: details,
            metadata: metadata,
            requestID: requestID,
            accountIdentifier: accountIdentifierProvider()
        )
        addEvent(event)
    }

    /// Log an API success (optional, for debugging)
    func logAPISuccess(endpoint: String, method: String = "GET", statusCode: Int) {
        let event = redactor.redact(
            category: .api,
            severity: .info,
            name: "api.request.succeeded",
            displayTitle: "\(method) \(endpoint)",
            message: "Status: \(statusCode)",
            metadata: ["Endpoint": endpoint, "Method": method, "Status": "\(statusCode)"],
            accountIdentifier: accountIdentifierProvider()
        )
        addEvent(event)
    }

    /// Log a Watch connectivity error
    func logWatchError(title: String, details: String, metadata: [String: String]? = nil) {
        let event = redactor.redact(
            category: .watch,
            severity: .error,
            name: "watch.error",
            displayTitle: title,
            message: details,
            metadata: metadata ?? [:],
            accountIdentifier: accountIdentifierProvider()
        )
        addEvent(event)
    }

    /// Log a Watch connectivity event
    func logWatchEvent(title: String, details: String) {
        let event = redactor.redact(
            category: .watch,
            severity: .info,
            name: "watch.event",
            displayTitle: title,
            message: details,
            accountIdentifier: accountIdentifierProvider()
        )
        addEvent(event)
    }

    /// Log a workout completion error
    func logCompletionError(workoutId: String?, error: Error, context: String? = nil) {
        var metadata: [String: String] = [:]
        if let workoutId = workoutId {
            metadata["WorkoutID"] = workoutId
        }
        if let context = context {
            metadata["Context"] = context
        }

        let event = redactor.redact(
            category: .completion,
            severity: .error,
            name: "completion.failed",
            displayTitle: "Completion failed",
            message: error.localizedDescription,
            metadata: metadata,
            accountIdentifier: accountIdentifierProvider()
        )
        addEvent(event)
    }

    /// Log a network error
    func logNetworkError(error: Error, context: String? = nil) {
        let event = redactor.redact(
            category: .network,
            severity: .warning,
            name: "network.error",
            displayTitle: "Network error",
            message: error.localizedDescription,
            metadata: context.map { ["Context": $0] } ?? [:],
            accountIdentifier: accountIdentifierProvider()
        )
        addEvent(event)
    }

    /// Log an authentication error
    func logAuthError(details: String, context: String? = nil) {
        let event = redactor.redact(
            category: .auth,
            severity: .error,
            name: "auth.error",
            displayTitle: "Authentication error",
            message: details,
            metadata: context.map { ["Context": $0] } ?? [:],
            accountIdentifier: accountIdentifierProvider()
        )
        addEvent(event)
    }

    /// Log a general debug message
    func log(_ title: String, details: String, metadata: [String: String]? = nil) {
        let event = redactor.redact(
            category: .general,
            severity: .info,
            name: "general.event",
            displayTitle: title,
            message: details,
            metadata: metadata ?? [:],
            accountIdentifier: accountIdentifierProvider()
        )
        addEvent(event)
    }

    /// Clear all log entries
    func clearLog() {
        hasLocalMutation = true
        entries = []
        enqueueWrite { [store] in
            try await store.clear()
        }
    }

    /// Get all entries as copyable text
    func getAllEntriesAsText() -> String {
        if entries.isEmpty {
            return "No debug log entries"
        }

        var text = "=== AmakaFlow Debug Log ===\n"
        text += "Generated: \(DebugLogEntry(type: .general, title: "", details: "").formattedTimestamp)\n"
        text += "Entries: \(entries.count)\n\n"

        for entry in entries {
            text += entry.copyableText
            text += "\n"
        }

        return text
    }

    // MARK: - Private Methods

    func waitForPendingWrites() async {
        let tail = writeTail
        let accountLoadTask = accountLoadTask
        pendingWriteTasks = []
        await tail?.value
        await accountLoadTask?.value
    }

    func reloadEntriesForCurrentAccount() async {
        accountIdentifierDidChange(accountIdentifierProvider())
        await waitForPendingWrites()
    }

    // MARK: - Private Methods

    private func addEvent(_ event: DiagnosticEvent) {
        hasLocalMutation = true
        let entry = event.projectedDebugLogEntry
        if eventBelongsToCurrentAccount(event) {
            entries.insert(entry, at: 0)
        }

        // Prune old entries
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }

        enqueueWrite { [store] in
            try await store.append(event)
        }

        // Print only the already-redacted projection for local Xcode debugging.
        print("[DebugLog] \(entry.type.rawValue): \(entry.title) - \(entry.details)")
    }

    private func enqueueWrite(_ operation: @escaping @Sendable () async throws -> Void) {
        let previous = writeTail
        let task = Task.detached(priority: .utility) {
            await previous?.value
            do {
                try await operation()
            } catch {
                print("[DebugLogService] Failed to persist diagnostic event")
            }
        }
        writeTail = task
        pendingWriteTasks.append(task)
    }

    private func bindAccountState() {
        accountStateCancellable = accountIdentifierPublisher()
            .sink { [weak self] accountIdentifier in
                self?.accountIdentifierDidChange(accountIdentifier)
            }
    }

    private func accountIdentifierDidChange(_ accountIdentifier: String?) {
        let newAccountHash = redactor.hashAccountIdentifier(accountIdentifier)
        guard newAccountHash != currentAccountHash || entries.isEmpty else { return }
        accountLoadGeneration += 1
        let generation = accountLoadGeneration
        currentAccountHash = newAccountHash
        entries = []
        hasLocalMutation = false

        guard let newAccountHash else {
            accountLoadTask = nil
            return
        }

        let pendingWrites = writeTail
        let migrationTask = migrationTask
        accountLoadTask = Task { [weak self] in
            await pendingWrites?.value
            await migrationTask?.value
            await self?.loadEntries(for: newAccountHash, generation: generation)
        }
    }

    private func loadEntries(for accountHash: String, generation: Int) async {
        do {
            let loadedEntries = try await store.snapshot(.account(accountHash))
                .prefix(maxEntries)
                .map(\.projectedDebugLogEntry)
            guard generation == accountLoadGeneration, currentAccountHash == accountHash, !hasLocalMutation else { return }
            entries = loadedEntries
        } catch {
            print("[DebugLogService] Failed to reload diagnostic events")
            guard generation == accountLoadGeneration else { return }
            entries = []
        }
    }

    private func eventBelongsToCurrentAccount(_ event: DiagnosticEvent) -> Bool {
        guard let currentAccountHash else { return false }
        return event.accountHash == currentAccountHash
    }
}
