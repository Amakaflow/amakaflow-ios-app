import Foundation

actor DiagnosticEventStore {
    private static let migrationMarkerKey = "SupportDiagnostics.DebugLogEntriesMigrated.v1"
    private static let retentionInterval: TimeInterval = 7 * 24 * 60 * 60

    nonisolated let eventsFileURL: URL

    private let userDefaults: UserDefaults
    private let now: @Sendable () -> Date
    private let maxBytes: Int
    private let fileManager: FileManager
    private let redactor: DiagnosticRedactor
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var lastAppliedFileProtection: FileProtectionType?

    init(
        rootURL: URL? = nil,
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = Date.init,
        maxBytes: Int = 5 * 1024 * 1024,
        redactor: DiagnosticRedactor = DiagnosticRedactor()
    ) {
        let root = rootURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = root.appendingPathComponent("SupportDiagnostics", isDirectory: true)
        self.eventsFileURL = directory.appendingPathComponent("diagnostic-events.ndjson")
        self.userDefaults = userDefaults
        self.now = now
        self.maxBytes = maxBytes
        self.fileManager = fileManager
        self.redactor = redactor
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func append(_ event: DiagnosticEvent) async throws {
        var events = try loadEvents()
        events.append(event)
        try persist(retained(events))
    }

    func snapshot(accountHash: String? = nil) async throws -> [DiagnosticEvent] {
        let events = try cleanupRetentionIfNeeded()
        let scopedEvents: [DiagnosticEvent]
        if let accountHash {
            scopedEvents = events.filter { $0.accountHash == accountHash }
        } else {
            scopedEvents = events
        }
        return scopedEvents.sorted { $0.timestamp > $1.timestamp }
    }

    func clear() async throws {
        try ensureDirectory()
        if fileManager.fileExists(atPath: eventsFileURL.path) {
            try fileManager.removeItem(at: eventsFileURL)
        }
        try Data().write(to: eventsFileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try setFileProtection()
    }

    func migrateLegacyIfNeeded() async throws {
        guard !userDefaults.bool(forKey: Self.migrationMarkerKey) else {
            _ = try cleanupRetentionIfNeeded()
            return
        }

        guard let data = userDefaults.data(forKey: DefaultsKey.debugLogEntries.rawValue) else {
            completeLegacyMigration()
            return
        }

        let legacyEntries: [DebugLogEntry]
        do {
            legacyEntries = try decoder.decode([DebugLogEntry].self, from: data)
        } catch {
            completeLegacyMigration()
            return
        }

        var events = try loadEvents()
        events.append(contentsOf: legacyEntries.map(redactor.redactLegacyEntry))
        try persist(retained(events))
        completeLegacyMigration()
    }

    func waitForPendingWrites() async {}

    func persistedFileProtection() throws -> FileProtectionType? {
        let attributes = try fileManager.attributesOfItem(atPath: eventsFileURL.path)
        return attributes[.protectionKey] as? FileProtectionType ?? lastAppliedFileProtection
    }

    private func retained(_ events: [DiagnosticEvent]) throws -> [DiagnosticEvent] {
        let cutoff = now().addingTimeInterval(-Self.retentionInterval)
        var retained = events
            .filter { $0.timestamp >= cutoff }
            .sorted { $0.timestamp < $1.timestamp }

        while encodedSize(retained) > maxBytes, !retained.isEmpty {
            retained.removeFirst()
        }

        return retained
    }

    private func cleanupRetentionIfNeeded() throws -> [DiagnosticEvent] {
        let events = try loadEvents()
        let retainedEvents = try retained(events)
        if events != retainedEvents {
            try persist(retainedEvents)
        }
        return retainedEvents
    }

    private func encodedSize(_ events: [DiagnosticEvent]) -> Int {
        events.reduce(0) { partial, event in
            partial + ((try? encoder.encode(event).count) ?? 0) + 1
        }
    }

    private func loadEvents() throws -> [DiagnosticEvent] {
        guard fileManager.fileExists(atPath: eventsFileURL.path) else { return [] }
        let data = try Data(contentsOf: eventsFileURL)
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return [] }
        return text
            .split(separator: "\n")
            .compactMap { line -> DiagnosticEvent? in
                guard let data = String(line).data(using: .utf8) else { return nil }
                return try? decoder.decode(DiagnosticEvent.self, from: data)
            }
    }

    private func persist(_ events: [DiagnosticEvent]) throws {
        try ensureDirectory()
        let data = try events.reduce(into: Data()) { partial, event in
            partial.append(try encoder.encode(event))
            partial.append(0x0A)
        }
        try data.write(to: eventsFileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try setFileProtection()
    }

    private func ensureDirectory() throws {
        let directory = eventsFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: directory.path
        )
    }

    private func setFileProtection() throws {
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: eventsFileURL.path
        )
        lastAppliedFileProtection = .completeUntilFirstUserAuthentication
    }

    private func completeLegacyMigration() {
        userDefaults.set(true, forKey: Self.migrationMarkerKey)
        userDefaults.removeObject(forKey: DefaultsKey.debugLogEntries.rawValue)
    }
}
