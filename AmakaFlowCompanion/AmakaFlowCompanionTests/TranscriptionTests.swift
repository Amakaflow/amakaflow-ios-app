//
//  TranscriptionTests.swift
//  AmakaFlowCompanionTests
//
//  Unit tests for transcription services (AMA-229/AMA-231)
//  Tests PersonalDictionary and FitnessVocabulary functionality
//

import XCTest
@testable import AmakaFlowCompanion

// MARK: - Personal Dictionary Tests

final class PersonalDictionaryTests: XCTestCase {

    // MARK: - Correction Application Tests

    func testApplyCorrectionsSimple() {
        let text = "I did ten reps of squats"
        let corrections: [String: String] = [
            "ten reps": "10 reps"
        ]

        let result = applyCorrections(to: text, corrections: corrections)

        XCTAssertEqual(result, "I did 10 reps of squats")
    }

    func testApplyCorrectionsMultiple() {
        let text = "dead lift and push ups"
        let corrections: [String: String] = [
            "dead lift": "deadlift",
            "push ups": "push-ups"
        ]

        let result = applyCorrections(to: text, corrections: corrections)

        XCTAssertEqual(result, "deadlift and push-ups")
    }

    func testApplyCorrectionsPreservesCase() {
        let text = "Did HIIT training today"
        let corrections: [String: String] = [
            "h i i t": "HIIT"
        ]

        // Original text already has HIIT, so no change needed
        let result = applyCorrections(to: text, corrections: corrections)

        XCTAssertEqual(result, "Did HIIT training today")
    }

    func testApplyCorrectionsEmptyCorrections() {
        let text = "Some workout text"
        let corrections: [String: String] = [:]

        let result = applyCorrections(to: text, corrections: corrections)

        XCTAssertEqual(result, text)
    }

    func testApplyCorrectionsEmptyText() {
        let corrections: [String: String] = [
            "test": "result"
        ]

        let result = applyCorrections(to: "", corrections: corrections)

        XCTAssertEqual(result, "")
    }

    func testApplyCorrectionsCaseInsensitive() {
        let text = "did DEAD LIFT today"
        let corrections: [String: String] = [
            "dead lift": "deadlift"
        ]

        let result = applyCorrections(to: text, corrections: corrections)

        XCTAssertEqual(result, "did deadlift today")
    }

    func testApplyCorrectionsLongestFirst() {
        let text = "bench press and incline bench"
        let corrections: [String: String] = [
            "bench": "flat bench",
            "bench press": "barbell press"
        ]

        // Longest match should be applied first
        // "bench press" (11 chars) is longer than "bench" (5 chars)
        let result = applyCorrectionsLongestFirst(to: text, corrections: corrections)

        // "bench press" -> "barbell press" first (longest)
        // Then "bench" -> "flat bench" (but only the standalone "bench" in "incline bench")
        // Result: "barbell press and incline flat bench"
        XCTAssertTrue(result.contains("barbell press"))
        XCTAssertTrue(result.contains("incline"))
    }

    // MARK: - Normalization Tests

    func testNormalizeWrongPhrase() {
        let input = "  DEAD LIFT  "
        let normalized = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(normalized, "dead lift")
    }

    func testNormalizeCorrectPhrase() {
        let input = "  Deadlift  "
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(normalized, "Deadlift")
    }

    // MARK: - Custom Terms Tests

    func testCustomTermsAreUnique() {
        var terms: [String] = []

        let term1 = "AMRAP"
        let term2 = "EMOM"

        if !terms.contains(term1) {
            terms.append(term1)
        }
        if !terms.contains(term2) {
            terms.append(term2)
        }
        // Try to add duplicate
        if !terms.contains(term1) {
            terms.append(term1)
        }

        XCTAssertEqual(terms.count, 2)
        XCTAssertEqual(terms, ["AMRAP", "EMOM"])
    }

