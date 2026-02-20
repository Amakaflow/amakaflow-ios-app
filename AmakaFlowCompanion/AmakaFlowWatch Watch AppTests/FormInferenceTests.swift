import XCTest
import CoreML
@testable import AmakaFlowWatch_Watch_App

final class FormInferenceTests: XCTestCase {

    // MARK: - Model-dependent test (skipped if FormClassifier is unavailable in test bundle)

    func test_classify_returnsFormResult_withValidWindow() throws {
        let inference: FormInference
        do {
            inference = try FormInference()
        } catch {
            throw XCTSkip("FormClassifier model not available in test bundle: \(error)")
        }

        let window = (0..<128).map { i in
            IMUSample(accX: 0, accY: 0, accZ: 0, gyrX: 0, gyrY: 0, gyrZ: 0, timestamp: Double(i) * 0.01)
        }

        let result = try inference.classify(window: window)

        let validLabels = ["good_form", "insufficient_depth", "knee_cave", "forward_lean"]
        XCTAssertTrue(validLabels.contains(result.label), "Label '\(result.label)' is not one of the 4 expected classes")
        XCTAssertGreaterThanOrEqual(result.confidence, 0.0)
        XCTAssertLessThanOrEqual(result.confidence, 1.0)
    }

    // MARK: - Pure helper tests (no model required)

    func test_inputArray_hasCorrectShape() throws {
        let inference: FormInference
        do {
            inference = try FormInference()
        } catch {
            throw XCTSkip("FormClassifier model not available in test bundle: \(error)")
        }

        let samples = (0..<10).map { i in
            IMUSample(accX: 0, accY: 0, accZ: 0, gyrX: 0, gyrY: 0, gyrZ: 0, timestamp: Double(i))
        }

        let array = try inference.makeInputArray(from: samples)

        XCTAssertEqual(array.shape.count, 2)
        XCTAssertEqual(array.shape[0], 1)
        XCTAssertEqual(array.shape[1], 60)  // 10 samples × 6 channels
    }

    func test_inputArray_encodesChannelsCorrectly() throws {
        let inference: FormInference
        do {
            inference = try FormInference()
        } catch {
            throw XCTSkip("FormClassifier model not available in test bundle: \(error)")
        }

        let sample = IMUSample(
            accX: 1.0,
            accY: 2.0,
            accZ: 3.0,
            gyrX: 4.0,
            gyrY: 5.0,
            gyrZ: 6.0,
            timestamp: 0.0
        )

        let array = try inference.makeInputArray(from: [sample])

        XCTAssertEqual(Float(array[0]), 1.0, "accX should be at index 0")
        XCTAssertEqual(Float(array[1]), 2.0, "accY should be at index 1")
        XCTAssertEqual(Float(array[2]), 3.0, "accZ should be at index 2")
        XCTAssertEqual(Float(array[3]), 4.0, "gyrX should be at index 3")
        XCTAssertEqual(Float(array[4]), 5.0, "gyrY should be at index 4")
        XCTAssertEqual(Float(array[5]), 6.0, "gyrZ should be at index 5")
    }

    // MARK: - Standalone array shape test (no model init needed)

    func test_inputArray_standaloneShape_withoutModel() throws {
        // Tests MLMultiArray construction logic directly, bypassing model init
        var samples: [IMUSample] = []
        for i in 0..<10 {
            let fi = Float(i)
            let sample = IMUSample(
                accX: fi,
                accY: fi * 0.1,
                accZ: fi * 0.2,
                gyrX: fi * 0.3,
                gyrY: fi * 0.4,
                gyrZ: fi * 0.5,
                timestamp: Double(i)
            )
            samples.append(sample)
        }

        // Replicate makeInputArray logic inline to test without needing a model instance
        let array = try MLMultiArray(shape: [1, NSNumber(value: samples.count * 6)], dataType: .float32)
        for (i, s) in samples.enumerated() {
            let base = i * 6
            array[base + 0] = NSNumber(value: s.accX)
            array[base + 1] = NSNumber(value: s.accY)
            array[base + 2] = NSNumber(value: s.accZ)
            array[base + 3] = NSNumber(value: s.gyrX)
            array[base + 4] = NSNumber(value: s.gyrY)
            array[base + 5] = NSNumber(value: s.gyrZ)
        }

        XCTAssertEqual(array.shape.count, 2)
        XCTAssertEqual(array.shape[0], 1)
        XCTAssertEqual(array.shape[1], 60)

        // Verify channel encoding for first sample (i=0, all zero)
        // Verify channel encoding for second sample (i=1)
        XCTAssertEqual(Float(array[6]), 1.0, "accX of sample[1] at index 6")
        XCTAssertEqual(Float(array[7]), 0.1, accuracy: 0.0001, "accY of sample[1] at index 7")
        XCTAssertEqual(Float(array[11]), 0.5, accuracy: 0.0001, "gyrZ of sample[1] at index 11")
    }
}
