//
//  SyncEngine.swift
//  AmakaFlow
//

import Foundation
import Sentry

actor SyncEngine {
    @MainActor static let shared = SyncEngine()

    private let queueRepository: SyncQueueRepository
    private let maxAttempts: Int
    private let baseBackoff: TimeInterval
    private let syncHandler: (SyncQueueItem) async throws -> Void

    @MainActor
    init(
        queueRepository: SyncQueueRepository = SyncQueueRepository(),
        maxAttempts: Int = 5,
        baseBackoff: TimeInterval = 2,
        syncHandler: @escaping (SyncQueueItem) async throws -> Void = { _ in }
    ) {
        self.queueRepository = queueRepository
        self.maxAttempts = maxAttempts
        self.baseBackoff = baseBackoff
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
            try await syncHandler(item)
            try await queueRepository.markSynced(item.id)
        } catch {
            let nextAttempt = item.attemptCount + 1
            let retryAfter = backoffDelay(forAttempt: nextAttempt)
            try? await queueRepository.markFailed(item.id, error: error.localizedDescription, retryAfter: retryAfter, poisonAfter: maxAttempts)

            if nextAttempt >= maxAttempts {
                SentrySDK.capture(message: "Sync queue item poisoned: \(item.resourceType)/\(item.resourceId) - \(error.localizedDescription)")
                await DebugLogService.shared.log(
                    "Sync queue item poisoned",
                    details: "\(item.resourceType)/\(item.resourceId): \(error.localizedDescription)",
                    metadata: ["source": "SyncEngine"]
                )
            }
        }
    }

    private func backoffDelay(forAttempt attempt: Int) -> TimeInterval {
        let exponent = max(0, attempt - 1)
        let capped = min(exponent, 6)
        return baseBackoff * pow(2, Double(capped))
    }
}
