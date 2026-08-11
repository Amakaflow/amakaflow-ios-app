//
//  WorkoutEnrichmentPushSheet+Previews.swift
//  AmakaFlow
//
//  AMA-2408 — DEBUG previews split from the sheet for SwiftLint file_length.
//

#if DEBUG
import SwiftUI

#Preview("Garmin") {
    WorkoutEnrichmentPushSheet(
        plan: WorkoutEnrichmentPushPlanner.Plan(
            offers: [
                WorkoutEnrichmentPushPlanner.Offer(
                    kind: .sessionWarmup,
                    isChecked: true,
                    wasTombstoned: false,
                    detail: "Jump Rope · until Lap",
                    target: .garmin
                ),
                WorkoutEnrichmentPushPlanner.Offer(
                    kind: .betweenSetRest,
                    isChecked: true,
                    wasTombstoned: false,
                    detail: "60s between sets",
                    target: .garmin
                ),
                WorkoutEnrichmentPushPlanner.Offer(
                    kind: .exerciseWarmupSets,
                    isChecked: false,
                    wasTombstoned: true,
                    detail: "2 warm-up sets (8 · 5 reps) on 3 exercises",
                    candidateExerciseIds: [],
                    candidateExerciseNames: ["Deadlift", "Overhead Press", "Leg Press"],
                    target: .garmin
                )
            ],
            target: .garmin
        ),
        prefs: .defaults,
        onConfirm: { _ in },
        onSkip: {},
        onClose: {}
    )
    .presentationDetents([.large])
}

#Preview("Apple") {
    WorkoutEnrichmentPushSheet(
        plan: WorkoutEnrichmentPushPlanner.Plan(
            offers: [
                WorkoutEnrichmentPushPlanner.Offer(
                    kind: .sessionWarmup,
                    isChecked: true,
                    wasTombstoned: false,
                    detail: "Jump Rope · until tap",
                    target: .apple
                ),
                WorkoutEnrichmentPushPlanner.Offer(
                    kind: .exerciseWarmupSets,
                    isChecked: true,
                    wasTombstoned: false,
                    detail: "2 warm-up sets (8 · 5 reps) on 2 exercises",
                    candidateExerciseNames: ["Deadlift", "Overhead Press"],
                    target: .apple
                ),
                WorkoutEnrichmentPushPlanner.Offer(
                    kind: .betweenSetRest,
                    isChecked: true,
                    wasTombstoned: false,
                    detail: "Open rest between sets",
                    target: .apple
                ),
                WorkoutEnrichmentPushPlanner.Offer(
                    kind: .cooldown,
                    isChecked: false,
                    wasTombstoned: false,
                    detail: "Stretch flow · 3:00 → Treadmill · open",
                    target: .apple
                )
            ],
            target: .apple
        ),
        prefs: .defaults,
        onConfirm: { _ in },
        onSkip: {},
        onClose: {}
    )
    .presentationDetents([.large])
}
#endif
