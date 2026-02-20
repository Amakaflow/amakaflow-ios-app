import CoreML
import Foundation

/// Wraps the FormClassifier Core ML model and converts [IMUSample] → FormResult.
struct FormInference {
    private let model: MLModel

    init() throws {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine
        model = try FormClassifier(configuration: config).model
    }

    /// Classify a fixed-length window of IMU samples.
    /// - Parameter window: Exactly `windowSize` samples (128 by default).
    /// - Returns: FormResult with top-class label and its softmax confidence.
    func classify(window: [IMUSample]) throws -> FormResult {
        let inputArray = try makeInputArray(from: window)
        let input = try MLDictionaryFeatureProvider(dictionary: ["input": inputArray])
        let output = try model.prediction(from: input)
        return topResult(from: output)
    }

    // MARK: - Private

    func makeInputArray(from samples: [IMUSample]) throws -> MLMultiArray {
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
        return array
    }

    private let classes = ["good_form", "insufficient_depth", "knee_cave", "forward_lean"]

    private func topResult(from output: MLFeatureProvider) -> FormResult {
        guard let probs = output.featureValue(for: "output")?.multiArrayValue else {
            return FormResult(label: "good_form", confidence: 0)
        }
        var best = (index: 0, value: Float(probs[0]))
        for i in 1..<classes.count {
            let v = Float(probs[i])
            if v > best.value { best = (i, v) }
        }
        return FormResult(label: classes[best.index], confidence: best.value)
    }
}
