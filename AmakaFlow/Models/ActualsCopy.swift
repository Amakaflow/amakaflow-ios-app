//
//  ActualsCopy.swift
//  AmakaFlow
//
//  AMA-2387: locked copy for completed-workout sync & fill-in actuals.
//

import Foundation

enum ActualsCopy {
    // MARK: - Teach card (Today empty + never connected)

    static let teachHeadline = "Your finished workouts can land here by themselves"
    static let teachSubhead =
        "Connect Apple Health, Garmin or Strava — sessions show up minutes after you finish, ready to log."
    static let teachCTA = "Connect a source"
    static let teachTrustLine = "~30 SECONDS · READ-ONLY · UNPLUG ANYTIME"
    static let teachManualAlt = "or log a session manually with ＋"
    static let teachCardAccessibilityID = "af_actuals_teach_card"

    // MARK: - Connect sources

    static let connectTitle = "Pull your training in"
    static let connectSubhead =
        "Finished sessions land on Today by themselves — then you fill in what you actually did. We only read; we never post."
    static let connectDedupeFooter =
        "SAME WORKOUT FROM TWO SOURCES? WE KEEP ONE — WATCH BEATS PHONE, RICHER DATA WINS. NOTHING COUNTS TWICE."

    static func sourceOneLiner(_ provider: ActualsSourceProvider) -> String {
        switch provider {
        case .appleHealth:
            return "WORKOUTS FROM YOUR APPLE WATCH · HEART RATE + CALORIES"
        case .garmin:
            return "RUNS + STRENGTH · PULLED AUTOMATICALLY AFTER SYNC"
        case .strava:
            return "EVERYTHING YOU RECORD THERE · INCL. OTHER APPS VIA STRAVA"
        }
    }

    static func sourceDisplayName(_ provider: ActualsSourceProvider) -> String {
        switch provider {
        case .appleHealth: return "Apple Health"
        case .garmin: return "Garmin"
        case .strava: return "Strava"
        }
    }

    static let connectedBadge = "CONNECTED ✓"
    /// Freshly linked this session (screens-actuals3.jsx SYLinkedScreen).
    static let linkedJustNowBadge = "LINKED ✓ JUST NOW"
    static let connectButton = "Connect"

    // MARK: - Sync / backfill (ACTUALS.md §5)

    static let syncPullingSub = "PULLING YOUR LAST 30 DAYS…"
    static let syncCounterAccessibilityID = "af_actuals_sync_counter"

    // MARK: - Merge ask / merged detail (screens-actuals2.jsx)

    static let mergeAskTitle = "Same session?"
    static let mergeAskBody =
        "These two overlap — started close together, similar distance. We don't merge without you when it's not certain."
    static let mergeAskConfirmCTA = "Merge — it's one session"
    static let mergeAskKeepBothCTA = "Keep both"
    static let mergeAskFooter =
        "CERTAIN DUPLICATES (SAME WINDOW ± 2 MIN, SAME SHAPE) MERGE AUTOMATICALLY — YOU'LL SEE “MERGED · N SOURCES” ON THE CARD."
    static let mergeAskAccessibilityID = "af_actuals_merge_ask"
    static let mergeAskMergeAccessibilityID = "af_actuals_merge_ask_merge"
    static let mergeAskKeepAccessibilityID = "af_actuals_merge_ask_keep"

    static let mergedHeadline = "One session, three recordings"
    static let mergedBody =
        "Apple Watch, Garmin and Strava all caught this. We merged them — it counts once, and each stat comes from whoever measured it best."
    static let mergedRecordingsHeader = "THE THREE RECORDINGS — WHAT EACH CONTRIBUTED"
    static let mergedSplitCTA = "Not the same? Split"
    static let mergedFillInCTA = "Fill in actuals ›"
    static let mergedSplitAccessibilityID = "af_actuals_merged_split"

    static func recordingRoleLabel(_ role: ActualsRecordingRole, detail: String) -> String {
        switch role {
        case .primary: return "PRIMARY · \(detail)"
        case .attached: return "ATTACHED · \(detail)"
        case .hidden: return "DUPLICATE · HIDDEN — NOTHING COUNTED TWICE"
        }
    }

    // MARK: - Map-to-plan (screens-actuals.jsx SYMapScreen)

