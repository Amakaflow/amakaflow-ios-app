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
/// **2026-05-22 status update (AMA-1875):** Default flipped to `true` for v1.
///
/// The original `false` default (AMA-1588) was the right call when v1 was
/// going to ship paid at $9.99 and the narrow MVP was a willingness-to-pay
/// experiment. The 2026-05-22 decision to ship v1 FREE (see
/// docs/architecture/PRODUCTION_READINESS.md gap #2) inverted the calculus —
/// hiding features now hurts retention, since users can't see the value
/// they'd be retaining for. The TestFlight tap-test on build 103 surfaced
/// "the app looks barren" as the #1 first-impression complaint.
///
/// All non-MVP surfaces (Sources, Programs, Readiness History, Fatigue
/// Advisor, Bulk Import, Log Food) are now exposed by default.
///
/// To re-hide during local development (e.g., to test the MVP cut), set
/// `AMAKAFLOW_NON_MVP=0` in the launch environment.
enum FeatureFlags {
    /// Controls the multi-week Program Wizard entry points.
    ///
    /// Default: `false`. AMA-2096 Phase 2 repointed the wizard to the mobile-bff
    /// SSE program pipeline (design → generate for review, then explicit
    /// save/schedule), but those `/v1/programs/*/stream` routes are not deployed
    /// to staging yet — shipping the wizard ON before then would re-expose a
    /// broken CTA (the 405 dead-button Phase 1 fixed). Keep OFF until the
    /// mobile-bff deploy is live + the flow is verified, then flip the default
    /// to `true`. Set env `AMAKAFLOW_PROGRAM_WIZARD=1` to enable for local/QA.
    static let programWizardEnabled: Bool = {
        if let override = ProcessInfo.processInfo.environment["AMAKAFLOW_PROGRAM_WIZARD"] {
            return override == "1" || override.lowercased() == "true"
        }
        return false
    }()

    /// Controls visibility of non-core feature surfaces.
    ///
    /// Default: `true` (all surfaces visible) per the 2026-05-22 v1 plan.
    ///
    /// Override via env var `AMAKAFLOW_NON_MVP`:
    ///   - `0` / `false` → hide non-MVP surfaces (legacy MVP cut)
    ///   - `1` / `true`  → show non-MVP surfaces (current default)
    static let nonMvp: Bool = {
        if let override = ProcessInfo.processInfo.environment["AMAKAFLOW_NON_MVP"] {
            return override == "1" || override.lowercased() == "true"
        }
        return true
    }()
}
