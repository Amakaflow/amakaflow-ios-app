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
    static let teachCTAAccessibilityID = "af_actuals_connect_cta"

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
    /// Apple Health after deny / prompt-with-no-grant evidence — opens Settings.
    static let openHealthSettingsButton = "Open Settings"
    static let appleHealthSettingsAccessibilityID = "af_actuals_apple_settings"

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

    // MARK: - Map-to-plan (screens-actuals.jsx SYMapScreen + Map v2 capture)

    static let mapAskTitle = "Which workout was this?"
    static let mapAskBody =
        "Mapping attaches this run to the plan it was — nothing is duplicated, and Progress counts it once."
    static let mapAskBodyNoMatch =
        "Nothing in your library looks close enough — build what you did, or match a workout below."
    static let mapCaptureSectionHeader = "NOT IN YOUR LIBRARY — CAPTURE IT"
    static let mapCaptureBuildTitle = "Build what you did"
    static let mapCaptureBuildSub = "SAME BUILDER · SAVES AS THIS SESSION'S ACTUALS"
    static let mapCapturePhotoTitle = "From a photo"
    static let mapCapturePhotoSub = "CLASS WHITEBOARD → DRAFT → MATCH"
    static let mapOrMatchHeader = "OR MATCH A LIBRARY WORKOUT"
    static let mapBestMatchesHeader = "BEST MATCHES — SAME DAY, SAME SHAPE"
    static let mapSearchAllCTA = "Search all workouts…"
    static let mapKeepAsIsCTA = "It was just a run — keep as is"
    static let mapKeepAsIsAccessibilityID = "af_actuals_map_keep_as_is"
    static let mapCaptureBuildAccessibilityID = "af_actuals_map_capture_build"
    static let mapCapturePhotoAccessibilityID = "af_actuals_map_capture_photo"

    static func mapCandidateAccessibilityID(_ index: Int) -> String {
        "af_actuals_map_candidate_\(index)"
    }

    static func mapKeepAsNamedCTA(title: String) -> String {
        "Keep as '\(title)' — no detail needed"
    }

    // MARK: - Capture builder / photo (Map v2)

    static let captureBuilderTitle = "What did the class do?"
    static let captureBuilderSubhead =
        "Pick a shape and we set the structure — or start blank and let it emerge."
    static let captureBuilderDoneCTA = "Done — save it"
    static let captureBannerTitle = "FILLING IN WHAT YOU DID"
    static let capturePhotoTitle = "From a photo"
    static let capturePhotoChooseTitle = "Choose photo"
    static let capturePhotoChooseSub = "Class whiteboard → editable draft"
    static let capturePhotoHonesty =
        "We send the image to the import service — you can edit the result before saving."

    // MARK: - Match-save (Map v2)

    static let matchSaveTitle = "Save — this is what you did"
    static let matchSaveYouBuilt = "YOU BUILT"
    static let matchSaveNameLabel = "SESSION NAME"
    static let matchSaveNamePlaceholder = "Name this session"
    static let matchSaveNameRequired = "Give this session a name"
    static let matchSaveNameFieldID = "af_actuals_match_save_name"
    static let captureNameRequiredToast = "Name this workout first"
    static let matchSaveBody =
        "THIS BECOMES THE SESSION'S DETAIL — DEVICE METRICS + YOUR BLOCKS, COUNTED ONCE. RPE COMES NEXT, THEN IT'S VERIFIED."
    static let matchSaveLibraryTitle = "Also save to Library"
    static let matchSaveLibrarySub = "DO IT AGAIN ANY TIME · SEND IT TO A WATCH · SOURCE: BUILT BY YOU"
    static let matchSaveLibraryOffNote = "Logs the session only — nothing added to your Library."
    static let matchSaveCTAWithLibrary = "Save session + add to Library"
    static let matchSaveCTASessionOnly = "Save session"
    static let matchSaveFooter = "Next: how hard was it? (RPE) — then the session shows Verified ✓"
    static let matchSaveToastMatched = "Session matched"
    static let matchSaveToastMatchedSub = "Attached to this finished session — counted once"
    static let matchSaveLibraryFailed = "Library save failed — fix and retry, or turn off Library."
    static let fillInSaveFailedTitle = "Couldn't save session"
    static let oauthAuthorizeFailed =
        "Couldn't complete authorization. Check the connection and try again."
    static let matchSaveAccessibilityID = "af_actuals_match_save"
    static let matchSaveLibraryToggleID = "af_actuals_match_save_library"
    static let matchSaveCTAAccessibilityID = "af_actuals_match_save_cta"

    static func captureBannerLine(for activity: ActualsUnmappedActivity) -> String {
        ActualsCaptureContext.bannerDetail(for: activity)
    }

    // MARK: - Fill-in actuals (screens-actuals.jsx SYActualsScreen)

    static let fillInTitle = "What you actually did"
    static let fillInBackLabel = "Activity"
    static let fillInAllAsPlannedCTA = "✓ All as planned"
    static let fillInAsPlannedSegment = "✓ As planned"
    static let fillInAdjustSegment = "Adjust"
    static let fillInRPEHeader = "HOW HARD WAS IT? · RPE"
    static let fillInFooterNote =
        "Actuals update your history — next time this plan shows what you really lifted, not what was written."
    static let fillInAllAsPlannedToast = "All confirmed as planned — adjust any if needed"
    static let fillInSavedToast = "Session verified"
    static let fillInSavedToastSub = "Actuals saved — ghosts update next time"
    static let fillInAllAsPlannedAccessibilityID = "af_actuals_all_asplanned"
    static let fillInSaveAccessibilityID = "af_actuals_save"
    static let verifiedTimelineCTA = "Verified ✓"

    static func fillInRPEAccessibilityID(_ value: Int) -> String {
        "af_actuals_rpe_\(value)"
    }

    static func fillInPlannedLine(_ planned: ExerciseActualPlanned) -> String {
        "PLANNED · \(planned.displayLine)"
    }

    static func fillInPlannedGhostKg(_ kilograms: Double) -> String {
        let kgText = kilograms == floor(kilograms) ? "\(Int(kilograms))" : String(format: "%.1f", kilograms)
        return "PLANNED \(kgText)"
    }

    // MARK: - Verified + ghost feed (screens-actuals.jsx SYVerifiedScreen)

    static let verifiedHeadline = "Verified session"
    static let verifiedVsPlanHeader = "WHAT YOU DID · VS PLAN"
    static let verifiedAsPlannedDelta = "AS PLANNED"
    static let verifiedAdjustedDelta = "ADJUSTED"
    static let verifiedGhostFooter =
        "Next time you run this plan, the editor ghosts show your real last time."
    static let verifiedCalloutAccessibilityID = "af_actuals_verified_callout"
    static let verifiedCardAccessibilityID = "af_actuals_verified_card"

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
        ("Heart rate", "EFFORT — SHOWN ON YOUR SESSION CARDS"),
        ("Active energy", "CALORIES ON YOUR CARDS")
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

    /// Locked scope rows — upload is always false / struck-through.
    static func oauthScopes(for provider: ActualsSourceProvider) -> [ActualsOAuthScopeRow] {
        switch provider {
        case .strava:
            return [
                ActualsOAuthScopeRow(
                    granted: true,
                    title: "View data about your activities",
                    subtitle: "Runs, rides, workouts — including those synced from other apps"
                ),
                ActualsOAuthScopeRow(
                    granted: true,
                    title: "View your profile information",
                    subtitle: "Name and units only"
                ),
                ActualsOAuthScopeRow(
                    granted: false,
                    title: "Upload or edit your activities",
                    subtitle: oauthUploadNotRequested
                )
            ]
        case .garmin:
            return [
                ActualsOAuthScopeRow(
                    granted: true,
                    title: "View data about your activities",
                    subtitle: "Runs, rides, strength — after Garmin Connect syncs"
                ),
                ActualsOAuthScopeRow(
                    granted: true,
                    title: "View your profile information",
                    subtitle: "Name and units only"
                ),
                ActualsOAuthScopeRow(
                    granted: false,
                    title: "Upload or edit your activities",
                    subtitle: oauthGarminUploadNotRequested
                )
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

struct ActualsOAuthScopeRow: Equatable {
    let granted: Bool
    let title: String
    let subtitle: String
}

enum ActualsTeachCardVisibility {
    /// Teach card shows only when the user has never connected a source AND Today is empty.
    /// After the first connect it is gone forever (even if later disconnected).
    static func shouldShow(hasEverConnected: Bool, todayEmpty: Bool) -> Bool {
        !hasEverConnected && todayEmpty
    }
}
