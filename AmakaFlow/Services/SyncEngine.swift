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
        // AMA-1823: stamp a fresh request_id on this attempt so the upstream
        // call (eventually `X-Request-ID`) and our local diagnostics
        // (Sentry breadcrumbs, DebugLogService) all share the same ID.
        // A retry generates a new UUID, so the column on the row reflects
        // the most recent attempt — earlier attempt IDs live in Sentry and
        // the BFF logs.
        let requestId = makeRequestId()
        var stampedItem = item
        stampedItem.requestId = requestId

        do {
            try await queueRepository.updateRequestId(item.id, requestId: requestId)
        } catch {
            await DebugLogService.shared.log(
                "Sync queue request_id persistence failed",
                details: error.localizedDescription,
                metadata: ["queueItemId": item.id, "request_id": requestId]
            )
            // Non-fatal: fall through with the in-memory stamped copy so the
            // attempt still propagates a request_id to the backend.
        }

        do {
            try await queueRepository.markInFlight(item.id)
        } catch {
            await DebugLogService.shared.log(
                "Sync queue mark-in-flight failed",
                details: error.localizedDescription,
                metadata: ["queueItemId": item.id, "request_id": requestId]
            )
            return
        }

        addSyncBreadcrumb(
            message: "sync attempt started",
            level: .info,
            item: stampedItem,
            requestId: requestId
        )

        do {
            try await syncHandler(stampedItem)
            try await queueRepository.markSynced(item.id)
            addSyncBreadcrumb(
                message: "sync attempt succeeded",
                level: .info,
                item: stampedItem,
                requestId: requestId
            )
            await cleanupCompletedItems()
        } catch {
            let syncError = error
            let nextAttempt = item.attemptCount + 1
            let retryAfter = backoffDelay(forAttempt: nextAttempt)
            addSyncBreadcrumb(
                message: "sync attempt failed",
                level: .warning,
                item: stampedItem,
                requestId: requestId,
                extra: ["error": syncError.localizedDescription]
            )
            await DebugLogService.shared.log(
                "Sync queue attempt failed",
                details: syncError.localizedDescription,
                metadata: [
                    "queueItemId": item.id,
                    "resourceType": item.resourceType,
                    "resourceId": item.resourceId,
                    "request_id": requestId,
                    "attempt": String(nextAttempt)
                ]
            )
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
                    metadata: ["queueItemId": item.id, "request_id": requestId]
                )
                return
            }

            if nextAttempt >= maxAttempts {
                SentrySDK.capture(message: "Sync queue item poisoned: \(item.resourceType)/\(item.resourceId) - \(syncError.localizedDescription)") { scope in
                    scope.setTag(value: requestId, key: "request_id")
                    scope.setTag(value: item.resourceType, key: "resource_type")
                    scope.setExtra(value: item.resourceId, key: "resource_id")
                }
                await DebugLogService.shared.log(
                    "Sync queue item poisoned",
                    details: "\(item.resourceType)/\(item.resourceId): \(syncError.localizedDescription)",
                    metadata: ["source": "SyncEngine", "request_id": requestId]
                )
                await cleanupCompletedItems()
            }
        }
    }

    // MARK: - Request ID + Breadcrumb helpers (AMA-1823)

    /// Overridable in tests; defaults to a fresh UUID string.
    nonisolated func makeRequestId() -> String {
        UUID().uuidString
    }

    nonisolated private func addSyncBreadcrumb(
        message: String,
        level: SentryLevel,
        item: SyncQueueItem,
        requestId: String,
        extra: [String: String] = [:]
    ) {
        let crumb = Breadcrumb(level: level, category: "sync_queue")
        crumb.message = message
        var data: [String: Any] = [
            "request_id": requestId,
            "queue_item_id": item.id,
            "resource_type": item.resourceType,
            "resource_id": item.resourceId,
            "op": item.op,
            "attempt": item.attemptCount + 1
        ]
        for (key, value) in extra {
            data[key] = value
        }
        crumb.data = data
        SentrySDK.addBreadcrumb(crumb)
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
