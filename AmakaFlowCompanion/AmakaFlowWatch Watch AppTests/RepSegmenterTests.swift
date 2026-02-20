import XCTest
@testable import AmakaFlowWatch_Watch_App

@MainActor
final class RepSegmenterTests: XCTestCase {

    private func makeSamples(yValues: [Float]) -> [IMUSample] {
        yValues.enumerated().map { i, y in
            IMUSample(accX: 0, accY: y, accZ: 0, gyrX: 0, gyrY: 0, gyrZ: 0, timestamp: Double(i) * 0.01)
        }
    }

    func test_noReps_whenBufferTooShort() {
        let segmenter = RepSegmenter()
        let samples = makeSamples(yValues: Array(repeating: Float(0.5), count: 10))
        XCTAssertTrue(segmenter.extractReps(from: samples).isEmpty)
    }

    func test_detectsOneRep_withClearValley() {
        let segmenter = RepSegmenter()
        // Two clear peaks with a valley in between = one rep
        var yValues: [Float] = Array(repeating: 1.0, count: 20)   // standing
        yValues += Array(repeating: -1.0, count: 20)               // squatting
        yValues += Array(repeating: 1.0, count: 20)                // standing again
        let reps = segmenter.extractReps(from: makeSamples(yValues: yValues))
        XCTAssertEqual(reps.count, 1)
    }

    func test_repWindow_hasCorrectedSize() throws {
        let segmenter = RepSegmenter(windowSize: 50)
        var yValues: [Float] = Array(repeating: Float(1.0), count: 20)
        yValues += Array(repeating: Float(-1.0), count: 20)
        yValues += Array(repeating: Float(1.0), count: 20)
        let reps = segmenter.extractReps(from: makeSamples(yValues: yValues))
        XCTAssertEqual(reps.count, 1)
        let rep = try XCTUnwrap(reps.first)
        XCTAssertEqual(rep.count, segmenter.windowSize)
    }

    func test_detectsMultipleReps_withThreePeaks() {
        let segmenter = RepSegmenter()
        // Three peaks separated by valleys = two rep windows
        var yValues: [Float] = Array(repeating: 1.5, count: 20)   // peak 1
        yValues += Array(repeating: -0.5, count: 20)               // valley
        yValues += Array(repeating: 1.5, count: 20)                // peak 2
        yValues += Array(repeating: -0.5, count: 20)               // valley
        yValues += Array(repeating: 1.5, count: 20)                // peak 3
        let reps = segmenter.extractReps(from: makeSamples(yValues: yValues))
        XCTAssertGreaterThanOrEqual(reps.count, 2)
    }

    func test_noReps_whenSignalBelowThreshold() {
        // Signal that never exceeds peak threshold should produce no reps
        let segmenter = RepSegmenter()
        let yValues: [Float] = Array(repeating: 0.1, count: 100)
        let reps = segmenter.extractReps(from: makeSamples(yValues: yValues))
        XCTAssertTrue(reps.isEmpty)
    }
}
