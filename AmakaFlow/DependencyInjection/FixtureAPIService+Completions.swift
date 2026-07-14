//
//  FixtureAPIService+Completions.swift
//  AmakaFlow
//
//  AMA-2289: Today diary completion fixtures (empty + Garmin/phone populated).
//

import Foundation

extension FixtureAPIService {
    func fetchCompletions(limit: Int, offset: Int) async throws -> [WorkoutCompletion] {
        // Honest empty diary when UITEST_FIXTURE_STATE=empty
        if UITestEnvironment.shared.fixtureState == "empty" {
            print("[FixtureAPIService] UITEST_FIXTURE_STATE=empty → no completions")
            return []
        }
        // Populated Today diary (Garmin + phone) without live watch pull
        let diary = WorkoutCompletion.todayDiarySampleData()
        if offset >= diary.count { return [] }
        return Array(diary.dropFirst(offset).prefix(limit))
    }

    func fetchCompletionDetail(id: String) async throws -> WorkoutCompletionDetail {
        if id == "today-garmin-run" || id.hasPrefix("today-garmin") {
            return WorkoutCompletionDetail.garminTodaySample
        }
        if id == "today-phone-strength" || id.hasPrefix("today-phone") {
            return WorkoutCompletionDetail.phoneTodaySample
        }
        return WorkoutCompletionDetail.sample
    }
}
