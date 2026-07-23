//
//  FixtureAPIService+DevicesLibrary.swift
//  AmakaFlow
//
//  Devices / library / messaging / coaching — SwiftLint split.
//

#if DEBUG
import Foundation

extension FixtureAPIService {
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
        if workoutId.contains("failed"),
           let failed = fixtureWatchDeliveryStatuses["fixture-watch-failed"] {
            return failed
        }
        if workoutId.contains("confirmed"),
           let confirmed = fixtureWatchDeliveryStatuses["fixture-watch-confirmed_on_device"] {
            return confirmed
        }
        if let pushed = fixtureWatchDeliveryStatuses["fixture-watch-pushed"] {
            return pushed
        }
        return Components.Schemas.WatchDeliveryStatus(
            canResend: true,
            occurredAt: "2026-05-29T13:00:00Z",
            state: .generated,
            subtitle: "Queued for Garmin delivery.",
            title: "Pushed"
        )
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

    func pushWatchDelivery(workoutId: String) async throws -> Components.Schemas.WatchResendResult {
        if let pushWatchDeliveryResult {
            return try pushWatchDeliveryResult.get()
        }
        fixtureWatchDeliveryStatuses[workoutId] = Components.Schemas.WatchDeliveryStatus(
            canResend: false,
            occurredAt: "2026-05-29T13:02:00Z",
            state: .pushed,
            subtitle: "Sent to your watch — waiting for sync",
            title: "Sent to watch"
        )
        print("[FixtureAPIService] Stub: pushWatchDelivery(\(workoutId)) -> success")
        return Components.Schemas.WatchResendResult(deliveryIds: ["fixture-push-\(workoutId)"], success: true)
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

    /// AMA-2298: mutate in-memory library fixtures (no network).
    func deleteKnowledgeCard(id: String) async throws {
        deleteKnowledgeCardCalled = true
        lastDeletedKnowledgeCardID = id
        try deleteKnowledgeCardResult.get()
        fixtureLibraryItems.removeAll { $0.id == id }
        fixtureLibraryItemDetails.removeValue(forKey: id)
        print("[FixtureAPIService] Stub: deleteKnowledgeCard(\(id)) -> success")
    }

    /// AMA-2298: mutate in-memory workout fixtures (no network).
    func deleteWorkout(id: String) async throws {
        deleteWorkoutCalled = true
        lastDeletedWorkoutID = id
        try deleteWorkoutResult.get()
        var workouts = try loadedFixtureWorkouts()
        workouts.removeAll { $0.id == id }
        fixtureWorkoutsCache = workouts
        print("[FixtureAPIService] Stub: deleteWorkout(\(id)) -> success")
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
}
#endif
