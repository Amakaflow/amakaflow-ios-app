//
//  UnifiedWorkoutDetailView+Previews.swift
//  AmakaFlow
//
//  DEBUG previews extracted so UnifiedWorkoutDetailView stays under SwiftLint file_length.
//

import SwiftUI

#if DEBUG
#Preview("Social") {
    NavigationStack {
        UnifiedWorkoutDetailView(
            workout: Workout(
                name: "DB Full-body AMRAP",
                sport: .cardio,
                duration: 1200,
                blocks: [
                    Block(
                        label: "Round 1–3",
                        structure: .amrap,
                        rounds: 3,
                        exercises: [
                            Exercise(
                                name: "Wall balls",
                                canonicalName: nil,
                                sets: nil,
                                reps: "20",
                                durationSeconds: nil,
                                load: ExerciseLoad(value: 0, unit: "med ball 6 kg"),
                                restSeconds: nil,
                                distance: nil,
                                notes: nil,
                                focus: "Quads · Shoulders",
                                supersetGroup: nil
                            ),
                            Exercise(
                                name: "Barbell thrusters",
                                canonicalName: nil,
                                sets: nil,
                                reps: "12",
                                durationSeconds: nil,
                                load: ExerciseLoad(value: 40, unit: "kg"),
                                restSeconds: nil,
                                distance: nil,
                                notes: nil,
                                focus: "Full body",
                                supersetGroup: nil
                            ),
                            Exercise(
                                name: "Burpee broad jumps",
                                canonicalName: nil,
                                sets: nil,
                                reps: "10",
                                durationSeconds: nil,
                                load: ExerciseLoad(value: 0, unit: "bodyweight"),
                                restSeconds: nil,
                                distance: nil,
                                notes: nil,
                                focus: "Full body",
                                supersetGroup: nil
                            )
                        ]
                    ),
                    Block(
                        label: "Finisher",
                        structure: .circuit,
                        rounds: 1,
                        exercises: [
                            Exercise(
                                name: "Sled push",
                                canonicalName: nil,
                                sets: 2,
                                reps: nil,
                                durationSeconds: nil,
                                load: ExerciseLoad(value: 80, unit: "kg"),
                                restSeconds: nil,
                                distance: 20,
                                notes: nil,
                                focus: "Legs · Core",
                                supersetGroup: nil
                            )
                        ]
                    )
                ],
                description: "Four main rounds of full-body conditioning plus a sled finisher. Parsed from the reel; nothing saved yet.",
                source: .instagram,
                sourceUrl: "https://instagram.com/reel/abc",
                creatorName: "gospelofgainz"
            ),
            garminPairedOverride: true,
            appleWatchReachableOverride: false
        )
        .environmentObject(WorkoutsViewModel())
    }
}

#Preview("Coach") {
    NavigationStack {
        UnifiedWorkoutDetailView(
            workout: Workout(
                name: "Lower body — posterior",
                sport: .strength,
                duration: 3120,
                blocks: [
                    Block(
                        label: "Main lifts",
                        structure: .straight,
                        rounds: 1,
                        exercises: [
                            Exercise(
                                name: "Back squat",
                                canonicalName: nil,
                                sets: 3,
                                reps: "5",
                                durationSeconds: nil,
                                load: nil,
                                restSeconds: nil,
                                distance: nil,
                                notes: "build to heavy",
                                focus: "Quads · Glutes",
                                supersetGroup: nil
                            ),
                            Exercise(
                                name: "Romanian deadlift",
                                canonicalName: nil,
                                sets: 3,
                                reps: "8",
                                durationSeconds: nil,
                                load: ExerciseLoad(value: 70, unit: "kg"),
                                restSeconds: nil,
                                distance: nil,
                                notes: nil,
                                focus: "Hamstrings · Glutes",
                                supersetGroup: nil
                            )
                        ]
                    ),
                    Block(
                        label: "Accessories",
                        structure: .straight,
                        rounds: 1,
                        exercises: [
                            Exercise(
                                name: "Split squat",
                                canonicalName: nil,
                                sets: 2,
                                reps: "10",
                                durationSeconds: nil,
                                load: nil,
                                restSeconds: nil,
                                distance: nil,
                                notes: nil,
                                focus: "Quads · Glutes",
                                supersetGroup: nil
                            )
                        ]
                    )
                ],
                description: "Posterior-chain strength: squat, hinge, single-leg. From your trainer.",
                source: .coach,
                sourceUrl: "Coach Mike",
                creatorName: "Coach Mike",
                createdAt: Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 1))
            ),
            garminPairedOverride: false,
            appleWatchReachableOverride: false
        )
        .environmentObject(WorkoutsViewModel())
    }
}

#Preview("Manual") {
    NavigationStack {
        UnifiedWorkoutDetailView(
            workout: Workout(
                name: "Hyrox Sim — Stations 1–4",
                sport: .cardio,
                duration: 2700,
                blocks: [
                    Block(
                        label: "Stations 1–4",
                        structure: .circuit,
                        rounds: 2,
                        exercises: [
                            Exercise(
                                name: "SkiErg",
                                canonicalName: nil,
                                sets: nil,
                                reps: nil,
                                durationSeconds: nil,
                                load: nil,
                                restSeconds: nil,
                                distance: 250,
                                notes: "Full body",
                                supersetGroup: nil
                            )
                        ]
                    )
                ],
                description: "Race-pace simulation of the first four stations with run intervals between each.",
                source: .manual
            ),
            garminPairedOverride: false,
            appleWatchReachableOverride: true
        )
        .environmentObject(WorkoutsViewModel())
    }
}
#endif
