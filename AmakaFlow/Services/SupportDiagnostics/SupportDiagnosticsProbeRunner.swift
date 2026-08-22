import Foundation

nonisolated struct SupportDiagnosticsProbeRunner: Sendable {
    private let probes: [any SupportDiagnosticsProbe]
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void

    init(
        probes: [any SupportDiagnosticsProbe],
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.probes = probes
        self.now = now
        self.sleep = sleep
    }

    func run() async -> SupportDiagnosticsSnapshot {
        let generatedAt = now()
        let results = await withTaskGroup(of: IndexedProbeResult.self) { group in
            for (index, probe) in probes.enumerated() {
                group.addTask {
                    await IndexedProbeResult(
                        index: index,
                        result: execute(probe: probe, sleep: sleep)
                    )
                }
            }

            var collected: [IndexedProbeResult] = []
            for await indexedResult in group {
                collected.append(indexedResult)
            }

            return collected
                .sorted { $0.index < $1.index }
                .map(\.result)
        }
        return SupportDiagnosticsSnapshot(generatedAt: generatedAt, results: results)
    }
}

private nonisolated struct IndexedProbeResult: Sendable {
    let index: Int
    let result: SupportDiagnosticsProbeResult
}

private nonisolated enum TimedProbeOutcome: Sendable {
    case fields([SupportDiagnosticsDisplayField])
    case unavailable(SupportDiagnosticsSafeErrorCode, String?)
}

private nonisolated func execute(
    probe: any SupportDiagnosticsProbe,
    sleep: @escaping @Sendable (Duration) async throws -> Void
) async -> SupportDiagnosticsProbeResult {
    let outcome = await withTaskGroup(of: TimedProbeOutcome.self, returning: TimedProbeOutcome.self) { group in
        group.addTask {
            do {
                return .fields(try await probe.run())
            } catch let error as SupportDiagnosticsProbeError {
                return .unavailable(error.code, error.correlationID)
            } catch {
                return .unavailable(.probeFailed, nil)
            }
        }
        group.addTask {
            do {
                try await sleep(probe.timeout)
            } catch {
                return .unavailable(.probeFailed, nil)
            }
            return .unavailable(.probeTimedOut, nil)
        }

        let outcome = await group.next() ?? .unavailable(.probeFailed, nil)
        group.cancelAll()
        return outcome
    }

    switch outcome {
    case .fields(let fields):
        return SupportDiagnosticsProbeResult(
            id: probe.id,
            title: probe.title,
            availability: .available(fields: fields)
        )
    case .unavailable(let errorCode, let correlationID):
        return SupportDiagnosticsProbeResult(
            id: probe.id,
            title: probe.title,
            availability: .unavailable(errorCode: errorCode, correlationID: correlationID)
        )
    }
}
