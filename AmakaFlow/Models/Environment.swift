import Foundation

enum AppEnvironment: String, CaseIterable {
    case development
    case staging
    case production

    private static let environmentKey = "app_environment"

    /// Get or set the current environment. Defaults to staging for debug builds, production for release.
    static var current: AppEnvironment {
        get {
            // E2E Test override (AMA-232) - check launch environment first
            #if DEBUG
            if let testEnv = ProcessInfo.processInfo.environment["UITEST_ENVIRONMENT"],
               let env = AppEnvironment(rawValue: testEnv) {
                return env
            }
            if let testEnv = ProcessInfo.processInfo.environment["TEST_ENVIRONMENT"],
               let env = AppEnvironment(rawValue: testEnv) {
                return env
            }
            #endif

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
        // Allow override via UITEST_API_BASE_URL / TEST_API_BASE_URL for E2E testing
        #if DEBUG
        if let testBaseURL = ProcessInfo.processInfo.environment["UITEST_API_BASE_URL"],
           !testBaseURL.isEmpty {
            return testBaseURL
        }
        if let testBaseURL = ProcessInfo.processInfo.environment["TEST_API_BASE_URL"],
           !testBaseURL.isEmpty {
            return testBaseURL
        }
        #endif

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
        // Show custom API URL hostname when using UITEST_API_BASE_URL / TEST_API_BASE_URL override
        #if DEBUG
        let testBaseURL = ProcessInfo.processInfo.environment["UITEST_API_BASE_URL"]
            ?? ProcessInfo.processInfo.environment["TEST_API_BASE_URL"]
        if let testBaseURL, !testBaseURL.isEmpty,
           let url = URL(string: testBaseURL),
           let host = url.host {
            return host
        }
        #endif

        switch self {
        case .development: return "Development"
        case .staging: return "Staging"
        case .production: return "Production"
        }
    }
}
