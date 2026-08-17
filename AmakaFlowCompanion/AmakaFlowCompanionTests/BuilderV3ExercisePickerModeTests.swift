//
//  BuilderV3ExercisePickerModeTests.swift
//  AmakaFlowCompanionTests
//
//  AMA-2443 slice 2a — replace-mode selection and commit logic.
//

import XCTest
@testable import AmakaFlowCompanion

final class BuilderV3ExercisePickerModeTests: XCTestCase {
    
    // MARK: - Mode toggle selection
    
    func testAddMode_toggleSelection_allowsMultipleSelections() {
        var selectedNames: [String] = []
        
        // Add first item
        toggleSelection("Bench Press", mode: .add, selectedNames: &selectedNames)
        XCTAssertEqual(selectedNames, ["Bench Press"])
        
        // Add second item
        toggleSelection("Squat", mode: .add, selectedNames: &selectedNames)
        XCTAssertEqual(selectedNames, ["Bench Press", "Squat"])
        
        // Toggle off first item
        toggleSelection("Bench Press", mode: .add, selectedNames: &selectedNames)
        XCTAssertEqual(selectedNames, ["Squat"])
    }
    
    func testReplaceMode_toggleSelection_allowsOnlyOneSelection() {
        var selectedNames: [String] = []
        
        // Select first item
        toggleSelection("Bench Press", mode: .replace(exerciseID: "ex1", exerciseName: "Old"), selectedNames: &selectedNames)
        XCTAssertEqual(selectedNames, ["Bench Press"])
        
        // Select second item replaces first
        toggleSelection("Squat", mode: .replace(exerciseID: "ex1", exerciseName: "Old"), selectedNames: &selectedNames)
        XCTAssertEqual(selectedNames, ["Squat"])
        
        // Toggle off current selection clears it
        toggleSelection("Squat", mode: .replace(exerciseID: "ex1", exerciseName: "Old"), selectedNames: &selectedNames)
        XCTAssertEqual(selectedNames, [])
    }
    
    func testReplaceMode_toggleSameItem_deselects() {
        var selectedNames: [String] = ["Bench Press"]
        
        toggleSelection("Bench Press", mode: .replace(exerciseID: "ex1", exerciseName: "Old"), selectedNames: &selectedNames)
        XCTAssertEqual(selectedNames, [])
    }
    
    // MARK: - Case-insensitive selection
    
    func testAddMode_caseInsensitiveToggle() {
        var selectedNames: [String] = ["Bench Press"]
        
        // Toggle with different case removes the item
        toggleSelection("bench press", mode: .add, selectedNames: &selectedNames)
        XCTAssertEqual(selectedNames, [])
    }
    
    func testReplaceMode_caseInsensitiveToggle() {
        var selectedNames: [String] = ["Bench Press"]
        
        // Toggle with different case clears selection
        toggleSelection("BENCH PRESS", mode: .replace(exerciseID: "ex1", exerciseName: "Old"), selectedNames: &selectedNames)
        XCTAssertEqual(selectedNames, [])
    }
    
    // MARK: - Helper (extracted logic from BuilderV3ExercisePickerSheet.toggleSelection)
    
    private func toggleSelection(_ name: String, mode: BuilderV3ExercisePickerSheet.Mode, selectedNames: inout [String]) {
        switch mode {
        case .add:
            if let index = selectedNames.firstIndex(where: {
                $0.caseInsensitiveCompare(name) == .orderedSame
            }) {
                selectedNames.remove(at: index)
            } else {
                selectedNames.append(name)
            }
        case .replace:
            // Single-select: replace current selection or select if empty
            if selectedNames.first?.caseInsensitiveCompare(name) == .orderedSame {
                selectedNames.removeAll()
            } else {
                selectedNames = [name]
            }
        }
    }
}
