//
//  FixtureAPIService.swift
//  AmakaFlow
//
//  API service stub for fixture-based E2E testing.
//  Loads workouts from bundled JSON fixtures; returns canned success for all writes.
//  No HTTP calls leave the device.
//

#if DEBUG
import Foundation

/// API service that loads from bundled JSON fixtures and stubs all writes.
/// Conforming to APIServiceProviding allows it to be injected via AppDependencies
/// without changes to ViewModels, Engine, or UI.
class FixtureAPIService: APIServiceProviding {
    private var followedUserIds = Set<String>()
    private var fixtureCoachingProfile = Components.Schemas.CoachingProfile(
        createdAt: "2026-05-28T00:00:00Z",
        equipment: nil,
        experienceLevel: "intermediate",
        goals: nil,
        primaryGoal: "general_fitness",
        sessionsPerWeek: 3,
        updatedAt: "2026-05-28T00:00:00Z",
        userId: "fixture-test-user"
    )
    var pairDeviceResult: Result<Components.Schemas.PairDeviceResult, Error> = .success(
        Components.Schemas.PairDeviceResult(message: "Fixture Garmin paired", success: true)
    )
    var revokeDeviceResult: Result<Components.Schemas.PairDeviceResult, Error> = .success(
        Components.Schemas.PairDeviceResult(message: "Fixture device removed", success: true)
    )
    var setDeviceRolesResult: Result<Components.Schemas.DeviceRolesResult, Error>?
    var watchDeliveryStatusResult: Result<Components.Schemas.WatchDeliveryStatus, Error>?
    var resendWatchDeliveryResult: Result<Components.Schemas.WatchResendResult, Error>?
    var listMessagingChannelsResult: Result<Components.Schemas.MessagingChannelList, Error>?
    var setChannelPrefsResult: Result<Components.Schemas.ChannelPrefsResult, Error>?
    var listLibraryItemsResult: Result<Components.Schemas.LibraryItemList, Error>?
    var getLibraryItemResult: Result<Components.Schemas.LibraryItemDetail, Error>?
    var postReadinessSampleResult: Result<ReadinessSampleWriteResult, Error>?
    var readinessTodayResult: Result<Components.Schemas.ReadinessToday, Error>?
    var readinessTrendResult: Result<Components.Schemas.ReadinessTrend, Error>?
    var readinessSourcePrefsResult: Result<Components.Schemas.ReadinessSourcePrefs, Error>?
    var setReadinessSourcePrefResult: Result<Components.Schemas.ReadinessSourcePref, Error>?
    var readinessTodayEmpty = false
    var readinessSourcePrefsEmpty = false
    var setReadinessSourcePrefDelayNanoseconds: UInt64 = 0
    private(set) var setReadinessSourcePrefCallCount = 0
    private(set) var fixtureReadinessSamples: [ReadinessSampleWriteResult] = []
    var fixtureSourcePrefs: [Components.Schemas.ReadinessSourcePref] = [
        Components.Schemas.ReadinessSourcePref(metric: "hrv", source: "apple_health"),
        Components.Schemas.ReadinessSourcePref(metric: "sleep", source: "apple_health"),
        Components.Schemas.ReadinessSourcePref(metric: "rhr", source: "garmin")
    ]
    var libraryItemsEmpty = false
    var libraryItemDetail404 = false
    private var fixtureMessagingDeliveryLive = false
    private var fixtureMessagingChannels: [Components.Schemas.MessagingChannel] = [
        Components.Schemas.MessagingChannel(
            comingSoon: false,
            connected: true,
            handle: "@amakaflow_fixture",
            id: "telegram",
            name: "Telegram",
            prefs: Components.Schemas.ChannelPrefs(briefing: true, checkin: true, quietEnd: "07:00", quietStart: "21:00", swap: false)
        ),
        Components.Schemas.MessagingChannel(
            comingSoon: true,
            connected: false,
            handle: nil,
            id: "whatsapp",
            name: "WhatsApp",
            prefs: Components.Schemas.ChannelPrefs(briefing: false, checkin: false, swap: false)
        ),
        Components.Schemas.MessagingChannel(
            comingSoon: true,
            connected: false,
            handle: nil,
            id: "slack",
            name: "Slack",
            prefs: Components.Schemas.ChannelPrefs(briefing: false, checkin: false, swap: false)
        )
    ]
    private var fixtureLibraryItems: [Components.Schemas.LibraryItem] = [
        Components.Schemas.LibraryItem(
            bookmarked: false,
            id: "fixture-strength-basics",
            kind: .workout,
            savedAt: "2026-05-29T12:00:00Z",
            sourceDomain: "coach.amakaflow.com",
            sourceUrl: "https://coach.amakaflow.com/library/strength-basics",
            tags: ["strength", "beginner"],
            thumbnailUrl: nil,
            title: "Strength basics for travel weeks"
        ),
        Components.Schemas.LibraryItem(
            bookmarked: false,
            id: "fixture-ankle-mobility-video",
            kind: .video,
            savedAt: "2026-05-29T12:05:00Z",
            sourceDomain: "youtube.com",
            sourceUrl: "https://youtube.com/watch?v=fixture",
            tags: ["mobility", "ankles"],
            thumbnailUrl: nil,
            title: "10-minute ankle mobility reset"
        ),
        Components.Schemas.LibraryItem(
            bookmarked: false,
            id: "fixture-zone-two-article",
            kind: .article,
            savedAt: "2026-05-29T12:10:00Z",
            sourceDomain: "trainingpeaks.com",
            sourceUrl: "https://trainingpeaks.com/fixture-zone-two",
            tags: ["endurance", "base"],
            thumbnailUrl: nil,
            title: "Why zone two still matters"
        ),
        Components.Schemas.LibraryItem(
            bookmarked: false,
            id: "fixture-hyrox-plan",
            kind: .plan,
            savedAt: "2026-05-29T12:15:00Z",
            sourceDomain: "amakaflow.com",
            sourceUrl: "https://amakaflow.com/plans/hyrox-fixture",
            tags: ["hyrox", "strength"],
            thumbnailUrl: nil,
            title: "Four-week HYROX tune-up"
        )
    ]
    private var fixtureLibraryItemDetails: [String: Components.Schemas.LibraryItemDetail] = [
        "fixture-strength-basics": Components.Schemas.LibraryItemDetail(
            bookmarked: false,
            id: "fixture-strength-basics",
            keyTakeaways: ["Two compact strength days fit travel weeks.", "Use RPE instead of fixed loads when equipment changes."],
            kind: .workout,
            microSummary: "Travel-friendly strength",
            savedAt: "2026-05-29T12:00:00Z",
            sourceDomain: "coach.amakaflow.com",
            sourceUrl: "https://coach.amakaflow.com/library/strength-basics",
            summary: "A compact strength template for weeks when travel or equipment limits your normal gym routine.",
            tags: ["strength", "beginner"],
            thumbnailUrl: nil,
            title: "Strength basics for travel weeks"
        ),
        "fixture-ankle-mobility-video": Components.Schemas.LibraryItemDetail(
            bookmarked: false,
            id: "fixture-ankle-mobility-video",
            keyTakeaways: ["Spend extra time on the loaded dorsiflexion drill.", "Stop before pinching pain."],
            kind: .video,
            microSummary: "Quick ankle reset",
            savedAt: "2026-05-29T12:05:00Z",
            sourceDomain: "youtube.com",
            sourceUrl: "https://youtube.com/watch?v=fixture",
            summary: "A short mobility sequence to restore ankle range before squats, runs, or HYROX work.",
            tags: ["mobility", "ankles"],
            thumbnailUrl: nil,
            title: "10-minute ankle mobility reset"
        ),
        "fixture-zone-two-article": Components.Schemas.LibraryItemDetail(
            bookmarked: false,
            id: "fixture-zone-two-article",
            keyTakeaways: ["Zone two supports aerobic durability.", "Keep it easy enough to repeat alongside strength work."],
            kind: .article,
            microSummary: "Aerobic base reminder",
            savedAt: "2026-05-29T12:10:00Z",
            sourceDomain: "trainingpeaks.com",
            sourceUrl: "https://trainingpeaks.com/fixture-zone-two",
            summary: "An explainer on why steady aerobic base work still matters for hybrid athletes.",
            tags: ["endurance", "base"],
            thumbnailUrl: nil,
            title: "Why zone two still matters"
        ),
        "fixture-hyrox-plan": Components.Schemas.LibraryItemDetail(
            bookmarked: false,
            id: "fixture-hyrox-plan",
            keyTakeaways: ["Build compromised running gradually.", "Keep strength maintenance in the plan."],
            kind: .plan,
            microSummary: "HYROX tune-up",
            savedAt: "2026-05-29T12:15:00Z",
            sourceDomain: "amakaflow.com",
            sourceUrl: "https://amakaflow.com/plans/hyrox-fixture",
            summary: "A four-week outline for sharpening HYROX skills without pretending the full week-by-week structure is available yet.",
            tags: ["hyrox", "strength"],
            thumbnailUrl: nil,
            title: "Four-week HYROX tune-up"
        )
    ]
    private var fixtureDevices: [Components.Schemas.PairedDevice] = [
        Components.Schemas.PairedDevice(
            id: "fixture-garmin-955",
            lastSyncAt: "2026-05-28T14:07:00Z",
            model: "Forerunner 955",
            name: "Garmin Forerunner",
            roles: [.workouts, .recovery]
        ),
        Components.Schemas.PairedDevice(
            id: "fixture-apple-watch",
            lastSyncAt: "2026-05-28T13:12:00Z",
            model: "Series 9",
            name: "Apple Watch",
            roles: [.recovery]
        ),
        Components.Schemas.PairedDevice(
            id: "fixture-whoop",
            lastSyncAt: nil,
            model: "WHOOP 4.0",
            name: "WHOOP Band",
            roles: nil
        )
    ]
    private var fixtureWatchDeliveryStatuses: [String: Components.Schemas.WatchDeliveryStatus] = [
        "fixture-watch-generated": Components.Schemas.WatchDeliveryStatus(
            canResend: false,
            occurredAt: "2026-05-29T13:00:00Z",
            state: .generated,
            subtitle: "Queued for Garmin delivery.",
            title: "Workout generated"
        ),
        "fixture-watch-pushed": Components.Schemas.WatchDeliveryStatus(
            canResend: false,
            occurredAt: "2026-05-29T13:00:03Z",
            state: .pushed,
            subtitle: "Sent to Garmin Connect.",
            title: "Pushed to Garmin"
        ),
        "fixture-watch-fetched_by_widget": Components.Schemas.WatchDeliveryStatus(
            canResend: false,
            occurredAt: "2026-05-29T13:00:10Z",
            state: .fetchedByWidget,
            subtitle: "The watch widget fetched the workout.",
            title: "Fetched by widget"
        ),
        "fixture-watch-confirmed_on_device": Components.Schemas.WatchDeliveryStatus(
            canResend: false,
            occurredAt: "2026-05-29T13:00:20Z",
            state: .confirmedOnDevice,
            subtitle: "Ready on your watch.",
            title: "Confirmed on device"
        ),
        "fixture-watch-failed": Components.Schemas.WatchDeliveryStatus(
            canResend: true,
            occurredAt: "2026-05-29T13:00:20Z",
            state: .failed,
            subtitle: "Garmin did not acknowledge delivery.",
            title: "Delivery failed"
        )
    ]

