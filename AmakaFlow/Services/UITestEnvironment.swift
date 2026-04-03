//
//  UITestEnvironment.swift
//  AmakaFlow
//
//  Centralized UITEST environment variable handling
//

import Foundation

/// Centralized management of UITEST environment variables
class UITestEnvironment {
    static let shared = UITestEnvironment()
    
    private init() {}
    
    // MARK: - Environment Variable Access
    
    /// Check if login bypass is enabled
    var isLoginBypassEnabled: Bool {
        ProcessInfo.processInfo.environment["UITEST_LOGIN_BYPASS"]?.lowercased() == "true"
    }
    
    /// Get simulation speed multiplier (1.0 = normal, 2.0 = 2x speed, etc.)
    var simulationSpeed: Double {
        if let speedStr = ProcessInfo.processInfo.environment["UITEST_SIM_SPEED"],
           let speed = Double(speedStr), speed > 0 {
            return speed
        }
        return 1.0 // Default to normal speed
    }
    
    /// Check if fake watch connectivity should be used
    var useFakeWatchConnectivity: Bool {
        ProcessInfo.processInfo.environment["UITEST_FAKE_WATCH"]?.lowercased() == "true"
    }
    
    /// Check if Sentry should be disabled
    var isSentryDisabled: Bool {
        ProcessInfo.processInfo.environment["UITEST_DISABLE_SENTRY"]?.lowercased() == "true"
    }
    
    // MARK: - Utility Methods
    
    /// Get adjusted duration for animations/timers based on simulation speed
    func adjustedDuration(_ originalDuration: TimeInterval) -> TimeInterval {
        return originalDuration / simulationSpeed
    }
    
    /// Get adjusted delay for async operations
    func adjustedDelay(_ originalDelay: TimeInterval) -> TimeInterval {
        return originalDelay / simulationSpeed
    }
    
    /// Print current UITEST configuration for debugging
    func printConfiguration() {
        #if DEBUG
        print("[UITestEnvironment] Configuration:")
        print("  - Login Bypass: \(isLoginBypassEnabled)")
        print("  - Simulation Speed: \(simulationSpeed)x")
        print("  - Fake Watch: \(useFakeWatchConnectivity)")
        print("  - Sentry Disabled: \(isSentryDisabled)")
        #endif
    }
}