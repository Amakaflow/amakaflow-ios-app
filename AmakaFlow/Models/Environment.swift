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

    var chatAPIURL: String {
        switch self {
        case .development: return "http://localhost:8005"
        case .staging: return "https://chat-api.staging.amakaflow.com"
        case .production: return "https://chat-api.amakaflow.com"
        }
    }

    var mcpAPIURL: String {
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
        case .development: return "http://localhost:8000"
        // Staging and production share the same Render deployment until a dedicated staging URL exists.
        case .staging: return "https://amakaflow-mcp.onrender.com"
        case .production: return "https://amakaflow-mcp.onrender.com"
        }
    }

    /// Clerk publishable key for the current environment.
    /// Values must be supplied by build settings/Info.plist or process environment, never hardcoded.
    var clerkPublishableKey: String {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["UITEST_CLERK_PUBLISHABLE_KEY"], !override.isEmpty {
            return override
        }
        if let override = ProcessInfo.processInfo.environment["CLERK_PUBLISHABLE_KEY"], !override.isEmpty {
            return override
        }
        // Unit test runner sets XCTestConfigurationFilePath; return a stub so tests don't crash on startup.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return "pk_test_stub_unit_tests_only"
        }
        #endif

        let keyName: String
        switch self {
        case .development, .staging:
            keyName = "CLERK_PUBLISHABLE_KEY_STAGING"
        case .production:
            keyName = "CLERK_PUBLISHABLE_KEY_PRODUCTION"
        }

        if let value = Bundle.main.object(forInfoDictionaryKey: keyName) as? String,
           !value.isEmpty, !value.hasPrefix("$(") {
            return value
        }

        if let value = ProcessInfo.processInfo.environment[keyName], !value.isEmpty {
            return value
        }

        preconditionFailure("Missing \(keyName). Provide the Clerk publishable key via build configuration or environment.")
    }


    var stravaAPIURL: String {
        switch self {
        case .development: return "http://localhost:8000"
        case .staging: return "https://strava-sync-api.staging.amakaflow.com"
        case .production: return "https://strava-sync-api.amakaflow.com"
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
