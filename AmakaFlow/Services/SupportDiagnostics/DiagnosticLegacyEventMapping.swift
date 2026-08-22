import Foundation

nonisolated struct DiagnosticLegacyEventMapping: Sendable {
    func category(for type: DebugLogType) -> DiagnosticEventCategory {
        switch type {
        case .apiError, .apiSuccess:
            return .api
        case .watchError, .watchEvent:
            return .watch
        case .completionError:
            return .completion
        case .networkError:
            return .network
        case .authError:
            return .auth
        case .general:
            return .general
        }
    }

    func severity(for type: DebugLogType) -> DiagnosticEventSeverity {
        switch type {
        case .apiSuccess, .watchEvent, .general:
            return .info
        case .networkError:
            return .warning
        case .apiError, .watchError, .completionError, .authError:
            return .error
        }
    }

    func stableEventName(for type: DebugLogType) -> String {
        switch type {
        case .apiError:
            return "api.request.failed"
        case .apiSuccess:
            return "api.request.succeeded"
        case .watchError:
            return "watch.error"
        case .watchEvent:
            return "watch.event"
        case .completionError:
            return "completion.failed"
        case .networkError:
            return "network.error"
        case .authError:
            return "auth.error"
        case .general:
            return "general.event"
        }
    }
}
