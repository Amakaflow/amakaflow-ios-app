//
//  FeatureFlags.swift
//  AmakaFlow
//
//  AMA-1588 / AMA-MVP-06 — single-source feature flag for MVP scope cut.
//
//  The MVP ships a narrow surface: Home (today's workout), Workouts
//  (this-week plan + execute), Pairing (Garmin), Settings, and a trimmed
//  More (History + essentials). Everything else is hidden behind
//  FeatureFlags.nonMvp until the willingness-to-pay test resolves.
//
//  To ship a non-MVP feature, flip this flag to `true` in a build /
//  scheme config — DO NOT delete the code. Everything stays in the repo
//  so we can re-enable it in one line when scope opens up.
//

import Foundation

/// Centralized feature flags for the AmakaFlow iOS app.
///
/// MVP scope = Home + Workouts + Pairing + Settings + minimal More.
/// All other surfaces are behind `nonMvp` until the 30-day willingness-to-pay
/// test resolves (see amakaflow-docs/concepts/Lean-Startup-Plan.md).
enum FeatureFlags {
    /// When `false` (the MVP default), all non-MVP surfaces are hidden
    /// from navigation entry points. The code remains in the app so we
    /// can re-enable it without a re-implementation.
    ///
    /// Override for development / internal builds by setting
    /// `AMAKAFLOW_NON_MVP=1` in the launch environment.
    static let nonMvp: Bool = {
        if let override = ProcessInfo.processInfo.environment["AMAKAFLOW_NON_MVP"] {
            return override == "1" || override.lowercased() == "true"
        }
        return false
    }()
}
