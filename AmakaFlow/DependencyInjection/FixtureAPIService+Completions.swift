//
//  FixtureAPIService+Completions.swift
//  AmakaFlow
//
//  AMA-2289: Today diary completion fixtures (empty + Garmin/phone populated).
//

import Foundation

extension FixtureAPIService {
    /// Fixture completions for Today diary — empty when `UITEST_FIXTURE_STATE=empty`.
    static func diaryCompletions(limit: Int, offset: Int) -> [WorkoutCompletion] {
        if UITestEnvironment.shared.fixtureState == "empty" {
            print("[FixtureAPIService] UITEST_FIXTURE_STATE=empty → no completions")
            return []
        }
        let diary = WorkoutCompletion.todayDiarySampleData()
        if offset >= diary.count { return [] }
        return Array(diary.dropFirst(offset).prefix(limit))
    }

    /// Fixture completion detail keyed by Today diary ids.
    static func diaryCompletionDetail(id: String) -> WorkoutCompletionDetail {
        if id == "today-garmin-run" || id.hasPrefix("today-garmin") {
            return WorkoutCompletionDetail.garminTodaySample
        }
        if id == "today-phone-strength" || id.hasPrefix("today-phone") {
            return WorkoutCompletionDetail.phoneTodaySample
        }
        return WorkoutCompletionDetail.sample
    }
}