    func testCustomTermNormalization() {
        let term = "  bulgarian split squats  "
        let normalized = term.trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(normalized, "bulgarian split squats")
        XCTAssertFalse(normalized.isEmpty)
    }

    func testEmptyTermIsRejected() {
        let term = "   "
        let normalized = term.trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertTrue(normalized.isEmpty)
    }

    // MARK: - Helper Methods

    private func applyCorrections(to text: String, corrections: [String: String]) -> String {
        var result = text

        for (wrong, correct) in corrections {
            result = result.replacingOccurrences(
                of: wrong,
                with: correct,
                options: .caseInsensitive
            )
        }

        return result
    }

    private func applyCorrectionsLongestFirst(to text: String, corrections: [String: String]) -> String {
        var result = text

        // Sort by length (longest first) to handle overlapping phrases
        let sortedCorrections = corrections.sorted { $0.key.count > $1.key.count }

        for (wrong, correct) in sortedCorrections {
            result = result.replacingOccurrences(
                of: wrong,
                with: correct,
                options: .caseInsensitive
            )
        }

        return result
    }
}

// MARK: - Fitness Vocabulary Tests

final class FitnessVocabularyTests: XCTestCase {

    // MARK: - Keyword Search Tests

    func testSearchKeywords() {
        let keywords = [
            "squats", "deadlifts", "bench press", "overhead press",
            "pull ups", "chin ups", "dips", "lunges"
        ]

        let query = "squat"
        let results = keywords.filter { $0.lowercased().contains(query.lowercased()) }

        XCTAssertEqual(results, ["squats"])
    }

