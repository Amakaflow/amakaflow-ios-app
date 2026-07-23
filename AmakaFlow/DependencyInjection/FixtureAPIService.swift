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
    var followedUserIds = Set<String>()
    var reviewedCoachKnowledgeActionIDs = Set<String>()
    var fixtureCoachingProfile = Components.Schemas.CoachingProfile(
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
    var pushWatchDeliveryResult: Result<Components.Schemas.WatchResendResult, Error>?
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
    var setReadinessSourcePrefCallCount = 0
    var fixtureReadinessSamples: [ReadinessSampleWriteResult] = []
    var fixtureSourcePrefs: [Components.Schemas.ReadinessSourcePref] = [
        Components.Schemas.ReadinessSourcePref(metric: "hrv", source: "apple_health"),
        Components.Schemas.ReadinessSourcePref(metric: "sleep", source: "apple_health"),
        Components.Schemas.ReadinessSourcePref(metric: "rhr", source: "garmin")
    ]
    var libraryItemsEmpty = false
    var libraryItemDetail404 = false
    /// AMA-2298: injectable delete results for Library unit / Maestro failure paths.
    var deleteKnowledgeCardResult: Result<Void, Error> = .success(())
    var deleteWorkoutResult: Result<Void, Error> = .success(())
    var deleteKnowledgeCardCalled = false
    var deleteWorkoutCalled = false
    var lastDeletedKnowledgeCardID: String?
    var lastDeletedWorkoutID: String?
    /// In-memory workout cache so fixture deletes survive reload without app relaunch.
    var fixtureWorkoutsCache: [Workout]?
    var fixtureMessagingDeliveryLive = false
    var fixtureMessagingChannels: [Components.Schemas.MessagingChannel] = [
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
    var fixtureLibraryItems: [Components.Schemas.LibraryItem] = [
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
    var fixtureLibraryItemDetails: [String: Components.Schemas.LibraryItemDetail] = [
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
    var fixtureDevices: [Components.Schemas.PairedDevice] = [
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
    var fixtureWatchDeliveryStatuses: [String: Components.Schemas.WatchDeliveryStatus] = [
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
        try loadedFixtureWorkouts()
    }

    /// Cache-backed fixture workouts so deletes persist without relaunch.
    /// Preserves `UITEST_FIXTURE_STATE=empty` (`[]`) and `=error` (throws).
    func loadedFixtureWorkouts() throws -> [Workout] {
        if let fixtureWorkoutsCache {
            return fixtureWorkoutsCache
        }
        let loaded = try FixtureLoader.loadWorkouts()
        fixtureWorkoutsCache = loaded
        return loaded
    }

    /// Guaranteed strength fixture for phone-first record → backfill visual / dogfood path.
    static let phoneStrengthFixtureWorkout = Workout(
        id: "fixture-emom-001",
        name: "Manual EMOM Strength",
        sport: .strength,
        duration: 1200,
        intervals: [
            .warmup(seconds: 120, target: nil),
            .reps(sets: 3, reps: 5, name: "Power Clean", load: "70% 1RM", restSec: 30, followAlongUrl: nil),
            .reps(sets: 3, reps: 8, name: "Push Press", load: nil, restSec: 45, followAlongUrl: nil),
            .cooldown(seconds: 120, target: nil)
        ],
        description: "Every minute on the minute — phone strength backfill seed (AMA-2290)",
        source: .manual
    )

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

    /// Keep in-memory Library fixtures aligned with create/edit saves.
    func upsertFixtureWorkout(_ workout: Workout) {
        var cache = (try? loadedFixtureWorkouts()) ?? []
        if let index = cache.firstIndex(where: { $0.id == workout.id }) {
            cache[index] = workout
        } else {
            cache.insert(workout, at: 0)
        }
        fixtureWorkoutsCache = cache
    }

}
#endif
