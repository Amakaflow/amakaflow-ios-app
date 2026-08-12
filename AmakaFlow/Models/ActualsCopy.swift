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
        "On connect we pull your last 30 days, then new sessions land on Today by themselves — fill in what you actually did. Pull is read-only; optional Strava write-back is off until you enable it."
    static let reconnectButton = "Reconnect"
    static let verifiedMenuWriteStrava = "Write to Strava now"
    static let verifiedMenuWriteStravaSub =
        "PUSH TITLE + STRUCTURE WITH “— TRACKED WITH AMAKAFLOW”"
    static let connectDedupeFooter =
        "SAME WORKOUT FROM TWO SOURCES? WE KEEP ONE — WATCH BEATS PHONE, RICHER DATA WINS. NOTHING COUNTS TWICE."

    static func sourceOneLiner(_ provider: ActualsSourceProvider) -> String {
        switch provider {
        case .appleHealth:
            return "WORKOUTS FROM YOUR APPLE WATCH · HEART RATE + CALORIES"
        case .garmin:
            return "RUNS + STRENGTH · PULLED AUTOMATICALLY AFTER SYNC"
        case .strava:
            return "LAST 30 DAYS ON CONNECT · THEN NEW SESSIONS AS THEY LAND"
        }
    }

    /// Empty Today after a source is linked and today's sync returned nothing.
    /// Prefer `linkedEmptyToday(connected:)` so copy matches linked providers.
    static let linkedEmptyToday =
        "No Strava sessions for today — earlier days stay in Strava (we pulled the last 30 on connect)."

    /// Adaptive empty-day line from the sources the athlete actually linked.
    static func linkedEmptyToday(connected: Set<ActualsSourceProvider>) -> String {
        let ordered = Self.displayOrdered(connected)
        switch ordered.count {
        case 0:
            return "No sessions for today — connect a source to pull your last 30 days."
        case 1:
            let name = sourceDisplayName(ordered[0])
            return "No \(name) sessions for today — earlier days stay in \(name) (we pulled the last 30 on connect)."
        default:
            let list = Self.joinedDisplayNames(ordered)
            return "No sessions from \(list) for today — we pulled the last 30 days on connect."
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

    // MARK: - Map-to-plan (screens-sync2.jsx SZMapScreen — Map v3)

    static let mapAskTitle = "Which workout was this?"
    static let mapAskMono =
        "ATTACHES THE PLAN · COUNTS ONCE · NOTHING DUPLICATED"
    static let mapAskBody =
        "Mapping attaches this run to the plan it was — nothing is duplicated, and Progress counts it once."
    static let mapAskBodyNoMatch =
        "Nothing in your library looks close enough — build what you did, or match a workout below."
    static let mapCaptureSectionHeader = "NOT IN YOUR LIBRARY — CAPTURE IT"
    static let mapCaptureBuildTitle = "Build it"
    static let mapCaptureBuildSub = "SAME BUILDER"
    static let mapCapturePhotoTitle = "From a photo"
    static let mapCapturePhotoSub = "WHITEBOARD → DRAFT"
    static let mapOrMatchHeader = "OR MATCH A LIBRARY WORKOUT"
    static let mapBestMatchesHeader = "BEST MATCHES — SAME DAY, SAME SHAPE"
    static let mapSearchAllCTA = "Search all workouts"
    static let mapKeepAsIsCTA = "It was just a run — verify as-is"
    static let mapKeepAsIsAccessibilityID = "af_actuals_map_keep_as_is"
    static let mapPinnedCTAAccessibilityID = "af_actuals_map_pinned_cta"
    static let mapCaptureBuildAccessibilityID = "af_actuals_map_capture_build"
    static let mapCapturePhotoAccessibilityID = "af_actuals_map_capture_photo"

    static func mapCandidateAccessibilityID(_ index: Int) -> String {
        "af_actuals_map_candidate_\(index)"
    }

    static func mapKeepAsNamedCTA(title: String) -> String {
        "Verify as-is “\(title)” — no detail needed"
    }

    /// Map v3 pinned CTA — nothing selected (AMA-2407: Verify as-is, not Keep as).
    static func mapKeepAsDoneCTA(title: String) -> String {
        "Verify “\(title)” as-is — done"
    }

    /// Map v3 pinned CTA — match selected.
    static func mapMatchToCTA(title: String) -> String {
        "Match to “\(title)”"
    }

    // MARK: - History scrubber / Profile History (AMA-2396 A2)

    /// Prefer `historyScrubberHint(connected:)` so the line lists linked sources only.
    static let historyScrubberHint =
        "SWIPE OR TAP — LAST 30 DAYS · PULLED FROM STRAVA + GARMIN ON CONNECT"

    /// Scrubber mono hint — names only the sources currently connected.
    static func historyScrubberHint(connected: Set<ActualsSourceProvider>) -> String {
        let ordered = Self.displayOrdered(connected)
        guard !ordered.isEmpty else {
            return "SWIPE OR TAP — LAST 30 DAYS · CONNECT A SOURCE TO PULL HISTORY"
        }
        let names = ordered.map { Self.sourceDisplayName($0).uppercased() }
        return "SWIPE OR TAP — LAST 30 DAYS · PULLED FROM \(names.joined(separator: " + ")) ON CONNECT"
    }

    /// Stable display order: Apple Health → Garmin → Strava.
    static func displayOrdered(_ connected: Set<ActualsSourceProvider>) -> [ActualsSourceProvider] {
        ActualsSourceProvider.allCases.filter { connected.contains($0) }
    }

    private static func joinedDisplayNames(_ providers: [ActualsSourceProvider]) -> String {
        let names = providers.map(Self.sourceDisplayName)
        guard let last = names.last else { return "" }
        if names.count == 1 { return last }
        if names.count == 2 { return "\(names[0]) and \(last)" }
        return names.dropLast().joined(separator: ", ") + ", and \(last)"
    }

    static let historyLocalTimeFooter =
        "TIMES ARE YOUR LOCAL TIME · NEWEST FIRST — THE WRONG-DAY BUG DIES HERE"
    static let historyJumpToday = "Today ›"
    static let historyTitle = "History"
    static let historyProfileEntrySub = "STRAVA SYNC · LAST 30 DAYS · WRITE-BACK STATE"
    /// Profile → Connect sources (AMA-2396 discoverability).
    static let connectSourcesProfileTitle = "Strava & sources"
    static let connectSourcesProfileSub = "LINK STRAVA · WRITE-BACK TOGGLE"
    static let historyLoadMore = "Load 30 more days…"
    static let historyFillInCTA = "Fill in ›"
    static let historyLegend =
        "STRAVA ✓ OURS = WE WROTE IT (SIGNED “— TRACKED WITH AMAKAFLOW”, SAFE TO REFRESH) · SKIPPED = A RULE HELD US BACK · UNTOUCHED = THEIR WORDS, WE NEVER WRITE."
    static let historyBannerShow = "Show ›"
    static let historyAccessibilityID = "af_actuals_history"

    static func historyPulledBanner(days: Int, sessions: Int, needFillIn: Int) -> String {
        "PULLED \(days) DAYS · \(sessions) SESSIONS · \(needFillIn) STILL NEED FILL-IN"
    }

    // MARK: - Verified undo / ⋯ menu (AMA-2396 A3)

    static let verifiedToastWithStrava = "Verified ✓ · Strava updated"
    static let verifiedToastNoStrava = "Verified ✓"
    static let verifiedUndoAction = "Undo"
    static let verifiedMenuEdit = "Edit actuals"
    static let verifiedMenuEditSub = "CHANGES STAY VERIFIED · REFRESHES OUR STRAVA TEXT"
    static let verifiedMenuRemoveStrava = "Undo our Strava text"
    static let verifiedMenuRemoveStravaSub =
        "KEEPS THE ACTIVITY · RESTORES TITLE + DESCRIPTION FROM BEFORE AMAKAFLOW"
    static let verifiedMenuUnverify = "Un-verify"
    static let verifiedMenuUnverifySub =
        "BACK TO “FILL IN” · ACTUALS KEPT AS DRAFT · STRAVA RESTORED"
    static let verifiedMenuUnmatch = "Unmatch from this workout"
    static let verifiedMenuUnmatchSub = "SESSION KEEPS ITS STRAVA METRICS"
    static let verifiedMenuAccessibilityID = "af_actuals_verified_menu"

    // MARK: - Strava write-back settings (AMA-2396 A4)

    static let writeBackToggleTitle = "Write my workout back to Strava"
    static let writeBackToggleSub =
        "AFTER YOU VERIFY — TITLE + DESCRIPTION GET THE REAL STRUCTURE"
    static let writeBackSkipHeader = "NEVER TOUCH — SKIP THESE"
    static let writeBackOwnershipExplainer =
        "HOW WE KNOW WHAT'S OURS: EVERY UPDATE WE WRITE ENDS WITH “— TRACKED WITH AMAKAFLOW”. SIGNED = OURS → REFRESHED WHEN YOUR ACTUALS CHANGE, NEVER DUPLICATED. UNSIGNED WORDS = YOURS OR ANOTHER APP'S → NEVER TOUCHED. ONE UPDATE PER ACTIVITY, EVER."
    static let writeBackPreviewHeader = "WHAT STRAVA GETS"
    static let writeBackStatusReadWrite = "CONNECTED ✓ · READ + WRITE-BACK"
    static let writeBackReconnectToast =
        "Needs one more permission — reconnect to Strava to allow editing"
    static let writeBackAccessibilityID = "af_actuals_strava_writeback"

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
    static let oauthUploadRequestedWriteBack =
        "REQUESTED — title + description only after you verify (signed write-back)"
    static let oauthGarminUploadNotRequested = "NOT REQUESTED — AmakaFlow never posts to Garmin"
    static let oauthStravaHostChrome = "🔒 strava.com/oauth/authorize"
    static let oauthGarminHostChrome = "🔒 connect.garmin.com/oauthConfirm"
    static let oauthScopeAccessibilityID = "af_actuals_oauth_scope"
    static let oauthAuthorizeAccessibilityID = "af_actuals_oauth_authorize"
    static let oauthCancelAccessibilityID = "af_actuals_oauth_cancel"

    /// Locked scope rows — edit/upload is struck-through unless write-back reconnect.
    static func oauthScopes(
        for provider: ActualsSourceProvider,
        includeWrite: Bool = false
    ) -> [ActualsOAuthScopeRow] {
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
                    granted: includeWrite,
                    title: "Upload or edit your activities",
                    subtitle: includeWrite ? oauthUploadRequestedWriteBack : oauthUploadNotRequested
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

// MARK: - Strava description (AMA-2405)

extension ActualsCopy {
    static let stravaDescriptionLabel = "STRAVA DESCRIPTION"
    static let stravaDescriptionEmpty = "No description on this Strava activity."
    static let stravaDescriptionLoading = "Loading Strava description…"
    static let stravaDescriptionLoadFailed = "Couldn't load the Strava description."
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
