import Foundation

nonisolated struct SupportDiagnosticsProbeRunner: Sendable {
    private let probes: [any SupportDiagnosticsProbe]
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    private let correlationIDProvider: @Sendable () -> String?

    init(
        probes: [any SupportDiagnosticsProbe],
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        },
        correlationIDProvider: @escaping @Sendable () -> String? = {
            SupportDiagnosticsRuntimeState.shared.safeCorrelationID()
        }
    ) {
        self.probes = probes
        self.now = now
        self.sleep = sleep
        self.correlationIDProvider = correlationIDProvider
    }

    func run() async -> SupportDiagnosticsSnapshot {
        let generatedAt = now()
        let results = await withTaskGroup(of: IndexedProbeResult.self) { group in
            for (index, probe) in probes.enumerated() {
                group.addTask {
                    await IndexedProbeResult(
                        index: index,
                        result: execute(
                            probe: probe,
                            sleep: sleep,
                            correlationIDProvider: correlationIDProvider
                        )
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
    sleep: @escaping @Sendable (Duration) async throws -> Void,
    correlationIDProvider: @escaping @Sendable () -> String?
) async -> SupportDiagnosticsProbeResult {
    let outcome = await withCheckedContinuation { continuation in
        let race = ProbeRace(continuation: continuation)
        let probeTask = Task {
            do {
                await race.resolve(.fields(try await probe.run()))
            } catch let error as SupportDiagnosticsProbeError {
                await race.resolve(.unavailable(error.code, error.correlationID ?? correlationIDProvider()))
            } catch {
                await race.resolve(.unavailable(.probeFailed, correlationIDProvider()))
            }
        }
        let timeoutTask = Task {
            do {
                try await sleep(probe.timeout)
            } catch {
                await race.resolve(.unavailable(.probeFailed, correlationIDProvider()))
                return
            }
            await race.resolve(.unavailable(.probeTimedOut, correlationIDProvider()))
        }
        Task {
            await race.installTasks([probeTask, timeoutTask])
        }
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

private actor ProbeRace {
    private var didResolve = false
    private var tasks: [Task<Void, Never>] = []
    private let continuation: CheckedContinuation<TimedProbeOutcome, Never>

    init(continuation: CheckedContinuation<TimedProbeOutcome, Never>) {
        self.continuation = continuation
    }

    func installTasks(_ tasks: [Task<Void, Never>]) {
        if didResolve {
            tasks.forEach { $0.cancel() }
        } else {
            self.tasks = tasks
        }
    }

    func resolve(_ outcome: TimedProbeOutcome) {
        guard !didResolve else { return }
        didResolve = true
        continuation.resume(returning: outcome)
        tasks.forEach { $0.cancel() }
        tasks = []
    }
}
