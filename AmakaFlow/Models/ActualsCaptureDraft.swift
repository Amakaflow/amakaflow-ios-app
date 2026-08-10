//
//  ActualsCaptureDraft.swift
//  AmakaFlow
//
//  AMA-2387 Map v2: draft produced by Builder / photo before match-save.
//

import Foundation

/// Handoff policy when photo import completes inside a parent-owned cover stack.
enum ActualsPhotoCaptureHandoff {
    /// When the parent supplies `onCaptureComplete`, it owns the next presentation —
    /// the importer must not call `dismiss()` or the Map `fullScreenCover` closes.
    static func shouldDismissImporter(hasCaptureCompleteHandler: Bool) -> Bool {
        !hasCaptureCompleteHandler
    }
}

/// Local capture result — not yet verified; match-save decides Library + attach.
struct ActualsCaptureDraft: Identifiable, Equatable {
    /// Default Builder title before the athlete names the session.
    static let placeholderTitle = "Captured session"

    let id: String
    var title: String
    var blockSummaries: [String]
    var estimatedMinutes: Int
    var source: Source
    /// Persist payload when "Also save to Library" is on (normal `saveWorkout` path).
    var sport: String
    var intervals: [WorkoutSaveInterval]
    var blocks: [SocialImportBlock]?

    enum Source: String, Equatable {
        case built
        case photo
    }

    static func == (lhs: ActualsCaptureDraft, rhs: ActualsCaptureDraft) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.blockSummaries == rhs.blockSummaries
            && lhs.estimatedMinutes == rhs.estimatedMinutes
            && lhs.source == rhs.source
            && lhs.sport == rhs.sport
            && lhs.intervals == rhs.intervals
            && lhs.blocks == rhs.blocks
    }

    var blocksLabel: String {
        let count = max(blockSummaries.count, 1)
        return "\(count) BLOCK\(count == 1 ? "" : "S")"
    }

    func toWorkoutSaveRequest() -> WorkoutSaveRequest {
        WorkoutSaveRequest(
            name: title.trimmingCharacters(in: .whitespacesAndNewlines),
            sport: sport,
            intervals: intervals,
            source: WorkoutSource.manual.rawValue,
            blocks: blocks,
            canonicalFieldsProvided: false
        )
    }

    /// Best-effort Workout for Strava structure + fill-in seeding after match-save.
    func toWorkoutForMatch() -> Workout? {
        guard let blocks, !blocks.isEmpty else { return nil }
        let mapped: [Block] = blocks.map { block in
            Block(
                label: block.label,
                structure: block.rounds > 1 ? .circuit : .straight,
                rounds: max(1, block.rounds),
                exercises: block.exercises.map { $0.toExercise() }
            )
        }
        guard mapped.contains(where: { !$0.exercises.isEmpty }) else { return nil }
        return Workout(
            id: id,
            name: title,
            sport: WorkoutSport.parse(sport),
            duration: max(0, estimatedMinutes * 60),
            blocks: mapped,
            description: nil,
            source: .manual,
            sourceUrl: nil,
            creatorName: nil
        )
    }

    static func sampleHyrox() -> ActualsCaptureDraft {
        let blocks = [
            SocialImportBlock(
                label: "Stations",
                rounds: 1,
                exercises: [
                    SocialImportExercise(name: "Ski erg", distanceMeters: 500),
                    SocialImportExercise(name: "Sled push", sets: 4, distanceMeters: 25),
                    SocialImportExercise(name: "Wall balls", sets: 3, reps: 25),
                    SocialImportExercise(name: "Burpee broad jump", sets: 3, reps: 12)
                ]
            )
        ]
        return ActualsCaptureDraft(
            id: UUID().uuidString,
            title: "Hyrox class — stations",
            blockSummaries: [
                "Ski erg — 500 m",
                "Sled push — 4 × 25 m",
                "Wall balls — 3 × 25",
                "Burpee broad jump — 3 × 12"
            ],
            estimatedMinutes: 45,
            source: .built,
            sport: WorkoutSport.strength.rawValue,
            intervals: [],
            blocks: blocks
        )
    }
}

enum ActualsCaptureContext {
    /// Mono detail for lime banner: `WED · 18:10 · 44 MIN · 486 CAL · FROM GARMIN`
    static func bannerDetail(for activity: ActualsUnmappedActivity) -> String {
        let day = Self.dayFormatter.string(from: activity.startDate).uppercased()
        let time = Self.timeFormatter.string(from: activity.startDate)
        let minutes = max(1, Int((activity.durationSeconds / 60).rounded()))
        let source = ActualsCopy.sourceDisplayName(activity.provider).uppercased()
        var parts = ["\(day) · \(time)", "\(minutes) MIN"]
        if let cal = activity.calories {
            parts.append("\(Int(cal.rounded())) CAL")
        }
        parts.append("FROM \(source)")
        return parts.joined(separator: " · ")
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
