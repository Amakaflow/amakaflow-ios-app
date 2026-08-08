//
//  WatchItemViewModel+Demo.swift
//  AmakaFlow
//
//  AMA-2388: demo / dogfood placeholders for Watch Item when prefs + store
//  have not seeded a real baseline yet. Kept out of the main VM file for
//  SwiftLint file_length.
//

import Foundation

@MainActor
extension WatchItemViewModel {
    static func demoPills(isApple: Bool, title: String) -> [String] {
        let isEMOM = title.uppercased().contains("EMOM")
        if isApple {
            return ["9 STEPS", "MOBILITY ×2", "RAMPS ×1", "OPEN REST"]
        }
        if isEMOM {
            return ["4 STEPS", "EMOM 10 MIN", "NO PREP", "LAP REST"]
        }
        return ["6 STEPS", "MOBILITY ×1", "NO RAMPS", "OPEN REST"]
    }

    static func demoWarmupNames(for title: String) -> [String] {
        if title.uppercased().contains("EMOM") {
            return ["Power Clean", "Push Press"]
        }
        return ["Bench Press", "Back Squat", "Romanian Deadlift"]
    }

    static func demoConfig(isApple: Bool, title: String) -> WatchItemConfigState {
        let mobility: [EnrichmentActivityPref] = [
            EnrichmentActivityPref(
                name: "Ski erg",
                goal: try? ActivityGoal(kind: .distance, value: 500)
            ),
            EnrichmentActivityPref(
                name: "Jump rope",
                durationSec: 120,
                goal: try? ActivityGoal(kind: .time, value: 120)
            )
        ]
        let cooldown = WorkoutEnrichmentMutations.defaultCooldownActivities()
        let names = demoWarmupNames(for: title)
        let ramps: [PerExerciseRamp] = names.prefix(1).map { name in
            PerExerciseRamp(
                exerciseRef: name,
                enabled: true,
                sets: WorkoutEnrichmentMutations.defaultRampSets()
            )
        }
        return WatchItemConfigState(
            mobilityActivities: mobility,
            cooldownActivities: cooldown,
            perExerciseRamps: ramps,
            restOpen: true,
            restSec: 60
        )
    }

    static func demoStepSections(title: String) -> [PreviewSection] {
        [
            PreviewSection(
                accent: .mobility,
                band: "MOBILITY",
                tag: nil,
                steps: [
                    PreviewStep(number: 1, title: "Ski erg", detail: "500 m", restChip: nil),
                    PreviewStep(number: 2, title: "Jump rope", detail: "2:00", restChip: nil)
                ]
            ),
            PreviewSection(
                accent: .work,
                band: "WARM-UP · \(demoWarmupNames(for: title).first ?? "BENCH")",
                tag: nil,
                steps: [
                    PreviewStep(number: 3, title: "8 × ~40%", detail: "easy", restChip: nil),
                    PreviewStep(number: 4, title: "5 × ~60%", detail: nil, restChip: nil),
                    PreviewStep(number: 5, title: "3 × ~80%", detail: nil, restChip: nil)
                ]
            ),
            PreviewSection(
                accent: .work,
                band: "WORK",
                tag: nil,
                steps: demoWarmupNames(for: title).enumerated().map { idx, name in
                    PreviewStep(number: 6 + idx, title: name, detail: "3 × 5", restChip: nil)
                }
            )
        ]
    }
}