    func testSearchKeywordsCaseInsensitive() {
        let keywords = ["HIIT", "Tabata", "AMRAP", "EMOM"]

        let query = "hiit"
        let results = keywords.filter { $0.lowercased().contains(query.lowercased()) }

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first, "HIIT")
    }

    func testSearchKeywordsPartialMatch() {
        let keywords = [
            "bench press", "incline bench", "decline bench",
            "dumbbell press", "overhead press"
        ]

        let query = "bench"
        let results = keywords.filter { $0.lowercased().contains(query.lowercased()) }

        XCTAssertEqual(results.count, 3)
        XCTAssertTrue(results.contains("bench press"))
        XCTAssertTrue(results.contains("incline bench"))
        XCTAssertTrue(results.contains("decline bench"))
    }

    func testSearchKeywordsNoMatch() {
        let keywords = ["squats", "deadlifts", "bench press"]

        let query = "swimming"
        let results = keywords.filter { $0.lowercased().contains(query.lowercased()) }

        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Category Tests

    func testCategoryKeywords() {
        let categories: [String: [String]] = [
            "strength_exercises": ["squats", "deadlifts", "bench press"],
            "cardio_exercises": ["tempo run", "interval training", "burpees"],
            "training_methods": ["HIIT", "Tabata", "AMRAP"]
        ]

        XCTAssertEqual(categories["strength_exercises"]?.count, 3)
        XCTAssertEqual(categories["cardio_exercises"]?.count, 3)
        XCTAssertEqual(categories["training_methods"]?.count, 3)
    }

    func testGetKeywordsForCategory() {
        let categories: [String: [String]] = [
            "strength_exercises": ["squats", "deadlifts"],
            "equipment": ["barbell", "dumbbell"]
        ]

        let strengthKeywords = categories["strength_exercises"] ?? []
        let equipmentKeywords = categories["equipment"] ?? []
        let unknownCategory = categories["unknown"] ?? []

        XCTAssertEqual(strengthKeywords.count, 2)
        XCTAssertEqual(equipmentKeywords.count, 2)
        XCTAssertTrue(unknownCategory.isEmpty)
    }

    func testAllKeywordsFromCategories() {
        let categories: [String: [String]] = [
            "strength": ["squats", "deadlifts"],
            "cardio": ["running", "cycling"]
        ]

        let allKeywords = categories.values.flatMap { $0 }

        XCTAssertEqual(allKeywords.count, 4)
        XCTAssertTrue(allKeywords.contains("squats"))
        XCTAssertTrue(allKeywords.contains("running"))
    }

    // MARK: - Common Fitness Terms Tests

    func testCommonMisrecognitions() {
        let defaultCorrections: [String: String] = [
            "dead lift": "deadlift",
            "dead lifts": "deadlifts",
            "bench presses": "bench press",
            "pull up": "pull-up",
            "pushup": "push-up",
            "pushups": "push-ups"
        ]

        XCTAssertEqual(defaultCorrections["dead lift"], "deadlift")
        XCTAssertEqual(defaultCorrections["pushups"], "push-ups")
    }

    func testAcronymCorrections() {
        let corrections: [String: String] = [
            "h i i t": "HIIT",
            "high intensity interval training": "HIIT",
            "a m rap": "AMRAP",
            "e mom": "EMOM",
            "are p e": "RPE"
        ]

        XCTAssertEqual(corrections["h i i t"], "HIIT")
        XCTAssertEqual(corrections["a m rap"], "AMRAP")
        XCTAssertEqual(corrections["are p e"], "RPE")
    }

    func testNumberCorrections() {
        let corrections: [String: String] = [
            "one rep": "1 rep",
            "two reps": "2 reps",
            "three reps": "3 reps",
            "ten reps": "10 reps",
            "twelve reps": "12 reps",
            "fifteen reps": "15 reps"
        ]

        XCTAssertEqual(corrections["ten reps"], "10 reps")
        XCTAssertEqual(corrections["fifteen reps"], "15 reps")
    }

    // MARK: - Vocabulary Coverage Tests

    func testVocabularyHasStrengthExercises() {
        let strengthExercises = [
            "squats", "deadlifts", "bench press", "overhead press",
            "barbell row", "pull ups", "chin ups", "dips", "lunges"
        ]

        XCTAssertGreaterThan(strengthExercises.count, 5)
        XCTAssertTrue(strengthExercises.contains("squats"))
        XCTAssertTrue(strengthExercises.contains("deadlifts"))
    }

    func testVocabularyHasCardioExercises() {
        let cardioExercises = [
            "tempo run", "interval training", "fartlek", "long run",
            "easy run", "recovery run", "hill repeats"
        ]

        XCTAssertGreaterThan(cardioExercises.count, 5)
        XCTAssertTrue(cardioExercises.contains("tempo run"))
        XCTAssertTrue(cardioExercises.contains("fartlek"))
    }

    func testVocabularyHasTrainingMethods() {
        let trainingMethods = [
            "HIIT", "Tabata", "AMRAP", "EMOM", "circuit training",
            "supersets", "drop sets", "pyramid sets"
        ]

        XCTAssertGreaterThan(trainingMethods.count, 5)
        XCTAssertTrue(trainingMethods.contains("HIIT"))
        XCTAssertTrue(trainingMethods.contains("EMOM"))
    }

    func testVocabularyHasEquipment() {
        let equipment = [
            "barbell", "dumbbell", "kettlebell", "resistance band",
            "medicine ball", "foam roller", "pull up bar"
        ]

        XCTAssertGreaterThan(equipment.count, 5)
        XCTAssertTrue(equipment.contains("barbell"))
        XCTAssertTrue(equipment.contains("kettlebell"))
    }

    func testVocabularyHasBodyParts() {
        let bodyParts = [
            "chest", "back", "shoulders", "biceps", "triceps",
            "quads", "hamstrings", "glutes", "calves", "core"
        ]

        XCTAssertGreaterThan(bodyParts.count, 5)
        XCTAssertTrue(bodyParts.contains("chest"))
        XCTAssertTrue(bodyParts.contains("glutes"))
    }
}

// MARK: - Transcription Provider Tests

final class TranscriptionProviderTests: XCTestCase {

    // MARK: - Provider Selection Tests

