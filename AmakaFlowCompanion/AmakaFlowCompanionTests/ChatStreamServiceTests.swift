//
//  ChatStreamServiceTests.swift
//  AmakaFlowCompanionTests
//
//  Tests for SSE streaming models and parsing (AMA-1410)
//

import XCTest
@testable import AmakaFlowCompanion

final class ChatStreamServiceTests: XCTestCase {

    // MARK: - Model Tests

    func testChatStageDisplayNames() {
        XCTAssertEqual(ChatStage.analyzing.displayName, "Analyzing")
        XCTAssertEqual(ChatStage.complete.displayName, "Complete")
    }

    func testChatStageIcons() {
        XCTAssertEqual(ChatStage.searching.iconName, "magnifyingglass")
        XCTAssertEqual(ChatStage.creating.iconName, "dumbbell.fill")
    }

    func testToolCallDisplayNames() {
        let searchTool = ChatToolCall(id: "t1", name: "search_workout_library", status: .running)
        XCTAssertEqual(searchTool.displayName, "Searching workouts")

        let unknownTool = ChatToolCall(id: "t2", name: "some_future_tool", status: .pending)
        XCTAssertEqual(unknownTool.displayName, "Working")
    }

    func testToolCallIcons() {
        let calendarTool = ChatToolCall(id: "t1", name: "get_calendar_events", status: .completed)
        XCTAssertEqual(calendarTool.iconName, "calendar")

        let unknownTool = ChatToolCall(id: "t2", name: "unknown", status: .pending)
        XCTAssertEqual(unknownTool.iconName, "wrench.fill")
    }

    func testGeneratedWorkoutDecoding() throws {
        let json = """
        {
            "name": "Upper Body Push",
            "duration": "45 min",
            "difficulty": "Intermediate",
            "exercises": [
                {"name": "Bench Press", "sets": 4, "reps": "8", "muscle_group": "Chest", "notes": null},
                {"name": "OHP", "sets": 3, "reps": "10", "muscle_group": "Shoulders", "notes": "Strict form"}
            ]
        }
        """.data(using: .utf8)!

        let workout = try JSONDecoder().decode(GeneratedWorkout.self, from: json)
        XCTAssertEqual(workout.name, "Upper Body Push")
        XCTAssertEqual(workout.exercises.count, 2)
        XCTAssertEqual(workout.exercises[0].muscleGroup, "Chest")
        XCTAssertEqual(workout.exercises[1].notes, "Strict form")
    }

    func testWorkoutSearchResultDecoding() throws {
        let json = """
        {"id": "w1", "name": "HIIT Blast", "duration": "30 min", "exercise_count": 8}
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(WorkoutSearchResult.self, from: json)
        XCTAssertEqual(result.id, "w1")
        XCTAssertEqual(result.exerciseCount, 8)
    }
}
