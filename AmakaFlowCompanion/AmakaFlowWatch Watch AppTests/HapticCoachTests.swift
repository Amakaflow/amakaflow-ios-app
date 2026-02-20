import XCTest
@testable import AmakaFlowWatch_Watch_App

final class HapticCoachTests: XCTestCase {

    func test_shouldCue_returnsTrue_forDepthDeviation() {
        let coach = HapticCoach()
        let result = FormResult(label: "insufficient_depth", confidence: 0.9)
        XCTAssertTrue(coach.shouldCue(for: result))
    }

    func test_shouldCue_returnsFalse_forGoodForm() {
        let coach = HapticCoach()
        let result = FormResult(label: "good", confidence: 0.95)
        XCTAssertFalse(coach.shouldCue(for: result))
    }

    func test_shouldCue_returnsFalse_belowConfidenceThreshold() {
        let coach = HapticCoach()
        let result = FormResult(label: "insufficient_depth", confidence: 0.4)
        XCTAssertFalse(coach.shouldCue(for: result))
    }

    func test_cueType_forDepthDeviation() {
        let coach = HapticCoach()
        let result = FormResult(label: "insufficient_depth", confidence: 0.9)
        XCTAssertEqual(coach.cueType(for: result), .depthPrompt)
    }

    func test_cueType_forKneeCave() {
        let coach = HapticCoach()
        let result = FormResult(label: "knee_cave", confidence: 0.9)
        XCTAssertEqual(coach.cueType(for: result), .asymmetryWarning)
    }

    func test_cueType_forForwardLean() {
        let coach = HapticCoach()
        let result = FormResult(label: "forward_lean", confidence: 0.9)
        XCTAssertEqual(coach.cueType(for: result), .tempoTooFast)
    }

    func test_allCueTypes_areCovered() {
        XCTAssertEqual(HapticCue.allCases.count, 6)
    }
}
