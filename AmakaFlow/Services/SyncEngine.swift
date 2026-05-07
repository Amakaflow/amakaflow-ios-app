//
//  SyncEngine.swift
//  AmakaFlow
//

import Foundation
import Sentry

enum SyncEngineError: LocalizedError {
    case missingHandler

    var errorDescription: String? {
        switch self {
        case .missingHandler:
            return "SyncEngine has no upstream sync handler configured."
        }
    }
}

actor SyncEngine {
    @MainActor static let shared = SyncEngine()

    private let queueRepository: SyncQueueRepository
    private let maxAttempts: Int
    private let baseBackoff: TimeInterval
    private let syncHandler: (SyncQueueItem) async throws -> Void
    private let completedRetention: TimeInterval

    @MainActor
    init(
        queueRepository: SyncQueueRepository = SyncQueueRepository(),
        maxAttempts: Int = 5,
        baseBackoff: TimeInterval = 2,
        completedRetention: TimeInterval = 7 * 24 * 60 * 60,
        syncHandler: @escaping (SyncQueueItem) async throws -> Void = { _ in throw SyncEngineError.missingHandler }
    ) {
        self.queueRepository = queueRepository
        self.maxAttempts = maxAttempts
        self.baseBackoff = baseBackoff
        self.completedRetention = completedRetention
        self.syncHandler = syncHandler
    }

    func processPending(limit: Int = 25) async {
        do {
            let items = try await queueRepository.pending(limit: limit)
            for item in items {
                await process(item)
            }
        } catch {
            await DebugLogService.shared.log("Sync queue scan failed", details: error.localizedDescription)
        }
    }

    func summary() async throws -> SyncQueueSummary {
        try await queueRepository.summary()
    }

    private func process(_ item: SyncQueueItem) async {
        do {
            try await queueRepository.markInFlight(item.id)
        } catch {
            await DebugLogService.shared.log(
                "Sync queue mark-in-flight failed",
                details: error.localizedDescription,
                metadata: ["queueItemId": item.id]
            )
            return
        }

        do {
            try await syncHandler(item)
            try await queueRepository.markSynced(item.id)
            await cleanupCompletedItems()
        } catch {
            let syncError = error
            let nextAttempt = item.attemptCount + 1
            let retryAfter = backoffDelay(forAttempt: nextAttempt)
            do {
                try await queueRepository.markFailed(
                    item.id,
                    error: syncError.localizedDescription,
                    retryAfter: retryAfter,
                    poisonAfter: maxAttempts
                )
            } catch {
                await DebugLogService.shared.log(
                    "Sync queue failure persistence failed",
                    details: error.localizedDescription,
                    metadata: ["queueItemId": item.id]
                )
                return
            }

            if nextAttempt >= maxAttempts {
                SentrySDK.capture(message: "Sync queue item poisoned: \(item.resourceType)/\(item.resourceId) - \(syncError.localizedDescription)")
                await DebugLogService.shared.log(
                    "Sync queue item poisoned",
                    details: "\(item.resourceType)/\(item.resourceId): \(syncError.localizedDescription)",
                    metadata: ["source": "SyncEngine"]
                )
                await cleanupCompletedItems()
            }
        }
    }

    private func cleanupCompletedItems() async {
        do {
            _ = try await queueRepository.deleteCompleted(olderThan: completedRetention)
        } catch {
            await DebugLogService.shared.log("Sync queue cleanup failed", details: error.localizedDescription)
        }
    }

    private func backoffDelay(forAttempt attempt: Int) -> TimeInterval {
        let exponent = max(0, attempt - 1)
        let capped = min(exponent, 6)
        return baseBackoff * pow(2, Double(capped))
    }
}
