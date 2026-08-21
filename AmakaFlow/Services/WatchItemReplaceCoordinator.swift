//
//  WatchItemReplaceCoordinator.swift
//  AmakaFlow
//
//  AMA-2386: Replace orchestration — demo delay or live Apple/Garmin seams.
//

import Foundation

enum WatchItemDevice: String, Hashable, Sendable {
    case apple
    case garmin

    var isApple: Bool { self == .apple }
}

enum WatchItemReplaceError: LocalizedError, Equatable {
    case cancelled
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Replace cancelled."
        case .underlying(let message):
            return message
        }
    }
}

struct WatchItemReplaceRequest: Equatable, Sendable {
    let device: WatchItemDevice
    let workoutID: String
    let title: String
    /// Apple scheduled plan id (WorkoutKit); unused for Garmin.
    let applePlanID: String?
    /// Apple slot date components for same-slot reschedule.
    let appleDateComponents: DateComponents?
}

protocol WatchItemReplacing: Sendable {
    func replace(_ request: WatchItemReplaceRequest) async -> Result<Void, WatchItemReplaceError>
}

/// Demo / live hybrid. When watch-manager demo is on, sleeps then succeeds
/// (or fails if `AF_FAULT_WATCH_REPLACE_FAIL=true`).
struct WatchItemReplaceCoordinator: WatchItemReplacing {
    var delayNanoseconds: UInt64
    var shouldFail: Bool
    var isDemo: Bool

    init(
        delayNanoseconds: UInt64? = nil,
        shouldFail: Bool? = nil,
        isDemo: Bool? = nil
    ) {
        #if DEBUG
        let envDelayMs = LaunchConfig.active?.watchItemReplaceDelayMilliseconds
            .flatMap { UInt64(exactly: $0) }
        self.delayNanoseconds = delayNanoseconds
            ?? ((envDelayMs ?? 900) * 1_000_000)
        self.shouldFail = shouldFail
            ?? (LaunchConfig.active?.watchItemReplaceFails == true)
        self.isDemo = isDemo ?? OnYourWatchesDemoSupport.isEnabled
        #else
        self.delayNanoseconds = delayNanoseconds ?? 0
        self.shouldFail = shouldFail ?? false
        self.isDemo = isDemo ?? false
        #endif
    }

    func replace(_ request: WatchItemReplaceRequest) async -> Result<Void, WatchItemReplaceError> {
        if isDemo {
            if delayNanoseconds > 0 {
                do {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                } catch is CancellationError {
                    return .failure(.cancelled)
                } catch {
                    return .failure(.underlying(error.localizedDescription))
                }
            }
            if Task.isCancelled { return .failure(.cancelled) }
            if shouldFail {
                return .failure(.underlying("Demo replace failed (AF_FAULT_WATCH_REPLACE_FAIL)."))
            }
            return .success(())
        }

        // Live Apple same-slot / Garmin id-stable replace is a follow-up.
        // Sheet CTA is demo-gated so users never hit this path in product UI.
        return .failure(.underlying("Live replace is not wired yet — enable AF_DEMO_WATCH_MANAGER for Simulator."))
    }
}
