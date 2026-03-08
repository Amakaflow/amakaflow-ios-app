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

    private let storageKey = "DebugLogEntries"
    private let maxEntries = 100

    @Published private(set) var entries: [DebugLogEntry] = []

    // Background serial queue for debounced saves
    private let saveQueue = DispatchQueue(label: "com.amakaflow.debuglog.save", qos: .utility)
    private var saveWorkItem: DispatchWorkItem?
    private let saveDebounceInterval: TimeInterval = 0.5

    private init() {
        // Load entries on background queue to avoid blocking main thread (AMA-1075)
        Task.detached(priority: .utility) { [weak self] in
            let loadedEntries = await self?.loadEntriesBackground() ?? []
            await MainActor.run {
                self?.entries = loadedEntries
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
        error: Error? = nil
    ) {
        var metadata: [String: String] = [
            "Endpoint": endpoint,
            "Method": method
        ]
        if let statusCode = statusCode {
            metadata["Status"] = "\(statusCode)"
        }
        if let response = response {
            metadata["Response"] = String(response.prefix(500))
        }

        let details = error?.localizedDescription ?? response ?? "Unknown error"

        let entry = DebugLogEntry(
            type: .apiError,
            title: "\(method) \(endpoint) failed",
            details: details,
            metadata: metadata
        )
        addEntry(entry)
    }

    /// Log an API success (optional, for debugging)
    func logAPISuccess(endpoint: String, method: String = "GET", statusCode: Int) {
        let entry = DebugLogEntry(
            type: .apiSuccess,
            title: "\(method) \(endpoint)",
            details: "Status: \(statusCode)",
            metadata: ["Endpoint": endpoint, "Method": method, "Status": "\(statusCode)"]
        )
        addEntry(entry)
    }

    /// Log a Watch connectivity error
    func logWatchError(title: String, details: String, metadata: [String: String]? = nil) {
        let entry = DebugLogEntry(
            type: .watchError,
            title: title,
            details: details,
            metadata: metadata
        )
        addEntry(entry)
    }

    /// Log a Watch connectivity event
    func logWatchEvent(title: String, details: String) {
        let entry = DebugLogEntry(
            type: .watchEvent,
            title: title,
            details: details,
            metadata: nil
        )
        addEntry(entry)
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

        let entry = DebugLogEntry(
            type: .completionError,
            title: "Completion failed",
            details: error.localizedDescription,
            metadata: metadata
        )
        addEntry(entry)
    }

    /// Log a network error
    func logNetworkError(error: Error, context: String? = nil) {
        let entry = DebugLogEntry(
            type: .networkError,
            title: "Network error",
            details: error.localizedDescription,
            metadata: context != nil ? ["Context": context!] : nil
        )
        addEntry(entry)
    }

    /// Log an authentication error
    func logAuthError(details: String, context: String? = nil) {
        let entry = DebugLogEntry(
            type: .authError,
            title: "Authentication error",
            details: details,
            metadata: context != nil ? ["Context": context!] : nil
        )
        addEntry(entry)
    }

    /// Log a general debug message
    func log(_ title: String, details: String, metadata: [String: String]? = nil) {
        let entry = DebugLogEntry(
            type: .general,
            title: title,
            details: details,
            metadata: metadata
        )
        addEntry(entry)
    }

    /// Clear all log entries
    func clearLog() {
        entries = []
        saveEntries()
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

    private func addEntry(_ entry: DebugLogEntry) {
        entries.insert(entry, at: 0)

        // Prune old entries
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }

        // Debounced save to background queue (AMA-1075)
        scheduleSaveEntries()

        // Also print to console for Xcode debugging
        print("[DebugLog] \(entry.type.rawValue): \(entry.title) - \(entry.details)")
    }

    /// Schedule a debounced save to avoid writing on every log call
    private func scheduleSaveEntries() {
        // Cancel any pending save
        saveWorkItem?.cancel()

        // Create new debounced save
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            // Capture entries on main actor before going to background
            let entriesToSave = self.entries
            self.saveEntriesBackground(entries: entriesToSave)
        }
        saveWorkItem = workItem

        // Schedule with debounce delay
        saveQueue.asyncAfter(deadline: .now() + saveDebounceInterval, execute: workItem)
    }

    private func saveEntriesBackground(entries: [DebugLogEntry]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entries)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("[DebugLogService] Failed to save entries: \(error)")
        }
    }

    private func saveEntries() {
        // For immediate saves (clearLog), save immediately on background queue
        saveQueue.async { [weak self] in
            guard let self = self else { return }
            let entriesToSave = self.entries
            self.saveEntriesBackground(entries: entriesToSave)
        }
    }

    /// Load entries on background thread
    private func loadEntriesBackground() async -> [DebugLogEntry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return []
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([DebugLogEntry].self, from: data)
        } catch {
            print("[DebugLogService] Failed to load entries: \(error)")
            return []
        }
    }

    private func loadEntries() {
        // Synchronous version kept for compatibility, but init now uses async loading
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([DebugLogEntry].self, from: data)
        } catch {
            print("[DebugLogService] Failed to load entries: \(error)")
            entries = []
        }
    }
}
