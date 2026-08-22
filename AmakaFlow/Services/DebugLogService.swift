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

    @Published private(set) var entries: [DebugLogEntry] = []

    private var pendingWriteTasks: [Task<Void, Never>] = []

    init(
        store: DiagnosticEventStore = DiagnosticEventStore(),
        redactor: DiagnosticRedactor = DiagnosticRedactor()
    ) {
        self.store = store
        self.redactor = redactor
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let loadedEntries: [DebugLogEntry]
            do {
                try await store.migrateLegacyIfNeeded()
                loadedEntries = try await store.snapshot()
                    .prefix(maxEntries)
                    .map(\.projectedDebugLogEntry)
            } catch {
                print("[DebugLogService] Failed to load diagnostic events")
                loadedEntries = []
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                if self.entries.isEmpty {
                    self.entries = loadedEntries
                }
            }
        }
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
            message: details,
            metadata: metadata,
            requestID: requestID
        )
        addEvent(event)
    }

    /// Log an API success (optional, for debugging)
    func logAPISuccess(endpoint: String, method: String = "GET", statusCode: Int) {
        let event = redactor.redact(
            category: .api,
            severity: .info,
            name: "api.request.succeeded",
            message: "Status: \(statusCode)",
            metadata: ["Endpoint": endpoint, "Method": method, "Status": "\(statusCode)"]
        )
        addEvent(event)
    }

    /// Log a Watch connectivity error
    func logWatchError(title: String, details: String, metadata: [String: String]? = nil) {
        let event = redactor.redact(
            category: .watch,
            severity: .error,
            name: title,
            message: details,
            metadata: metadata ?? [:]
        )
        addEvent(event)
    }

    /// Log a Watch connectivity event
    func logWatchEvent(title: String, details: String) {
        let event = redactor.redact(
            category: .watch,
            severity: .info,
            name: title,
            message: details
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
            name: "Completion failed",
            message: error.localizedDescription,
            metadata: metadata
        )
        addEvent(event)
    }

    /// Log a network error
    func logNetworkError(error: Error, context: String? = nil) {
        let event = redactor.redact(
            category: .network,
            severity: .warning,
            name: "Network error",
            message: error.localizedDescription,
            metadata: context.map { ["Context": $0] } ?? [:]
        )
        addEvent(event)
    }

    /// Log an authentication error
    func logAuthError(details: String, context: String? = nil) {
        let event = redactor.redact(
            category: .auth,
            severity: .error,
            name: "Authentication error",
            message: details,
            metadata: context.map { ["Context": $0] } ?? [:]
        )
        addEvent(event)
    }

    /// Log a general debug message
    func log(_ title: String, details: String, metadata: [String: String]? = nil) {
        let event = redactor.redact(
            category: .general,
            severity: .info,
            name: title,
            message: details,
            metadata: metadata ?? [:]
        )
        addEvent(event)
    }

    /// Clear all log entries
    func clearLog() {
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
        let tasks = pendingWriteTasks
        pendingWriteTasks = []
        for task in tasks {
            await task.value
        }
    }

    // MARK: - Private Methods

    private func addEvent(_ event: DiagnosticEvent) {
        let entry = event.projectedDebugLogEntry
        entries.insert(entry, at: 0)

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
        let task = Task.detached(priority: .utility) {
            do {
                try await operation()
            } catch {
                print("[DebugLogService] Failed to persist diagnostic event")
            }
        }
        pendingWriteTasks.append(task)
    }
}
