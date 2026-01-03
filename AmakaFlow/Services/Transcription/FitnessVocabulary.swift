//
//  FitnessVocabulary.swift
//  AmakaFlow
//
//  Fitness-specific vocabulary for transcription keyword boosting (AMA-229)
//

import Foundation

/// Manages fitness vocabulary for boosting transcription accuracy
final class FitnessVocabulary {
    // MARK: - Singleton

    static let shared = FitnessVocabulary()

    // MARK: - Properties

    /// All fitness keywords for transcription boosting
    private(set) var allKeywords: [String] = []

    /// Keywords organized by category
    private(set) var keywordsByCategory: [String: [String]] = [:]

    // MARK: - Initialization

    private init() {
        loadVocabulary()
    }

    // MARK: - Loading

    private func loadVocabulary() {
        // Load from bundled JSON if available
        if let url = Bundle.main.url(forResource: "fitness_vocabulary", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let vocabulary = try? JSONDecoder().decode(VocabularyFile.self, from: data) {
            self.keywordsByCategory = vocabulary.categories
            self.allKeywords = vocabulary.categories.values.flatMap { $0 }
        } else {
            // Fallback to embedded vocabulary
            loadEmbeddedVocabulary()
        }

        print("[FitnessVocabulary] Loaded \(allKeywords.count) keywords across \(keywordsByCategory.count) categories")
    }

    private func loadEmbeddedVocabulary() {
        keywordsByCategory = [
            "strength_exercises": [
                // Compound movements
                "squats", "deadlifts", "bench press", "overhead press", "barbell row",
                "pull ups", "chin ups", "dips", "lunges", "hip thrusts",
                "Romanian deadlifts", "sumo deadlifts", "front squats", "goblet squats",
                "Bulgarian split squats", "step ups", "leg press", "hack squats",

                // Upper body
                "bicep curls", "tricep extensions", "tricep dips", "hammer curls",
                "skull crushers", "cable flyes", "dumbbell flyes", "lateral raises",
                "front raises", "face pulls", "shrugs", "upright rows",
                "lat pulldowns", "seated rows", "T-bar rows", "pendlay rows",

                // Lower body
                "calf raises", "leg curls", "leg extensions", "glute bridges",
                "hip abductions", "hip adductions", "good mornings",

                // Core
                "planks", "crunches", "sit ups", "Russian twists", "leg raises",
                "mountain climbers", "dead bugs", "bird dogs", "ab wheel",
                "hanging leg raises", "cable crunches", "woodchops",

                // Push variations
                "push ups", "diamond push ups", "pike push ups", "decline push ups",
                "incline push ups", "close grip bench", "incline bench", "decline bench"
            ],

            "cardio_exercises": [
                // Running
                "tempo run", "interval training", "fartlek", "long run", "easy run",
                "recovery run", "hill repeats", "speed work", "strides",
                "negative splits", "progressive run", "threshold run",

                // Other cardio
                "jumping jacks", "burpees", "box jumps", "jump rope", "rowing",
                "cycling", "spinning", "elliptical", "stair climber",
                "battle ropes", "sled push", "sled pull", "farmer's walk"
            ],

            "training_methods": [
                "HIIT", "Tabata", "AMRAP", "EMOM", "circuit training", "cross training",
                "supersets", "drop sets", "pyramid sets", "giant sets", "tri-sets",
                "rest pause", "myo reps", "tempo training", "pause reps",
                "negative reps", "forced reps", "21s", "countdown sets"
            ],

            "sets_reps": [
                "reps", "sets", "rounds", "rest period", "rest for",
                "seconds", "minutes", "max reps", "to failure", "RPE",
                "one rep max", "working sets", "warm up sets", "back off sets"
            ],

            "intensity": [
                "max effort", "moderate", "light", "heavy", "bodyweight",
                "RPE 6", "RPE 7", "RPE 8", "RPE 9", "RPE 10",
                "zone 2", "zone 3", "zone 4", "zone 5",
                "easy pace", "tempo pace", "threshold pace", "race pace"
            ],

            "equipment": [
                "barbell", "dumbbell", "kettlebell", "resistance band", "medicine ball",
                "foam roller", "yoga mat", "pull up bar", "squat rack", "bench",
                "cable machine", "smith machine", "trap bar", "EZ bar",
                "battle ropes", "TRX", "bosu ball", "stability ball"
            ],

            "body_parts": [
                "chest", "back", "shoulders", "biceps", "triceps", "forearms",
                "quads", "hamstrings", "glutes", "calves", "core", "abs",
                "upper body", "lower body", "full body", "push day", "pull day", "leg day"
            ],

            "mobility_flexibility": [
                "stretching", "dynamic stretching", "static stretching",
                "foam rolling", "mobility work", "hip flexors", "thoracic spine",
                "ankle mobility", "shoulder mobility", "hip circles",
                "leg swings", "arm circles", "cat cow", "child's pose"
            ],

            "time_duration": [
                "5 minutes", "10 minutes", "15 minutes", "20 minutes",
                "25 minutes", "30 minutes", "35 minutes", "40 minutes",
                "45 minutes", "50 minutes", "55 minutes", "60 minutes",
                "75 minutes", "90 minutes", "2 hours", "half hour", "an hour"
            ],

            "distances": [
                "1K", "2K", "3K", "5K", "10K", "half marathon", "marathon",
                "100 meters", "200 meters", "400 meters", "800 meters",
                "1 mile", "2 miles", "3 miles", "5 miles", "10 miles"
            ]
        ]

        allKeywords = keywordsByCategory.values.flatMap { $0 }
    }

    // MARK: - Queries

    /// Get keywords for a specific category
    func keywords(for category: String) -> [String] {
        keywordsByCategory[category] ?? []
    }

    /// Search for keywords matching a query
    func search(_ query: String) -> [String] {
        let lowercased = query.lowercased()
        return allKeywords.filter { $0.lowercased().contains(lowercased) }
    }
}

// MARK: - Vocabulary File Model

private struct VocabularyFile: Decodable {
    let categories: [String: [String]]
}