    // MARK: - Reads (from fixtures)

    func fetchWorkouts(isRetry: Bool) async throws -> [Workout] {
        try FixtureLoader.loadWorkouts()
    }

    func fetchScheduledWorkouts(isRetry: Bool) async throws -> [ScheduledWorkout] {
        // Wrap first two fixture workouts as scheduled for today/tomorrow
        let workouts = try FixtureLoader.loadWorkouts()
        return workouts.prefix(2).enumerated().map { index, workout in
            ScheduledWorkout(
                workout: workout,
                scheduledDate: Calendar.current.date(byAdding: .day, value: index, to: Date()),
                scheduledTime: index == 0 ? "09:00" : "18:00",
                syncedToApple: false
            )
        }
    }

    func fetchPushedWorkouts(isRetry: Bool) async throws -> [Workout] {
        try FixtureLoader.loadWorkouts()
    }

    func fetchPendingWorkouts(isRetry: Bool) async throws -> [Workout] {
        try FixtureLoader.loadWorkouts()
    }

    // MARK: - Writes (canned success)

    func syncWorkout(_ workout: Workout) async throws {
        print("[FixtureAPIService] Stub: syncWorkout(\(workout.name)) -> success")
    }

    func getAppleExport(workoutId: String) async throws -> String {
        print("[FixtureAPIService] Stub: getAppleExport(\(workoutId)) -> empty JSON")
        return "{}"
    }

