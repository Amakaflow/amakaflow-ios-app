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
        XCTAssertEqual(coach.cueType(for: result), .asymmetryWarning)
    }

    func test_cueType_stop_whenConfidenceLow() {
        let coach = HapticCoach()
        let result = FormResult(label: "insufficient_depth", confidence: 0.30)
        XCTAssertEqual(coach.cueType(for: result), .stop)
    }

    func test_cueType_stop_atStopThresholdBoundary() {
        let coach = HapticCoach()
        // Just below stop threshold → .stop
        XCTAssertEqual(coach.cueType(for: FormResult(label: "insufficient_depth", confidence: 0.3999)), .stop)
        // At stop threshold → falls through to switch, not .stop
        XCTAssertNotEqual(coach.cueType(for: FormResult(label: "insufficient_depth", confidence: 0.40)), .stop)
    }

    func test_cueType_goodRep_forGoodForm() {
        let coach = HapticCoach()
        let result = FormResult(label: "good_form", confidence: 0.95)
        XCTAssertEqual(coach.cueType(for: result), .goodRep)
    }

    func test_cueType_fatigueWarning_forFatigueLabel() {
        let coach = HapticCoach()
        let result = FormResult(label: "fatigue", confidence: 0.80)
        XCTAssertEqual(coach.cueType(for: result), .fatigueWarning)
    }

    func test_cueType_tempoTooFast_forTempoLabel() {
        let coach = HapticCoach()
        let result = FormResult(label: "tempo_too_fast", confidence: 0.80)
        XCTAssertEqual(coach.cueType(for: result), .tempoTooFast)
    }

    func test_allSixCueCasesMappable() {
        let coach = HapticCoach()
        let mappings: [(String, Float, HapticCue)] = [
            ("insufficient_depth", 0.9, .depthPrompt),
            ("insufficient_depth", 0.3, .stop),
            ("knee_cave", 0.9, .asymmetryWarning),
            ("tempo_too_fast", 0.8, .tempoTooFast),
            ("good_form", 0.95, .goodRep),
            ("fatigue", 0.8, .fatigueWarning)
        ]
        for (label, confidence, expected) in mappings {
            XCTAssertEqual(coach.cueType(for: FormResult(label: label, confidence: confidence)), expected, "Failed for label: \(label)")
        }
    }
}
