//
//  LibraryDestination.swift
//  AmakaFlow
//
//  AMA-2291: Library → one detail layout for every workout source.
//

import Foundation

/// Navigation target from a Library row.
enum LibraryDestination: Hashable, Identifiable {
    case unifiedWorkout(workoutID: String)
    case knowledgeDetail(itemID: String)

    var id: String {
        switch self {
        case .unifiedWorkout(let workoutID):
            return "workout:\(workoutID)"
        case .knowledgeDetail(let itemID):
            return "knowledge:\(itemID)"
        }
    }
}

/// Resolves which detail chrome a Library entry should open.
enum LibraryDetailRouting {
    /// Saved workouts (manual / social / coach / AI / …) share one unified detail.
    static func destination(forWorkoutID workoutID: String) -> LibraryDestination {
        .unifiedWorkout(workoutID: workoutID)
    }

    /// Knowledge cards: workout-kind still open unified chrome when a matching Workout exists;
    /// otherwise knowledge preview. Non-workout kinds keep Library detail.
    static func destination(
        forKnowledgeKind kind: Components.Schemas.LibraryKind,
        itemID: String,
        matchingWorkoutID: String?
    ) -> LibraryDestination {
        switch kind {
        case .workout:
            if let matchingWorkoutID {
                return .unifiedWorkout(workoutID: matchingWorkoutID)
            }
            // Thin Proto: still open unified detail by synthesizing from the knowledge id.
            return .unifiedWorkout(workoutID: itemID)
        case .video, .article, .plan:
            return .knowledgeDetail(itemID: itemID)
        }
    }

    /// Whether a source should show the social credit row (Open in IG/TikTok).
    static func showsSocialCreditRow(source: WorkoutSource) -> Bool {
        switch source {
        case .instagram, .tiktok, .youtube:
            return true
        default:
            return WorkoutSourceProvenance.isExternal(source.rawValue)
        }
    }
}

/// Row model for the unified Library list (workouts + knowledge).
enum LibraryListEntry: Identifiable, Hashable {
    case workout(Workout)
    case knowledge(Components.Schemas.LibraryItem)

    var id: String {
        switch self {
        case .workout(let workout):
            return "workout:\(workout.id)"
        case .knowledge(let item):
            return "knowledge:\(item.id)"
        }
    }

    var title: String {
        switch self {
        case .workout(let workout):
            return workout.name
        case .knowledge(let item):
            return item.title
        }
    }

    var destination: LibraryDestination {
        switch self {
        case .workout(let workout):
            return LibraryDetailRouting.destination(forWorkoutID: workout.id)
        case .knowledge(let item):
            return LibraryDetailRouting.destination(
                forKnowledgeKind: item.kind,
                itemID: item.id,
                matchingWorkoutID: nil
            )
        }
    }
}
