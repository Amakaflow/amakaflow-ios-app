import XCTest
@testable import AmakaFlowWatch_Watch_App

@MainActor
final class MotionCaptureTests: XCTestCase {

    func test_motionCapture_initialises_with_100Hz() {
        let capture = MotionCapture()
        XCTAssertEqual(capture.sampleRate, 100.0)
    }

    func test_motionCapture_buffer_is_empty_initially() {
        let capture = MotionCapture()
        XCTAssertTrue(capture.buffer.isEmpty)
    }

    func test_motionCapture_appends_sample_to_buffer() {
        let capture = MotionCapture()
        let sample = IMUSample(
            accX: 0.1, accY: -0.9, accZ: 0.05,
            gyrX: 0.01, gyrY: 0.02, gyrZ: 0.0,
            timestamp: 0.0
        )
        capture.appendSample(sample)
        XCTAssertEqual(capture.buffer.count, 1)
    }

    func test_motionCapture_trims_buffer_to_maxSize() {
        let capture = MotionCapture(maxBufferSize: 5)
        for i in 0..<10 {
            capture.appendSample(IMUSample(
                accX: 0, accY: 0, accZ: 0,
                gyrX: 0, gyrY: 0, gyrZ: 0,
                timestamp: Double(i)
            ))
        }
        XCTAssertEqual(capture.buffer.count, 5)
    }

    func test_motionCapture_isCapturing_false_initially() {
        let capture = MotionCapture()
        XCTAssertFalse(capture.isCapturing)
    }
}