    func mintTelegramLinkToken() async throws -> TelegramLinkTokenResponse {
        TelegramLinkTokenResponse(
            token: "fixture-telegram-token",
            deepLink: "https://t.me/amakaflow_userbot?start=fixture-telegram-token",
            nativeLink: "tg://resolve?domain=amakaflow_userbot&start=fixture-telegram-token",
            expiresInSeconds: 900
        )
    }

    func getTelegramLinkStatus(token: String) async throws -> TelegramLinkStatusResponse {
        TelegramLinkStatusResponse(
            linked: true,
            telegramId: 123_456_789,
            telegramIdHash: "fixture-telegram-hash",
            usedAt: Date()
        )
    }

    func parseVoiceWorkout(transcription: String, sportHint: WorkoutSport?) async throws -> VoiceWorkoutParseResponse {
        throw APIError.notImplemented
    }

    func ingestInstagramReel(url: String) async throws -> IngestInstagramReelResponse {
        throw APIError.notImplemented
    }

    func ingestText(text: String, source: String?) async throws -> IngestTextResponse {
        print("[FixtureAPIService] Stub: ingestText -> canned response")
        return IngestTextResponse(name: "Fixture Workout", sport: "strength", source: source)
    }

    func transcribeAudio(
        audioData: String,
        provider: String,
        language: String,
        keywords: [String],
        includeWordTimings: Bool
    ) async throws -> CloudTranscriptionResponse {
        throw APIError.notImplemented
    }

    func syncPersonalDictionary(
        corrections: [String: String],
        customTerms: [String]
    ) async throws -> PersonalDictionaryResponse {
        print("[FixtureAPIService] Stub: syncPersonalDictionary -> empty")
        return PersonalDictionaryResponse(corrections: [:], customTerms: [])
    }

    func fetchPersonalDictionary() async throws -> PersonalDictionaryResponse {
        return PersonalDictionaryResponse(corrections: [:], customTerms: [])
    }

    func logManualWorkout(_ workout: Workout, startedAt: Date, endedAt: Date, durationSeconds: Int) async throws {
        print("[FixtureAPIService] Stub: logManualWorkout(\(workout.name)) -> success")
    }