    static let mapAskTitle = "Which workout was this?"
    static let mapAskBody =
        "Mapping attaches this run to the plan it was — nothing is duplicated, and Progress counts it once."
    static let mapBestMatchesHeader = "BEST MATCHES — SAME DAY, SAME SHAPE"
    static let mapSearchAllCTA = "Search all workouts…"
    static let mapKeepAsIsCTA = "It was just a run — keep as is"
    static let mapKeepAsIsAccessibilityID = "af_actuals_map_keep_as_is"

    static func mapCandidateAccessibilityID(_ index: Int) -> String {
        "af_actuals_map_candidate_\(index)"
    }

    // MARK: - Apple Health primer (screens-actuals3.jsx SYAppleFlowScreen)

    static let appleHealthTitle = "Apple Health"
    static let appleHealthPrimerLeadPrefix = "iOS will ask next. We request "
    static let appleHealthPrimerLeadEmphasis = "read only"
    static let appleHealthPrimerLeadSuffix = " — three things:"
    static let appleHealthPrimerLead =
        "iOS will ask next. We request read only — three things:"

    /// Locked WHY tags — title + mono reason (exact JSX).
    static let appleHealthReadTypes: [(title: String, why: String)] = [
        ("Workouts", "THE SESSIONS THEMSELVES"),
        ("Heart rate", "EFFORT — FEEDS RPE SUGGESTIONS"),
        ("Active energy", "CALORIES ON YOUR CARDS"),
    ]

    static let appleHealthTurnOnAllCoach =
        "Apple's sheet starts with everything off — tap “Turn On All”, then Allow."
    static let appleHealthContinueCTA = "Continue"
    static let appleHealthPrimerAccessibilityID = "af_actuals_apple_primer"
    static let appleHealthContinueAccessibilityID = "af_actuals_apple_continue"

    // MARK: - Strava / Garmin OAuth scope (screens-actuals3.jsx SYStravaFlowScreen)

    static let oauthAuthorizeCTA = "Authorize"
    static let oauthCancelCTA = "Cancel"
    static let oauthUploadNotRequested = "NOT REQUESTED — AmakaFlow never posts to Strava"
    static let oauthGarminUploadNotRequested = "NOT REQUESTED — AmakaFlow never posts to Garmin"
    static let oauthStravaHostChrome = "🔒 strava.com/oauth/authorize"
    static let oauthGarminHostChrome = "🔒 connect.garmin.com/oauthConfirm"
    static let oauthScopeAccessibilityID = "af_actuals_oauth_scope"
    static let oauthAuthorizeAccessibilityID = "af_actuals_oauth_authorize"
    static let oauthCancelAccessibilityID = "af_actuals_oauth_cancel"

    /// Locked scope rows — `(granted, title, subtitle)`. Upload is always false / struck-through.
    static func oauthScopes(for provider: ActualsSourceProvider) -> [(granted: Bool, title: String, subtitle: String)] {
        switch provider {
        case .strava:
            return [
                (true, "View data about your activities",
                 "Runs, rides, workouts — including those synced from other apps"),
                (true, "View your profile information", "Name and units only"),
                (false, "Upload or edit your activities", oauthUploadNotRequested),
            ]
        case .garmin:
            return [
                (true, "View data about your activities",
                 "Runs, rides, strength — after Garmin Connect syncs"),
                (true, "View your profile information", "Name and units only"),
                (false, "Upload or edit your activities", oauthGarminUploadNotRequested),
            ]
        case .appleHealth:
            return []
        }
    }

    static func oauthHostChrome(for provider: ActualsSourceProvider) -> String {
        switch provider {
        case .strava: return oauthStravaHostChrome
        case .garmin: return oauthGarminHostChrome
        case .appleHealth: return ""
        }
    }

    static func oauthAuthorizeHeadline(for provider: ActualsSourceProvider) -> String {
        "Authorize AmakaFlow to connect to \(sourceDisplayName(provider))"
    }
}

enum ActualsTeachCardVisibility {
    /// Teach card shows only when the user has never connected a source AND Today is empty.
    /// After the first connect it is gone forever (even if later disconnected).
    static func shouldShow(hasEverConnected: Bool, todayEmpty: Bool) -> Bool {
        !hasEverConnected && todayEmpty
    }
}
