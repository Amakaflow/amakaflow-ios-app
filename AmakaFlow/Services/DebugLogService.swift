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

    let maxEntries = 100
    let store: DiagnosticEventStore
    let redactor: DiagnosticRedactor
    let accountIdentifierProvider: @MainActor @Sendable () -> String?
    let accountIdentifierPublisher: @MainActor @Sendable () -> AnyPublisher<String?, Never>
    let diagnosticSnapshotReader: @MainActor @Sendable (DiagnosticSnapshotScope) async throws -> [DiagnosticEvent]

    @Published var entries: [DebugLogEntry] = []

    var writeTail: Task<Void, Never>?
    var accountLoadTask: Task<Void, Never>?
    var migrationTask: Task<Void, Never>?
    var accountStateCancellable: AnyCancellable?
    var currentAccountHash: String?
    var accountLoadGeneration = 0
    var hasLocalMutation = false

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
        },
        diagnosticSnapshotReader: (@MainActor @Sendable (DiagnosticSnapshotScope) async throws -> [DiagnosticEvent])? = nil
    ) {
        self.store = store
        self.redactor = redactor
        self.accountIdentifierProvider = accountIdentifierProvider
        self.accountIdentifierPublisher = accountIdentifierPublisher
        self.diagnosticSnapshotReader = diagnosticSnapshotReader ?? { scope in
            try await store.snapshot(scope)
        }
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
        // Response bodies are intentionally never persisted. They can contain customer,
        // authentication, health, or location data; callers may pass one for API
        // compatibility, but diagnostics record only safe status and error summaries.
        _ = response
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
        record(
            category: .api,
            severity: .error,
            name: "api.request.failed",
            displayTitle: "\(method) \(endpoint) failed",
            message: details,
            metadata: metadata,
            requestID: requestID
        )
    }

    /// Log an API success (optional, for debugging)
    func logAPISuccess(endpoint: String, method: String = "GET", statusCode: Int) {
        record(
            category: .api,
            severity: .info,
            name: "api.request.succeeded",
            displayTitle: "\(method) \(endpoint)",
            message: "Status: \(statusCode)",
            metadata: ["Endpoint": endpoint, "Method": method, "Status": "\(statusCode)"]
        )
    }

    /// Log a Watch connectivity error
    func logWatchError(title: String, details: String, metadata: [String: String]? = nil) {
        record(
            category: .watch,
            severity: .error,
            name: "watch.error",
            displayTitle: title,
            message: details,
            metadata: metadata ?? [:]
        )
    }

    /// Log a Watch connectivity event
    func logWatchEvent(title: String, details: String) {
        record(
            category: .watch,
            severity: .info,
            name: "watch.event",
            displayTitle: title,
            message: details
        )
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

        record(
            category: .completion,
            severity: .error,
            name: "completion.failed",
            displayTitle: "Completion failed",
            message: error.localizedDescription,
            metadata: metadata
        )
    }

    /// Log a network error
    func logNetworkError(error: Error, context: String? = nil) {
        record(
            category: .network,
            severity: .warning,
            name: "network.error",
            displayTitle: "Network error",
            message: error.localizedDescription,
            metadata: context.map { ["Context": $0] } ?? [:]
        )
    }

    /// Log an authentication error
    func logAuthError(details: String, context: String? = nil) {
        record(
            category: .auth,
            severity: .error,
            name: "auth.error",
            displayTitle: "Authentication error",
            message: details,
            metadata: context.map { ["Context": $0] } ?? [:]
        )
    }

    /// Log a general debug message
    func log(_ title: String, details: String, metadata: [String: String]? = nil) {
        record(
            category: .general,
            severity: .info,
            name: "general.event",
            displayTitle: title,
            message: details,
            metadata: metadata ?? [:]
        )
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

    private func record(
        category: DiagnosticEventCategory,
        severity: DiagnosticEventSeverity,
        name: String,
        displayTitle: String,
        message: String,
        metadata: [String: String] = [:],
        requestID: String? = nil
    ) {
        addEvent(
            redactor.redact(
                category: category,
                severity: severity,
                name: name,
                displayTitle: displayTitle,
                message: message,
                metadata: metadata,
                requestID: requestID,
                accountIdentifier: accountIdentifierProvider()
            )
        )
    }
}
