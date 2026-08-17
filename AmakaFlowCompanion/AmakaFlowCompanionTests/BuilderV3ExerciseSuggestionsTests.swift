//
//  BuilderV3ExerciseSuggestionsTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2443 slice 2b — tests for suggestion ranking and did-you-mean helpers.
//

import XCTest
@testable import AmakaFlowCompanion

final class BuilderV3ExerciseSuggestionsTests: XCTestCase {
    
    // MARK: - suggestedExercises tests
    
    func testSuggestedExercises_emptyCanvas_returnsEmpty() {
        let catalog = BuilderV3ExerciseLibrary.demo
        let result = BuilderV3ExerciseSuggestions.suggestedExercises(
            canvasNames: [],
            catalog: catalog,
            limit: 6
        )
        XCTAssertEqual(result.count, 0, "Empty canvas should return no suggestions")
    }
    
    func testSuggestedExercises_excludesAlreadyPresent() {
        let catalog = BuilderV3ExerciseLibrary.demo
        let canvasNames = ["Bench Press", "Back Squat"]
        let result = BuilderV3ExerciseSuggestions.suggestedExercises(
            canvasNames: canvasNames,
            catalog: catalog,
            limit: 10
        )
        let resultNames = Set(result.map { $0.name })
        XCTAssertFalse(resultNames.contains("Bench Press"), "Should exclude Bench Press (already on canvas)")
        XCTAssertFalse(resultNames.contains("Back Squat"), "Should exclude Back Squat (already on canvas)")
    }
    
    func testSuggestedExercises_scoresByMuscleOverlap() {
        let catalog = BuilderV3ExerciseLibrary.demo
        // Canvas has chest exercises
        let canvasNames = ["Bench Press"]
        let result = BuilderV3ExerciseSuggestions.suggestedExercises(
            canvasNames: canvasNames,
            catalog: catalog,
            limit: 10
        )
        
        // Push Ups should be highly ranked (same muscle: Chest)
        let pushUpsIndex = result.firstIndex { $0.name == "Push Ups" }
        XCTAssertNotNil(pushUpsIndex, "Push Ups should be suggested for chest workout")
        if let index = pushUpsIndex {
            XCTAssertLessThan(index, 5, "Push Ups should rank highly (same muscle)")
        }
    }
    
    func testSuggestedExercises_scoresByEquipmentOverlap() {
        let catalog = BuilderV3ExerciseLibrary.demo
        // Canvas has barbell exercises
        let canvasNames = ["Bench Press", "Deadlift"]
        let result = BuilderV3ExerciseSuggestions.suggestedExercises(
            canvasNames: canvasNames,
            catalog: catalog,
            limit: 10
        )
        
        // Other barbell exercises should rank higher
        let barbellExercises = result.filter { $0.equipmentKey == "barbell" }
        XCTAssertGreaterThan(barbellExercises.count, 0, "Should suggest other barbell exercises")
    }
    
    func testSuggestedExercises_respectsLimit() {
        let catalog = BuilderV3ExerciseLibrary.demo
        let canvasNames = ["Bench Press"]
        let result = BuilderV3ExerciseSuggestions.suggestedExercises(
            canvasNames: canvasNames,
            catalog: catalog,
            limit: 3
        )
        XCTAssertLessThanOrEqual(result.count, 3, "Should respect limit of 3")
    }
    
    func testSuggestedExercises_stableOrdering() {
        let catalog = BuilderV3ExerciseLibrary.demo
        let canvasNames = ["Bench Press"]
        let result1 = BuilderV3ExerciseSuggestions.suggestedExercises(
            canvasNames: canvasNames,
            catalog: catalog,
            limit: 5
        )
        let result2 = BuilderV3ExerciseSuggestions.suggestedExercises(
            canvasNames: canvasNames,
            catalog: catalog,
            limit: 5
        )
        XCTAssertEqual(result1.map(\.name), result2.map(\.name), "Should have stable ordering")
    }
    
    // MARK: - didYouMean tests
    
    func testDidYouMean_exactMatch_returnsNil() {
        let catalog = BuilderV3ExerciseLibrary.demo
        let result = BuilderV3ExerciseSuggestions.didYouMean(query: "Bench Press", catalog: catalog)
        XCTAssertNil(result, "Exact match should return nil")
    }
    
    func testDidYouMean_emptyQuery_returnsNil() {
        let catalog = BuilderV3ExerciseLibrary.demo
        let result = BuilderV3ExerciseSuggestions.didYouMean(query: "", catalog: catalog)
        XCTAssertNil(result, "Empty query should return nil")
    }
    
    func testDidYouMean_whitespaceOnly_returnsNil() {
        let catalog = BuilderV3ExerciseLibrary.demo
        let result = BuilderV3ExerciseSuggestions.didYouMean(query: "   ", catalog: catalog)
        XCTAssertNil(result, "Whitespace-only query should return nil")
    }
    
    func testDidYouMean_missingSpaces_findsMatch() {
        let catalog = BuilderV3ExerciseLibrary.demo
        let result = BuilderV3ExerciseSuggestions.didYouMean(query: "benchpress", catalog: catalog)
        XCTAssertEqual(result, "Bench Press", "Should suggest 'Bench Press' for 'benchpress'")
    }
    
    func testDidYouMean_extraSpaces_findsMatch() {
        let catalog = BuilderV3ExerciseLibrary.demo
        let result = BuilderV3ExerciseSuggestions.didYouMean(query: "bench  press", catalog: catalog)
        XCTAssertEqual(result, "Bench Press", "Should tolerate extra spaces")
    }
    
    func testDidYouMean_caseInsensitive() {
        let catalog = BuilderV3ExerciseLibrary.demo
        let result = BuilderV3ExerciseSuggestions.didYouMean(query: "BENCH PRESS", catalog: catalog)
        XCTAssertEqual(result, "Bench Press", "Should be case-insensitive")
    }
    
    func testDidYouMean_smallTypo_findsMatch() {
        let catalog = BuilderV3ExerciseLibrary.demo
        // "squat" vs "squot" (1 edit distance)
        let result = BuilderV3ExerciseSuggestions.didYouMean(query: "back squot", catalog: catalog)
        XCTAssertEqual(result, "Back Squat", "Should correct small typos")
    }
    
    func testDidYouMean_twoEdits_findsMatch() {
        let catalog = BuilderV3ExerciseLibrary.demo
        // "deadlift" vs "dedlift" (2 edits: missing 'a', wrong 'e')
        let result = BuilderV3ExerciseSuggestions.didYouMean(query: "dedlift", catalog: catalog)
        XCTAssertNotNil(result, "Should tolerate up to 2 edits for queries >4 chars")
    }
    
    func testDidYouMean_largeDistance_returnsNil() {
        let catalog = BuilderV3ExerciseLibrary.demo
        // "xyz" has no close match
        let result = BuilderV3ExerciseSuggestions.didYouMean(query: "xyzabc", catalog: catalog)
        XCTAssertNil(result, "Should return nil for queries with no close match")
    }
    
    func testDidYouMean_shortQuery_noLevenshtein() {
        let catalog = BuilderV3ExerciseLibrary.demo
        // Short queries (≤4 chars) don't use Levenshtein, only space normalization
        let result = BuilderV3ExerciseSuggestions.didYouMean(query: "sqat", catalog: catalog)
        XCTAssertNil(result, "Short queries with typos should return nil (no Levenshtein)")
    }
}