    func postWorkoutCompletion(_ completion: WorkoutCompletionRequest, isRetry: Bool, requestID: String?) async throws -> WorkoutCompletionResponse {
        print("[FixtureAPIService] Stub: postWorkoutCompletion -> success (requestID=\(requestID ?? "nil"))")
        return WorkoutCompletionResponse(
            completionId: "fixture-completion-001",
            id: "fixture-completion-001",
            status: "completed",
            success: true
        )
    }

    func confirmSync(workoutId: String, deviceType: String, deviceId: String?, requestID: String?) async throws {
        print("[FixtureAPIService] Stub: confirmSync(\(workoutId)) -> success (requestID=\(requestID ?? "nil"))")
    }

    func reportSyncFailed(workoutId: String, deviceType: String, error: String, deviceId: String?, requestID: String?) async throws {
        print("[FixtureAPIService] Stub: reportSyncFailed(\(workoutId)) -> success (requestID=\(requestID ?? "nil"))")
    }

    func fetchProfile() async throws -> UserProfile {
        return UserProfile(
            id: "fixture-test-user",
            email: "fixture-test@amakaflow.com",
            name: "Fixture Test User",
            avatarUrl: nil
        )
    }

    func fetchCompletions(limit: Int, offset: Int) async throws -> [WorkoutCompletion] {
        return WorkoutCompletion.sampleData
    }

    func fetchCompletionDetail(id: String) async throws -> WorkoutCompletionDetail {
        return WorkoutCompletionDetail.sample
    }

    // MARK: - Planning (AMA-1147)

    func fetchDayStates(from: String, to: String) async throws -> [DayState] { [] }
    func generateWeek(request: GenerateWeekRequest?) async throws -> ProposedPlan {
        ProposedPlan(weekStartDate: "2026-03-21", days: [], rationale: "Fixture plan", totalLoadScore: nil)
    }
    func detectConflicts(startDate: String, endDate: String) async throws -> [Conflict] { [] }
    func parseWorkoutText(text: String, context: String?) async throws -> ParseTextResult {
        ParseTextResult(
            success: true,
            exercises: [ParsedExercise(rawName: "Fixture Exercise", sets: 3, reps: "10", order: 1)],
            detectedFormat: "free_text",
            confidence: 0.9,
            source: context
        )
    }

    // MARK: - Agent Actions (AMA-1956)

    func fetchAgentActions(status: String?) async throws -> [AgentAction] { [] }
    func respondToAction(id: String, decision: String) async throws -> AgentAction { .samplePending }
    func undoAction(id: String) async throws -> AgentAction { .sampleApplied }

    // MARK: - Devices (AMA-1996)

    func listDevices() async throws -> [Components.Schemas.PairedDevice] {
        fixtureDevices
    }

    func pairDevice(shortCode: String) async throws -> Components.Schemas.PairDeviceResult {
        let result = try pairDeviceResult.get()
        if !fixtureDevices.contains(where: { $0.id == "fixture-garmin-955" }) {
            fixtureDevices.insert(
                Components.Schemas.PairedDevice(
                    id: "fixture-garmin-955",
                    lastSyncAt: "2026-05-28T14:07:00Z",
                    model: "Forerunner 955",
                    name: "Garmin Forerunner",
                    roles: [.workouts, .recovery]
                ),
                at: 0
            )
        }
        print("[FixtureAPIService] Stub: pairDevice(\(shortCode)) -> success")
        return result
    }

    func revokeDevice(id: String) async throws -> Components.Schemas.PairDeviceResult {
        let result = try revokeDeviceResult.get()
        fixtureDevices.removeAll { $0.id == id }
        print("[FixtureAPIService] Stub: revokeDevice(\(id)) -> success")
        return result
    }

    func setDeviceRoles(
        id: String,
        roles: [Components.Schemas.DeviceRole]
    ) async throws -> Components.Schemas.DeviceRolesResult {
        if let setDeviceRolesResult {
            return try setDeviceRolesResult.get()
        }
        guard let index = fixtureDevices.firstIndex(where: { $0.id == id }) else {
            throw APIError.serverErrorWithBody(404, "{\"detail\":\"Device pairing not found\"}")
        }
        let existing = fixtureDevices[index]
        fixtureDevices[index] = Components.Schemas.PairedDevice(
            id: existing.id,
            lastSyncAt: existing.lastSyncAt,
            model: existing.model,
            name: existing.name,
            roles: roles
        )
        print("[FixtureAPIService] Stub: setDeviceRoles(\(id), \(roles.map(\.rawValue))) -> success")
        return Components.Schemas.DeviceRolesResult(roles: roles, success: true)
    }

    func watchDeliveryStatus(workoutId: String) async throws -> Components.Schemas.WatchDeliveryStatus {
        if let watchDeliveryStatusResult {
            return try watchDeliveryStatusResult.get()
        }
        if let exact = fixtureWatchDeliveryStatuses[workoutId] {
            return exact
        }
        if workoutId.contains("failed") {
            return fixtureWatchDeliveryStatuses["fixture-watch-failed"]!
        }
        if workoutId.contains("confirmed") {
            return fixtureWatchDeliveryStatuses["fixture-watch-confirmed_on_device"]!
        }
        return fixtureWatchDeliveryStatuses["fixture-watch-pushed"]!
    }

