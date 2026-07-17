//
//  FixtureAPIService+Completions.swift
//  AmakaFlow
//
//  AMA-2289: Today diary completion fixtures (empty + Garmin/phone populated).
//  AMA-2290: append phone completions after player Save so Today refreshes.
//

#if DEBUG
import Foundation

extension FixtureAPIService {
    /// In-memory Today diary deltas from live phone completions during a fixture session.
    /// Prefixed with `phone-live-` so Maestro can assert the freshly recorded row.
    private static var livePhoneDiaryCompletions: [WorkoutCompletion] = []
    private static var livePhoneSetLogsById: [String: [SetLog]] = [:]

    static func resetLivePhoneDiaryForTesting() {
        livePhoneDiaryCompletions = []
        livePhoneSetLogsById = [:]
    }

    /// Fixture completions for Today diary — empty when `UITEST_FIXTURE_STATE=empty`.
    static func diaryCompletions(limit: Int, offset: Int) -> [WorkoutCompletion] {
        if UITestEnvironment.shared.fixtureState == "empty" {
            print("[FixtureAPIService] UITEST_FIXTURE_STATE=empty → no completions")
            return []
        }
        // Newest-first: live phone sessions, then static diary samples.
        let diary = livePhoneDiaryCompletions + WorkoutCompletion.todayDiarySampleData()
        if offset >= diary.count { return [] }
        return Array(diary.dropFirst(offset).prefix(limit))
    }

    /// Fixture completion detail keyed by Today diary ids.
    static func diaryCompletionDetail(id: String) -> WorkoutCompletionDetail {
        if id.hasPrefix("phone-live-") {
            return WorkoutCompletionDetail.phoneLiveSample(
                id: id,
                from: livePhoneDiaryCompletions.first { $0.id == id },
                setLogs: livePhoneSetLogsById[id]
            )
        }
        if id == "today-lunch-run" || id == "today-garmin-run" || id.hasPrefix("today-garmin") {
            return WorkoutCompletionDetail.garminTodaySample
        }
        if id == "today-lunch-workout" || id == "today-phone-strength" || id.hasPrefix("today-phone") {
            return WorkoutCompletionDetail.phoneTodaySample
        }
        return WorkoutCompletionDetail.sample
    }

    /// AMA-2290: record a phone completion into the fixture diary (source `.phone`).
    @discardableResult
    static func recordPhoneCompletion(
        request: WorkoutCompletionRequest
    ) -> WorkoutCompletionResponse {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let startedAt = formatter.date(from: request.startedAt)
            ?? ISO8601DateFormatter().date(from: request.startedAt)
            ?? Date()
        let endedAt = formatter.date(from: request.endedAt)
            ?? ISO8601DateFormatter().date(from: request.endedAt)
            ?? startedAt.addingTimeInterval(1800)
        let duration = max(Int(endedAt.timeIntervalSince(startedAt)), 1)
        let completionId = "phone-live-\(UUID().uuidString.lowercased())"
        let completion = WorkoutCompletion(
            id: completionId,
            workoutName: request.workoutName ?? "Phone Strength",
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: duration,
            avgHeartRate: request.healthMetrics.avgHeartRate,
            maxHeartRate: request.healthMetrics.maxHeartRate,
            activeCalories: request.healthMetrics.activeCalories,
            distanceMeters: request.healthMetrics.distanceMeters,
            source: .phone,
            syncedToStrava: false,
            workoutId: request.workoutId,
            originalWorkout: nil,
            isSimulated: request.isSimulated
        )
        livePhoneDiaryCompletions.insert(completion, at: 0)
        if let setLogs = request.setLogs {
            livePhoneSetLogsById[completionId] = setLogs
        }
        print("[FixtureAPIService] AMA-2290 recorded phone completion \(completionId)")
        return WorkoutCompletionResponse(
            completionId: completionId,
            id: completionId,
            status: "completed",
            success: true
        )
    }

    static func liveSetLogs(forCompletionId id: String) -> [SetLog]? {
        livePhoneSetLogsById[id]
    }
}
#endif
