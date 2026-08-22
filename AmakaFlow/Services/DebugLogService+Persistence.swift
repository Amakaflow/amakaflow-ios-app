import Combine
import Foundation

extension DebugLogService {
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

    func diagnosticEventsForCurrentAccount() async throws -> [DiagnosticEvent] {
        let accountIdentifier = accountIdentifierProvider()
        guard let accountHash = redactor.hashAccountIdentifier(accountIdentifier) else {
            if currentAccountHash != nil {
                accountIdentifierDidChange(nil)
            }
            await writeTail?.value
            await migrationTask?.value
            await accountLoadTask?.value
            return []
        }

        if currentAccountHash != accountHash {
            accountIdentifierDidChange(accountIdentifier)
        }

        await writeTail?.value
        await migrationTask?.value
        await accountLoadTask?.value
        let latestAccountIdentifier = accountIdentifierProvider()
        guard redactor.hashAccountIdentifier(latestAccountIdentifier) == accountHash else {
            accountIdentifierDidChange(latestAccountIdentifier)
            return []
        }
        guard currentAccountHash == accountHash else { return [] }
        let events = try await diagnosticSnapshotReader(.account(accountHash))
        let postSnapshotAccountIdentifier = accountIdentifierProvider()
        guard redactor.hashAccountIdentifier(postSnapshotAccountIdentifier) == accountHash else {
            accountIdentifierDidChange(postSnapshotAccountIdentifier)
            return []
        }
        guard currentAccountHash == accountHash else {
            accountIdentifierDidChange(postSnapshotAccountIdentifier)
            return []
        }
        return events
    }

    func addEvent(_ event: DiagnosticEvent) {
        hasLocalMutation = true
        let entry = event.projectedDebugLogEntry
        if eventBelongsToCurrentAccount(event) {
            entries.insert(entry, at: 0)
        }

        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }

        enqueueWrite { [store] in
            try await store.append(event)
        }

        // Print only the already-redacted projection for local Xcode debugging.
        print("[DebugLog] \(entry.type.rawValue): \(entry.title) - \(entry.details)")
    }

    func enqueueWrite(_ operation: @escaping @Sendable () async throws -> Void) {
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

    func bindAccountState() {
        accountStateCancellable = accountIdentifierPublisher()
            .sink { [weak self] accountIdentifier in
                self?.accountIdentifierDidChange(accountIdentifier)
            }
    }

    func accountIdentifierDidChange(_ accountIdentifier: String?) {
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

    func loadEntries(for accountHash: String, generation: Int) async {
        do {
            let loadedEntries = try await store.snapshot(.account(accountHash))
                .prefix(maxEntries)
                .map(\.projectedDebugLogEntry)
            guard generation == accountLoadGeneration,
                  currentAccountHash == accountHash,
                  !hasLocalMutation
            else { return }
            entries = loadedEntries
        } catch {
            print("[DebugLogService] Failed to reload diagnostic events")
            guard generation == accountLoadGeneration else { return }
            entries = []
        }
    }

    func eventBelongsToCurrentAccount(_ event: DiagnosticEvent) -> Bool {
        guard let currentAccountHash else { return false }
        return event.accountHash == currentAccountHash
    }
}
