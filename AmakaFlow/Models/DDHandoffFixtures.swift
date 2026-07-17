//
//  DDHandoffFixtures.swift
//  AmakaFlow
//
//  Gates Daily Driver handoff sample data behind DEBUG / UI-test fixtures.
//

import Foundation

enum DDHandoffFixtures {
    /// When true, Profile/Today/Settings may show design-handoff fixture rows for verification.
    static var isEnabled: Bool {
        #if DEBUG
        return UITestEnvironment.shared.useFixtures
            || ProcessInfo.processInfo.environment["AF_USE_HANDOFF_FIXTURES"] == "1"
        #else
        return false
        #endif
    }
}