    func resendWatchDelivery(workoutId: String) async throws -> Components.Schemas.WatchResendResult {
        if let resendWatchDeliveryResult {
            return try resendWatchDeliveryResult.get()
        }
        fixtureWatchDeliveryStatuses[workoutId] = Components.Schemas.WatchDeliveryStatus(
            canResend: false,
            occurredAt: "2026-05-29T13:01:00Z",
            state: .generated,
            subtitle: "Queued for Garmin delivery.",
            title: "Workout generated"
        )
        print("[FixtureAPIService] Stub: resendWatchDelivery(\(workoutId)) -> success")
        return Components.Schemas.WatchResendResult(deliveryIds: ["fixture-delivery-\(workoutId)"], success: true)
    }

    // MARK: - Library (AMA-2004)

    func listLibraryItems(
        kind: Components.Schemas.LibraryKind?,
        tag: String?
    ) async throws -> Components.Schemas.LibraryItemList {
        if let listLibraryItemsResult {
            return try listLibraryItemsResult.get()
        }
        var items = libraryItemsEmpty ? [] : fixtureLibraryItems
        if let kind {
            items = items.filter { $0.kind == kind }
        }
        if let tag = tag?.trimmingCharacters(in: .whitespacesAndNewlines), !tag.isEmpty {
            items = items.filter { item in
                (item.tags ?? []).contains { candidate in
                    candidate.compare(tag, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                }
            }
        }
        return Components.Schemas.LibraryItemList(items: items, total: items.count)
    }

    func getLibraryItem(id: String) async throws -> Components.Schemas.LibraryItemDetail {
        if let getLibraryItemResult {
            return try getLibraryItemResult.get()
        }
        guard !libraryItemDetail404,
              let item = fixtureLibraryItemDetails[id] else {
            throw APIError.serverErrorWithBody(404, "{\"detail\":\"Library item not found\"}")
        }
        return item
    }

    // MARK: - Messaging Channels (AMA-2027)

    func listMessagingChannels() async throws -> Components.Schemas.MessagingChannelList {
        if let listMessagingChannelsResult {
            return try listMessagingChannelsResult.get()
        }
        return Components.Schemas.MessagingChannelList(
            channels: fixtureMessagingChannels,
            deliveryLive: fixtureMessagingDeliveryLive
        )
    }

    func setChannelPrefs(
        channelId: String,
        prefs: Components.Schemas.ChannelPrefsRequest
    ) async throws -> Components.Schemas.ChannelPrefsResult {
        if let setChannelPrefsResult {
            return try setChannelPrefsResult.get()
        }
        guard let index = fixtureMessagingChannels.firstIndex(where: { $0.id == channelId }) else {
            throw APIError.serverErrorWithBody(404, "{\"detail\":\"Messaging channel not found\"}")
        }
        let updatedPrefs = Components.Schemas.ChannelPrefs(
            briefing: prefs.briefing,
            checkin: prefs.checkin,
            quietEnd: prefs.quietEnd,
            quietStart: prefs.quietStart,
            swap: prefs.swap
        )
        let existing = fixtureMessagingChannels[index]
        fixtureMessagingChannels[index] = Components.Schemas.MessagingChannel(
            comingSoon: existing.comingSoon,
            connected: existing.connected,
            handle: existing.handle,
            id: existing.id,
            name: existing.name,
            prefs: updatedPrefs
        )
        print("[FixtureAPIService] Stub: setChannelPrefs(\(channelId)) -> saved prefs only; deliveryLive=false")
        return Components.Schemas.ChannelPrefsResult(channelId: channelId, prefs: updatedPrefs, success: true)
    }

    // MARK: - Coaching Profile (AMA-1995)

    func getCoachingProfile() async throws -> Components.Schemas.CoachingProfile? {
        fixtureCoachingProfile
    }

    func upsertCoachingProfile(_ profile: Components.Schemas.CoachingProfileUpsert) async throws -> Components.Schemas.CoachingProfile {
        fixtureCoachingProfile = Components.Schemas.CoachingProfile(
            createdAt: fixtureCoachingProfile.createdAt,
            equipment: profile.equipment,
            experienceLevel: profile.experienceLevel,
            goals: profile.goals,
            injuriesLimitations: profile.injuriesLimitations,
            preFilledFromMemory: fixtureCoachingProfile.preFilledFromMemory,
            preferredDays: profile.preferredDays,
            primaryGoal: profile.primaryGoal,
            sessionDurationMinutes: profile.sessionDurationMinutes,
            sessionsPerWeek: profile.sessionsPerWeek,
            updatedAt: "2026-05-28T00:00:01Z",
            userId: fixtureCoachingProfile.userId
        )
        return fixtureCoachingProfile
    }

    func postReadinessSample(
        hrv: Double?,
        restingHr: Int?,
        sleepHours: Double?,
        sleepQuality: String?,
        sampleDate: String?
    ) async throws -> ReadinessSampleWriteResult {
        if let postReadinessSampleResult {
            return try postReadinessSampleResult.get()
        }
        guard hrv != nil || restingHr != nil || sleepHours != nil || sleepQuality != nil else {
            throw APIError.serverErrorWithBody(422, "{\"detail\":\"At least one metric is required.\"}")
        }
        let result = ReadinessSampleWriteResult(
            success: true,
            date: sampleDate ?? "2026-05-30",
            source: "apple_health"
        )
        fixtureReadinessSamples.append(result)
        print("[FixtureAPIService] Stub: postReadinessSample(date=\(result.date), source=apple_health) -> success")
        return result
    }

    // MARK: - Readiness (AMA-2054)

    func readinessToday() async throws -> Components.Schemas.ReadinessToday {
        if let readinessTodayResult {
            return try readinessTodayResult.get()
        }
        if readinessTodayEmpty {
            return Components.Schemas.ReadinessToday(
                date: "2026-05-30",
                hasData: false,
                hrv: nil,
                restingHr: nil,
                sleepHours: nil,
                sleepQuality: nil,
                source: nil
            )
        }
        return Components.Schemas.ReadinessToday(
            date: "2026-05-30",
            hasData: true,
            hrv: 62.4,
            restingHr: 48,
            sleepHours: 7.6,
            sleepQuality: "good",
            source: "apple_health"
        )
    }

    func readinessTrend(metric: String, days: Int) async throws -> Components.Schemas.ReadinessTrend {
        if let readinessTrendResult {
            return try readinessTrendResult.get()
        }
        let points = [
            Components.Schemas.ReadinessTrendPoint(date: "2026-05-24", value: 57.0),
            Components.Schemas.ReadinessTrendPoint(date: "2026-05-25", value: nil),
            Components.Schemas.ReadinessTrendPoint(date: "2026-05-26", value: 59.5),
            Components.Schemas.ReadinessTrendPoint(date: "2026-05-27", value: 61.0),
            Components.Schemas.ReadinessTrendPoint(date: "2026-05-28", value: nil),
            Components.Schemas.ReadinessTrendPoint(date: "2026-05-29", value: 60.2),
            Components.Schemas.ReadinessTrendPoint(date: "2026-05-30", value: 62.4)
        ]
        return Components.Schemas.ReadinessTrend(days: days, metric: metric, points: points)
    }

    func readinessSourcePrefs() async throws -> Components.Schemas.ReadinessSourcePrefs {
        if let readinessSourcePrefsResult {
            return try readinessSourcePrefsResult.get()
        }
        return Components.Schemas.ReadinessSourcePrefs(prefs: readinessSourcePrefsEmpty ? [] : fixtureSourcePrefs)
    }

    func setReadinessSourcePref(metric: String, source: String, deviceId: String?) async throws -> Components.Schemas.ReadinessSourcePref {
        setReadinessSourcePrefCallCount += 1
        if setReadinessSourcePrefDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: setReadinessSourcePrefDelayNanoseconds)
        }
        if let setReadinessSourcePrefResult {
            return try setReadinessSourcePrefResult.get()
        }
        let updated = Components.Schemas.ReadinessSourcePref(deviceId: deviceId, metric: metric, source: source)
        if let index = fixtureSourcePrefs.firstIndex(where: { $0.metric == metric }) {
            fixtureSourcePrefs[index] = updated
        } else {
            fixtureSourcePrefs.append(updated)
        }
        print("[FixtureAPIService] Stub: setReadinessSourcePref(\(metric), \(source)) -> success")
        return updated
    }

    // MARK: - Coach (AMA-1147)

    func sendCoachMessage(message: String, context: CoachContext?) async throws -> CoachResponse {
        CoachResponse(id: "fixture", message: "Fixture coach response", suggestions: nil, actionItems: nil)
    }
    func getFatigueAdvice(fatigueScore: Double?, loadHistory: [DailyLoad]?) async throws -> FatigueAdvice {
        FatigueAdvice(level: .low, message: "You're recovering well", recommendations: ["Rest"], suggestedRestDays: 1, recoveryActivities: nil)
    }
    func fetchCoachMemories() async throws -> [CoachMemory] { [] }

    // MARK: - Analytics (AMA-1147)

    func fetchShoeComparison() async throws -> [ShoeStats] { [] }

    // MARK: - Billing (AMA-1147)

    func fetchSubscription() async throws -> Subscription {
        Subscription(plan: "free", status: .active, currentPeriodEnd: nil, cancelAtPeriodEnd: nil, features: [])
    }

    // MARK: - Notification Preferences (AMA-1147)

    func fetchNotificationPreferences() async throws -> NotificationPreferences { NotificationPreferences() }
    func updateNotificationPreferences(_ prefs: NotificationPreferences) async throws -> NotificationPreferences { prefs }


    // MARK: - Workout Save (AMA-1231)

    func saveWorkout(_ request: WorkoutSaveRequest) async throws -> Workout {
        print("[FixtureAPIService] Stub: saveWorkout -> fixture workout")
        return try FixtureLoader.loadWorkouts().first!
    }

    // MARK: - Calendar Sync (AMA-1238)

    func fetchConnectedCalendars() async throws -> [ConnectedCalendar] { [] }
    func connectCalendar(provider: String) async throws -> String { "https://example.com/auth" }
    func syncCalendar(calendarId: String) async throws -> CalendarSyncResponse { CalendarSyncResponse(syncedEvents: 0) }
    func disconnectCalendar(calendarId: String) async throws {}

    // MARK: - Social Feed (AMA-1273)

    func fetchSocialFeed(cursor: String?, limit: Int) async throws -> FeedResponse {
        FeedResponse(posts: [], nextCursor: nil, hasMore: false)
    }
    func addSocialReaction(postId: String, emoji: String) async throws {}
    func removeSocialReaction(postId: String, emoji: String) async throws {}
    func fetchSocialComments(postId: String) async throws -> CommentsResponse {
        CommentsResponse(comments: [])
    }
    func postSocialComment(postId: String, text: String) async throws {}
    func fetchSocialSettings() async throws -> SocialSettings {
        SocialSettings(discoverable: true, shareWorkouts: true, hideWeights: false)
    }
    func updateSocialSettings(_ settings: SocialSettings) async throws {}
    func fetchUserPublicProfile(userId: String) async throws -> UserPublicProfile {
        UserPublicProfile(userId: userId, userName: "Fixture User", avatarUrl: nil, workoutCount: 0, totalVolume: 0, streakDays: 0, isFollowing: followedUserIds.contains(userId), recentWorkouts: [])
    }
    func followUser(userId: String) async throws { followedUserIds.insert(userId) }
    func unfollowUser(userId: String) async throws { followedUserIds.remove(userId) }

    // MARK: - Challenges (AMA-1276)

    func fetchChallenges() async throws -> ChallengesResponse {
        ChallengesResponse(challenges: [])
    }
    func fetchChallengeDetail(id: String) async throws -> ChallengeDetailResponse {
        ChallengeDetailResponse(
            challenge: Challenge(id: id, title: "Fixture", type: .volume, status: .active, description: nil, target: 1000, targetUnit: "kg", startDate: Date(), endDate: Date(), creatorId: "fix", creatorName: "Fixture", participantCount: 0, isTeamMode: false, isJoined: false, myProgress: nil, myProgressPercentage: nil),
            leaderboard: [],
            myProgress: nil
        )
    }
    func createChallenge(_ request: CreateChallengeRequest) async throws {}
    func joinChallenge(id: String) async throws {}

    // MARK: - Training Crews (AMA-1277)

    func fetchMyCrews() async throws -> CrewListResponse {
        return CrewListResponse(crews: [], count: 0)
    }

    func fetchCrewDetail(id: String) async throws -> CrewDetail {
        throw APIError.notFound
    }

    func fetchCrewFeed(crewId: String) async throws -> CrewFeedResponse {
        return CrewFeedResponse(posts: [], nextCursor: nil)
    }

    func createCrew(_ request: CreateCrewRequest) async throws {}

    func joinCrew(crewId: String, request: JoinCrewRequest) async throws {}

    func leaveCrew(crewId: String) async throws {}

    // MARK: - Leaderboards (AMA-1278)

    func fetchFriendsLeaderboard(dimension: String, period: String) async throws -> LeaderboardAPIResponse {
        LeaderboardAPIResponse(dimension: dimension, period: period, entries: [])
    }

    func fetchCrewLeaderboard(crewId: String, dimension: String, period: String) async throws -> LeaderboardAPIResponse {
        LeaderboardAPIResponse(dimension: dimension, period: period, entries: [])
    }

    // MARK: - Nutrition (AMA-1412)

    func analyzePhoto(imageBase64: String) async throws -> AnalyzePhotoAPIResponse {
        AnalyzePhotoAPIResponse(items: [], totals: MacroTotalsResponse(calories: 0, proteinG: 0, carbsG: 0, fatG: 0), notes: nil)
    }

    func lookupBarcode(code: String) async throws -> BarcodeNutritionAPIResponse {
        throw APIError.notImplemented
    }

    func parseText(text: String) async throws -> ParseTextAPIResponse {
        ParseTextAPIResponse(items: [], totals: MacroTotalsResponse(calories: 0, proteinG: 0, carbsG: 0, fatG: 0), rawText: text)
    }

    func getFuelingStatus() async throws -> FuelingStatusResponse {
        FuelingStatusResponse(status: "green", proteinPct: 0.75, caloriesPct: 0.8, hydrationPct: 0.6, message: "You're fueling well")
    }

    func checkProteinNudge() async throws -> ProteinNudgeResponse {
        ProteinNudgeResponse(shouldNudge: false, proteinCurrent: 100, proteinTarget: 150, message: "Protein on track")
    }

    // MARK: - Coach Suggestions (AMA-1412)

    func suggestWorkout(request: SuggestWorkoutRequest) async throws -> SuggestWorkoutResponse {
        throw APIError.notImplemented
    }

    func postRPEFeedback(_ feedback: RPEFeedbackRequest) async throws -> RPEFeedbackResponse {
        RPEFeedbackResponse(success: true, message: "Feedback recorded", deloadRecommended: false)
    }

    // MARK: - Program Generation (AMA-1413)

    func generateProgram(request: ProgramGenerationRequest) async throws -> ProgramGenerationResponse {
        print("[FixtureAPIService] Stub: generateProgram -> fixture job")
        return ProgramGenerationResponse(jobId: "fixture-job-001", status: "queued", programId: nil, error: nil)
    }

    func fetchGenerationStatus(jobId: String) async throws -> ProgramGenerationStatus {
        print("[FixtureAPIService] Stub: fetchGenerationStatus(\(jobId)) -> completed")
        return ProgramGenerationStatus(jobId: jobId, status: "completed", progress: 100, programId: "fixture-program-001", error: nil)
    }

    func updateProgramStatus(id: String, status: String) async throws {
        print("[FixtureAPIService] Stub: updateProgramStatus(\(id), \(status)) -> success")
    }

    func updateProgramProgress(id: String, currentWeek: Int) async throws {
        print("[FixtureAPIService] Stub: updateProgramProgress(\(id), week \(currentWeek)) -> success")
    }

    func deleteProgram(id: String) async throws {
        print("[FixtureAPIService] Stub: deleteProgram(\(id)) -> success")
    }

    func completeWorkout(workoutId: String) async throws {
        print("[FixtureAPIService] Stub: completeWorkout(\(workoutId)) -> success")
    }

    // MARK: - Volume Analytics (AMA-1414)

    func fetchVolumeAnalytics(startDate: String, endDate: String, granularity: String) async throws -> VolumeAnalyticsResponse {
        VolumeAnalyticsResponse(
            data: [],
            summary: VolumeSummary(totalVolume: 0, totalSets: 0, totalReps: 0, muscleGroupBreakdown: [:]),
            period: VolumePeriod(startDate: startDate, endDate: endDate),
            granularity: granularity
        )
    }

    // MARK: - Bulk Import (AMA-1415)

    func detectImport(request: BulkDetectRequest) async throws -> BulkDetectResponse {
        print("[FixtureAPIService] Stub: detectImport -> canned response")
        return BulkDetectResponse(
            success: true,
            jobId: "fixture-job-001",
            items: [
                DetectedItem(
                    id: "item-001",
                    sourceRef: request.sources.first ?? "fixture-source",
                    parsedTitle: "Fixture Workout A",
                    parsedExerciseCount: 6,
                    confidence: 90,
                    errors: nil,
                    warnings: nil
                )
            ],
            total: 1,
            successCount: 1,
            errorCount: 0
        )
    }

    func matchExercises(request: BulkMatchRequest) async throws -> BulkMatchResponse {
        print("[FixtureAPIService] Stub: matchExercises -> canned response")
        return BulkMatchResponse(
            success: true,
            jobId: request.jobId,
            exercises: [
                ExerciseMatch(
                    id: "ex-001",
                    originalName: "Bench Press",
                    matchedGarminName: "Bench Press",
                    confidence: 95,
                    suggestions: nil,
                    status: "matched",
                    userSelection: nil
                )
            ],
            totalExercises: 1,
            matched: 1,
            needsReview: 0
        )
    }

    func previewImport(request: BulkPreviewRequest) async throws -> BulkPreviewResponse {
        print("[FixtureAPIService] Stub: previewImport -> canned response")
        return BulkPreviewResponse(
            success: true,
            jobId: request.jobId,
            workouts: [
                PreviewWorkout(
                    id: "workout-preview-001",
                    title: "Fixture Workout A",
                    exerciseCount: 6,
                    blockCount: 2,
                    validationIssues: nil,
                    selected: true,
                    isDuplicate: false
                )
            ],
            stats: ImportStats(
                totalDetected: 1,
                totalSelected: 1,
                exercisesMatched: 1,
                exercisesNeedingReview: 0,
                duplicatesFound: 0,
                validationErrors: 0,
                validationWarnings: 0
            )
        )
    }

    func executeImport(request: BulkExecuteRequest) async throws -> BulkExecuteResponse {
        print("[FixtureAPIService] Stub: executeImport -> canned response")
        return BulkExecuteResponse(
            success: true,
            jobId: request.jobId,
            status: "running",
            message: "Import started"
        )
    }

    func fetchImportStatus(jobId: String, profileId: String) async throws -> BulkImportStatus {
        print("[FixtureAPIService] Stub: fetchImportStatus -> complete")
        return BulkImportStatus(
            success: true,
            jobId: jobId,
            status: "complete",
            progress: 100,
            results: [
                ImportResult(
                    workoutId: "workout-preview-001",
                    title: "Fixture Workout A",
                    status: "success",
                    error: nil,
                    savedWorkoutId: "saved-001"
                )
            ],
            error: nil
        )
    }

    func cancelImport(jobId: String, profileId: String) async throws {
        print("[FixtureAPIService] Stub: cancelImport(\(jobId)) -> success")
    }

    func exportUserData() async throws -> Data {
        Data("{}".utf8)
    }

    func deleteAccount() async throws {
        print("[FixtureAPIService] Stub: deleteAccount -> success")
    }
}
#endif
