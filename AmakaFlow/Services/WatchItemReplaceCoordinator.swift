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
/// (or fails if `UITEST_WATCHITEM_REPLACE_FAIL=true`).
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
        let envDelayMs = UITestEnvironment.value(for: "UITEST_WATCHITEM_REPLACE_DELAY_MS")
            .flatMap(UInt64.init)
        self.delayNanoseconds = delayNanoseconds
            ?? ((envDelayMs ?? 900) * 1_000_000)
        self.shouldFail = shouldFail
            ?? UITestEnvironment.isTruthy("UITEST_WATCHITEM_REPLACE_FAIL")
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
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            if shouldFail {
                return .failure(.underlying("Demo replace failed (UITEST_WATCHITEM_REPLACE_FAIL)."))
            }
            return .success(())
        }

        // Live path lands in Task 4; until then surface an honest error so we
        // never claim success without WorkoutKit / Garmin work.
        return .failure(.underlying("Live replace is not wired yet — enable AMA2375_DEMO for Simulator."))
    }
}