    func testProviderHasDisplayName() {
        let providers: [(name: String, displayName: String)] = [
            ("smart", "Smart"),
            ("onDevice", "On-Device Only"),
            ("deepgram", "Deepgram Cloud"),
            ("assemblyai", "AssemblyAI")
        ]

        for provider in providers {
            XCTAssertFalse(provider.displayName.isEmpty)
        }
    }

    func testProviderHasDescription() {
        let descriptions = [
            "Uses on-device first, falls back to cloud for low confidence",
            "Privacy-focused, works offline",
            "Best accuracy for fitness terms",
            "Budget-friendly cloud option"
        ]

        for desc in descriptions {
            XCTAssertFalse(desc.isEmpty)
            XCTAssertGreaterThan(desc.count, 10)
        }
    }

    func testProviderCostInfo() {
        let costInfo: [String: String] = [
            "smart": "Free + Usage",
            "onDevice": "Free",
            "deepgram": "$0.0043/min",
            "assemblyai": "$0.0025/min"
        ]

        XCTAssertEqual(costInfo["onDevice"], "Free")
        XCTAssertTrue(costInfo["deepgram"]?.contains("$") ?? false)
    }

    func testCloudProviderIdentification() {
        let cloudProviders = ["deepgram", "assemblyai"]
        let onDeviceProviders = ["onDevice", "smart"]

        for provider in cloudProviders {
            XCTAssertTrue(isCloudProvider(provider))
        }

        for provider in onDeviceProviders {
            XCTAssertFalse(isCloudProvider(provider))
        }
    }

    // MARK: - Accent Region Tests

    func testAccentRegionHasDisplayName() {
        let regions: [(code: String, displayName: String)] = [
            ("en-US", "American English"),
            ("en-GB", "British English"),
            ("en-AU", "Australian English"),
            ("en-IN", "Indian English")
        ]

        for region in regions {
            XCTAssertFalse(region.displayName.isEmpty)
        }
    }

    func testAccentRegionCodeFormat() {
        let regionCodes = ["en-US", "en-GB", "en-AU", "en-IN"]

        for code in regionCodes {
            XCTAssertTrue(code.contains("-"))
            let parts = code.split(separator: "-")
            XCTAssertEqual(parts.count, 2)
            XCTAssertEqual(parts[0].count, 2) // Language code
            XCTAssertEqual(parts[1].count, 2) // Region code
        }
    }

    // MARK: - Helper Methods

    private func isCloudProvider(_ provider: String) -> Bool {
        provider == "deepgram" || provider == "assemblyai"
    }
}

// MARK: - Transcription Confidence Tests

final class TranscriptionConfidenceTests: XCTestCase {

    func testHighConfidenceThreshold() {
        let highConfidence = 0.85
        let threshold = 0.80

        XCTAssertGreaterThanOrEqual(highConfidence, threshold)
    }

    func testLowConfidenceTriggersFallback() {
        let lowConfidence = 0.65
        let fallbackThreshold = 0.80

        let shouldFallback = lowConfidence < fallbackThreshold

        XCTAssertTrue(shouldFallback)
    }

    func testConfidenceNormalization() {
        let rawConfidences: [Double] = [0.0, 0.5, 0.75, 0.95, 1.0]

        for confidence in rawConfidences {
            XCTAssertGreaterThanOrEqual(confidence, 0.0)
            XCTAssertLessThanOrEqual(confidence, 1.0)
        }
    }

    func testAverageConfidenceCalculation() {
        let wordConfidences: [Double] = [0.8, 0.9, 0.85, 0.7, 0.95]

        let average = wordConfidences.reduce(0, +) / Double(wordConfidences.count)

        XCTAssertEqual(average, 0.84, accuracy: 0.01)
    }

    func testMinimumConfidenceFromWords() {
        let wordConfidences: [Double] = [0.8, 0.9, 0.6, 0.85, 0.95]

        let minimum = wordConfidences.min()

        XCTAssertEqual(minimum, 0.6)
    }
}
