import Foundation

enum AppEnvironment: String, CaseIterable {
    case development
    case staging
    case production

    private static let environmentKey = "app_environment"

    /// Get or set the current environment. Defaults to staging for debug builds, production for release.
    static var current: AppEnvironment {
        get {
            // Check if user has manually set an environment
            if let savedEnv = UserDefaults.standard.string(forKey: environmentKey),
               let env = AppEnvironment(rawValue: savedEnv) {
                return env
            }
            // Default based on build configuration
            #if DEBUG
            return .staging
            #else
            return .production
            #endif
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: environmentKey)
        }
    }

    /// Reset to default environment based on build configuration
    static func resetToDefault() {
        UserDefaults.standard.removeObject(forKey: environmentKey)
    }

    var mapperAPIURL: String {
        switch self {
        case .development: return "http://localhost:8001"
        case .staging: return "https://mapper-api.staging.amakaflow.com"
        case .production: return "https://mapper-api.amakaflow.com"
        }
    }

    var ingestorAPIURL: String {
        switch self {
        case .development: return "http://localhost:8004"
        case .staging: return "https://workout-ingestor-api.staging.amakaflow.com"
        case .production: return "https://workout-ingestor-api.amakaflow.com"
        }
    }

    var calendarAPIURL: String {
        switch self {
        case .development: return "http://localhost:8003"
        case .staging: return "https://calendar-api.staging.amakaflow.com"
        case .production: return "https://calendar-api.amakaflow.com"
        }
    }

    var displayName: String {
        switch self {
        case .development: return "Development"
        case .staging: return "Staging"
        case .production: return "Production"
        }
    }
}
